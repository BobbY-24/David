import hashlib
import json
import time
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .db import session_factory
from .errors import IdempotencyConflict, PermanentJobError, QueueFull, TransientJobError
from .metrics import snapshot as metrics_snapshot
from .runners import run
from .schema import Job
from .settings import lease_seconds, max_attempts, queue_cap, retry_backoff_seconds


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def payload_hash(kind: str, spec: dict) -> str:
    body = json.dumps({"kind": kind, "spec": spec}, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(body.encode()).hexdigest()


def job_view(job: Job) -> dict:
    result = job.result or {}
    return {
        "id": job.id,
        "kind": job.kind,
        "spec": job.spec,
        "status": job.status,
        "attempts": job.attempts,
        "max_attempts": job.max_attempts,
        "queued_at": job.queued_at.isoformat(),
        "started_at": job.started_at.isoformat() if job.started_at else None,
        "finished_at": job.finished_at.isoformat() if job.finished_at else None,
        "queue_wait_ms": job.queue_wait_ms,
        "e2e_ms": job.e2e_ms,
        "headline": result.get("headline"),
        "detail": result.get("detail"),
        "lead": result.get("lead"),
        "result": job.result,
        "error": job.error,
    }


class JobService:
    """Postgres is the job record. Redis only carries the wake-up.

    A claim is a conditional update, so a duplicate delivery or a crash
    retry cannot complete the same attempt twice. Permanent errors die
    immediately. Transient errors requeue until max_attempts.
    """

    def __init__(self, factory=None, cap: int | None = None, dispatch=None, dispatch_later=None) -> None:
        self._factory = factory or session_factory
        self.cap = queue_cap() if cap is None else cap
        self.dispatch = dispatch or (lambda job_id: None)
        # A retry is scheduled on the broker, not slept on, so a backing-off
        # job does not hold a worker slot. Without a scheduler, wake now.
        self.dispatch_later = dispatch_later or (lambda job_id, _delay: self.dispatch(job_id))

    def session(self) -> Session:
        return self._factory()

    def enqueue(self, kind: str, spec: dict, idempotency_key: str) -> tuple[dict, bool]:
        digest = payload_hash(kind, spec)
        session = self.session()
        created = False
        try:
            session.execute(text("SELECT pg_advisory_xact_lock(481516)"))
            existing = session.scalar(select(Job).where(Job.idempotency_key == idempotency_key))
            if existing is not None:
                if existing.payload_hash != digest:
                    raise IdempotencyConflict()
                view = job_view(existing)
                session.rollback()
                return view, False
            depth = session.scalar(
                select(func.count()).select_from(Job).where(Job.status.in_(("queued", "running")))
            )
            depth = int(depth or 0)
            if depth >= self.cap:
                raise QueueFull(self.cap, depth)
            job = Job(
                idempotency_key=idempotency_key,
                payload_hash=digest,
                kind=kind,
                spec=spec,
                status="queued",
                attempts=0,
                max_attempts=max_attempts(),
                queued_at=utcnow(),
            )
            session.add(job)
            session.commit()
            created = True
            view = job_view(job)
        except IntegrityError:
            session.rollback()
            existing = session.scalar(select(Job).where(Job.idempotency_key == idempotency_key))
            if existing is None:
                raise
            if existing.payload_hash != digest:
                raise IdempotencyConflict() from None
            return job_view(existing), False
        finally:
            session.close()
        if created:
            self._wake(view["id"])
        return view, created

    def _mark_dispatched(self, job_id: str) -> None:
        session = self.session()
        try:
            job = session.get(Job, job_id)
            if job is not None and job.status == "queued":
                job.dispatched_at = utcnow()
                session.commit()
        finally:
            session.close()

    def claim(self, job_id: str, token: str) -> dict | None:
        session = self.session()
        try:
            job = session.scalar(
                select(Job).where(Job.id == job_id, Job.status == "queued").with_for_update(skip_locked=True)
            )
            if job is None:
                session.rollback()
                return None
            job.status = "running"
            job.started_at = utcnow()
            job.worker_token = token
            job.attempts = job.attempts + 1
            session.commit()
            return job_view(job) | {"attempts": job.attempts, "spec": job.spec, "kind": job.kind}
        finally:
            session.close()

    def execute(self, job_id: str) -> None:
        token = uuid.uuid4().hex
        claimed = self.claim(job_id, token)
        if claimed is None:
            return
        fail_times = int((claimed["spec"] or {}).get("fail_times") or 0)
        sleep_ms = int((claimed["spec"] or {}).get("sleep_ms") or 0)
        if sleep_ms > 0:
            time.sleep(sleep_ms / 1000.0)
        try:
            if claimed["attempts"] <= fail_times:
                raise TransientJobError(f"Injected failure on attempt {claimed['attempts']}.")
            session = self.session()
            try:
                result = run(claimed["kind"], claimed["spec"], session)
                session.commit()
            finally:
                session.close()
            self._succeed(job_id, token, result)
        except TransientJobError as exc:
            action = self._fail(job_id, token, str(exc), retry=True)
            if action == "requeue":
                self._wake(job_id, delay=_backoff(claimed["attempts"]))
        except PermanentJobError as exc:
            self._fail(job_id, token, str(exc), retry=False)
        except Exception as exc:
            self._fail(job_id, token, str(exc), retry=False)

    def _succeed(self, job_id: str, token: str, result: dict) -> None:
        session = self.session()
        try:
            job = session.scalar(
                select(Job).where(Job.id == job_id, Job.status == "running", Job.worker_token == token)
            )
            if job is None:
                session.rollback()
                return
            finished = utcnow()
            job.status = "succeeded"
            job.finished_at = finished
            job.result = result
            job.error = None
            job.queue_wait_ms = _millis(job.started_at, job.queued_at)
            job.e2e_ms = _millis(finished, job.queued_at)
            session.commit()
        finally:
            session.close()

    def _fail(self, job_id: str, token: str, message: str, retry: bool) -> str:
        session = self.session()
        try:
            job = session.scalar(
                select(Job).where(Job.id == job_id, Job.status == "running", Job.worker_token == token)
            )
            if job is None:
                session.rollback()
                return "lost"
            job.error = message
            if retry and job.attempts < job.max_attempts:
                job.status = "queued"
                job.worker_token = None
                job.started_at = None
                job.dispatched_at = None
                session.commit()
                return "requeue"
            job.status = "dead"
            job.finished_at = utcnow()
            job.e2e_ms = _millis(job.finished_at, job.queued_at)
            session.commit()
            return "dead"
        finally:
            session.close()

    def get(self, job_id: str) -> dict | None:
        session = self.session()
        try:
            job = session.get(Job, job_id)
            return None if job is None else job_view(job)
        finally:
            session.close()

    def list_jobs(self, limit: int = 20) -> list[dict]:
        session = self.session()
        try:
            rows = session.scalars(select(Job).order_by(Job.queued_at.desc()).limit(limit))
            return [job_view(row) for row in rows]
        finally:
            session.close()

    def metrics(self) -> dict:
        session = self.session()
        try:
            return metrics_snapshot(session)
        finally:
            session.close()

    def reclaim_expired(self) -> list[str]:
        cutoff = utcnow() - timedelta(seconds=lease_seconds())
        session = self.session()
        ids: list[str] = []
        try:
            rows = session.scalars(
                select(Job).where(Job.status == "running", Job.started_at.is_not(None), Job.started_at < cutoff)
            )
            for job in rows:
                if job.attempts >= job.max_attempts:
                    job.status = "dead"
                    job.finished_at = utcnow()
                    job.error = job.error or "Lease expired after the last attempt."
                else:
                    job.status = "queued"
                    job.worker_token = None
                    job.started_at = None
                    job.dispatched_at = None
                    job.error = "Lease expired. Requeued."
                    ids.append(job.id)
            quiet = utcnow() - timedelta(seconds=2)
            stale = utcnow() - timedelta(seconds=lease_seconds())
            stuck = session.scalars(
                select(Job).where(
                    Job.status == "queued",
                    Job.queued_at < quiet,
                    (Job.dispatched_at.is_(None)) | (Job.dispatched_at < stale),
                )
            )
            for job in stuck:
                job.dispatched_at = None
                ids.append(job.id)
            session.commit()
        finally:
            session.close()
        for job_id in ids:
            self._wake(job_id)
        return ids

    def _wake(self, job_id: str, delay: float = 0.0) -> None:
        try:
            if delay > 0:
                self.dispatch_later(job_id, delay)
            else:
                self.dispatch(job_id)
        except Exception:
            return
        self._mark_dispatched(job_id)


def _millis(end: datetime | None, start: datetime | None) -> float | None:
    if end is None or start is None:
        return None
    return (end - start).total_seconds() * 1000.0


def _backoff(attempt: int) -> float:
    base = retry_backoff_seconds()
    return min(8.0, base * (2 ** max(0, attempt - 1)))


def init_db() -> None:
    from .db import Base, get_engine

    Base.metadata.create_all(get_engine())
