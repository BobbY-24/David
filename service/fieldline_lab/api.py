import json
import logging
import threading
from contextlib import asynccontextmanager

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field
from sqlalchemy import text

from .db import session_factory
from .errors import IdempotencyConflict, QueueFull
from .metrics import prometheus
from .runners import catalog
from .service import JobService, init_db
from .settings import sweep_enabled
from .worker import dispatch_job

log = logging.getLogger("fieldline")
logging.basicConfig(level=logging.INFO, format="%(message)s")

service = JobService(dispatch=dispatch_job)


class JobRequest(BaseModel):
    kind: str = Field(min_length=1, max_length=40)
    spec: dict = Field(default_factory=dict)


def _event(event: str, **fields) -> None:
    log.info(json.dumps({"event": event, **fields}, default=str))


def _sweep(stop: threading.Event) -> None:
    while not stop.wait(2.0):
        try:
            reclaimed = service.reclaim_expired()
            if reclaimed:
                _event("lease_reclaim", jobs=reclaimed)
        except Exception as exc:
            _event("sweep_error", error=str(exc))


@asynccontextmanager
async def lifespan(_app: FastAPI):
    init_db()
    stop = threading.Event()
    thread = None
    if sweep_enabled():
        thread = threading.Thread(target=_sweep, args=(stop,), name="fieldline-sweep", daemon=True)
        thread.start()
    _event("api_start", scorer="fixture-scorer-v1")
    yield
    stop.set()
    if thread is not None:
        thread.join(timeout=1)


app = FastAPI(title="David jobs", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/v1/health")
def health():
    session = session_factory()
    try:
        session.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Database is not reachable: {exc}") from exc
    finally:
        session.close()
    return {"ok": True, "database": "up", "scorer": "fixture-scorer-v1"}


@app.get("/v1/catalog")
def get_catalog():
    return {"items": catalog(), "scorer": "fixture-scorer-v1"}


@app.post("/v1/jobs", status_code=202)
def create_job(body: JobRequest, idempotency_key: str | None = Header(default=None, alias="Idempotency-Key")):
    if not idempotency_key or not idempotency_key.strip():
        raise HTTPException(status_code=400, detail="Idempotency-Key is required.")
    try:
        view, created = service.enqueue(body.kind, body.spec, idempotency_key.strip())
    except QueueFull as exc:
        _event("queue_full", cap=exc.cap, depth=exc.depth)
        raise HTTPException(status_code=429, detail=str(exc)) from exc
    except IdempotencyConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    _event("job_enqueued", job_id=view["id"], kind=view["kind"], created=created)
    return view


@app.get("/v1/jobs/{job_id}")
def read_job(job_id: str):
    view = service.get(job_id)
    if view is None:
        raise HTTPException(status_code=404, detail="No job with that id.")
    return view


@app.get("/v1/jobs")
def list_jobs():
    return {"jobs": service.list_jobs()}


@app.get("/v1/metrics")
def metrics_json():
    return service.metrics()


@app.get("/metrics")
def metrics_prom():
    return PlainTextResponse(prometheus(service.metrics()), media_type="text/plain; version=0.0.4")
