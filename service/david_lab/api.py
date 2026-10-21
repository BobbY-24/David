import hmac
import json
import logging
import re
import threading
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse
from pydantic import BaseModel, Field
from sqlalchemy import text

from . import SCORER_ID, llm
from .db import session_factory
from .errors import IdempotencyConflict, QueueFull
from .metrics import prometheus
from .runners import _CASES, catalog
from .service import JobService, init_db
from .settings import api_token, cors_origins, sweep_enabled
from .engagements import EngagementStore, EvidenceIn, Intake
from .specs import Profile, Spec, SpecError, SpecStore
from .vault import KeyMissing, KeyUnreadable, Vault, VaultError, VaultUnavailable
from .worker import dispatch_job, dispatch_job_later

log = logging.getLogger("david")
logging.basicConfig(level=logging.INFO, format="%(message)s")

service = JobService(dispatch=dispatch_job, dispatch_later=dispatch_job_later)
vault = Vault()
specs = SpecStore()
user_engagements = EngagementStore(vault=vault, specs=specs)
meter = llm.UsageMeter()

_KEY_PATTERN = re.compile(r"sk-ant-[A-Za-z0-9_\-]{16,380}")


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
        thread = threading.Thread(target=_sweep, args=(stop,), name="david-sweep", daemon=True)
        thread.start()
    _event("api_start", scorer=SCORER_ID)
    yield
    stop.set()
    if thread is not None:
        thread.join(timeout=1)


app = FastAPI(title="David jobs", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins(),
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Content-Type", "Idempotency-Key", "X-David-Token"],
)


@app.exception_handler(RequestValidationError)
async def _validation_error(_request, exc: RequestValidationError):
    # The default body repeats the submitted value, which could be an API key.
    errors = [{"loc": list(e.get("loc", [])), "msg": e.get("msg"), "type": e.get("type")} for e in exc.errors()]
    return JSONResponse(status_code=422, content={"detail": errors})


def require_token(x_david_token: str | None = Header(default=None, alias="X-David-Token")) -> None:
    """Optional shared secret. When DAVID_API_TOKEN is set, vault and model routes need it."""
    expected = api_token()
    if expected is None:
        return
    if x_david_token is None or not hmac.compare_digest(x_david_token.encode(), expected.encode()):
        raise HTTPException(status_code=401, detail={"code": "token_required", "message": "A valid X-David-Token header is required."})


_STATUS = {
    "key_rejected": 400, "key_format": 400, "admin_key": 400, "bad_request": 400,
    "model_unreachable": 502, "model_output_invalid": 502, "model_busy": 429,
    "daily_cap_reached": 429, "model_refused": 422, "key_missing": 409,
    "key_unreadable": 409, "vault_unavailable": 503,
}


def _fail(code: str, message: str, status: int | None = None, headers: dict | None = None) -> HTTPException:
    return HTTPException(status_code=status or _STATUS.get(code, 400), detail={"code": code, "message": message}, headers=headers)


def _model_http(exc: llm.ModelError) -> HTTPException:
    headers = {"Retry-After": str(exc.retry_after)} if isinstance(exc, llm.ModelBusy) else None
    return _fail(exc.code, str(exc), headers=headers)


def _vault_http(exc: VaultError) -> HTTPException:
    if isinstance(exc, KeyMissing):
        return _fail("key_missing", str(exc))
    if isinstance(exc, KeyUnreadable):
        return _fail("key_unreadable", str(exc))
    return _fail("vault_unavailable", str(exc))


def _vault_view() -> dict:
    return {
        "vault": vault.readiness(),
        "anthropic": vault.status(llm.PROVIDER),
        "usage": meter.snapshot(),
        "models": list(llm.ALLOWED_MODELS),
        "default_model": llm.DEFAULT_MODEL,
    }


@app.get("/v1/health")
def health():
    session = session_factory()
    try:
        session.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Database is not reachable: {exc}") from exc
    finally:
        session.close()
    return {"ok": True, "database": "up", "scorer": SCORER_ID}


@app.get("/v1/catalog")
def get_catalog():
    return {"items": catalog(), "scorer": SCORER_ID}


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


@app.get("/v1/vault")
def vault_status(_auth: None = Depends(require_token)):
    return _vault_view()


class KeyBody(BaseModel):
    key: str = Field(min_length=1, max_length=400)


@app.put("/v1/vault/anthropic")
def save_key(body: KeyBody, _auth: None = Depends(require_token)):
    key = body.key.strip()
    if key.startswith("sk-ant-admin"):
        raise _fail("admin_key", "That is an admin key. Use a regular API key that can only call models.")
    if not _KEY_PATTERN.fullmatch(key):
        raise _fail("key_format", "This does not look like an Anthropic API key.")
    ready = vault.readiness()
    if not ready["ready"]:
        raise _fail("vault_unavailable", ready["reason"] or "The key vault is not available.")
    try:
        llm.verify_key(key)
    except llm.ModelError as exc:
        raise _model_http(exc) from None
    try:
        vault.put(llm.PROVIDER, key)
    except VaultError as exc:
        raise _vault_http(exc) from None
    vault.mark_verified(llm.PROVIDER)
    _event("vault_key_saved", provider=llm.PROVIDER)
    return _vault_view()


@app.post("/v1/vault/anthropic/verify")
def verify_saved_key(_auth: None = Depends(require_token)):
    try:
        key = vault.get(llm.PROVIDER)
        llm.verify_key(key)
    except VaultError as exc:
        raise _vault_http(exc) from None
    except llm.ModelError as exc:
        raise _model_http(exc) from None
    vault.mark_verified(llm.PROVIDER)
    return _vault_view()


@app.delete("/v1/vault/anthropic")
def remove_key(_auth: None = Depends(require_token)):
    removed = vault.delete(llm.PROVIDER)
    _event("vault_key_removed", provider=llm.PROVIDER, removed=removed)
    return _vault_view()


class JudgeRequest(BaseModel):
    engagement_id: str = Field(min_length=1, max_length=80)
    evidence_ids: list[str] = Field(min_length=1, max_length=200)
    model: str = llm.DEFAULT_MODEL


@app.post("/v1/model/judge")
def model_judge(body: JudgeRequest, _auth: None = Depends(require_token)):
    case = _CASES.get(body.engagement_id)
    if case is None:
        try:
            case = user_engagements.build_case(body.engagement_id)
        except VaultError as exc:
            raise _vault_http(exc) from None
        if case is None:
            raise HTTPException(status_code=404, detail={"code": "unknown_engagement", "message": "No engagement with that id."})
    if body.model not in llm.ALLOWED_MODELS:
        raise _fail("bad_request", "That model is not allowed.")
    try:
        key = vault.get(llm.PROVIDER)
    except VaultError as exc:
        raise _vault_http(exc) from None
    try:
        result = llm.judge(key, case, body.evidence_ids, body.model, meter)
    except ValueError as exc:
        raise _fail("bad_request", str(exc)) from None
    except llm.ModelError as exc:
        raise _model_http(exc) from None
    _event("model_judged", engagement=body.engagement_id, model=result["model"], **result["usage"])
    return result


def _spec_error(exc: SpecError) -> HTTPException:
    return HTTPException(status_code=400, detail={"code": "spec_refused", "message": str(exc)})


@app.get("/v1/profile")
def get_profile(_auth: None = Depends(require_token)):
    return specs.profile()


@app.put("/v1/profile")
def put_profile(body: Profile, _auth: None = Depends(require_token)):
    return specs.save_profile(body)


@app.get("/v1/specs")
def list_specs(_auth: None = Depends(require_token)):
    return {"items": specs.list_latest()}


class NewSpecBody(BaseModel):
    spec: Spec


@app.post("/v1/specs", status_code=201)
def create_spec(body: NewSpecBody, _auth: None = Depends(require_token)):
    try:
        return specs.create(body.spec)
    except SpecError as exc:
        raise _spec_error(exc) from None


@app.get("/v1/specs/{spec_id}/versions/{version}")
def get_spec_version(spec_id: str, version: int, _auth: None = Depends(require_token)):
    found = specs.get(spec_id, version)
    if found is None:
        raise HTTPException(status_code=404, detail={"code": "not_found", "message": "No spec version with that id."})
    return found


@app.post("/v1/specs/{spec_id}/versions", status_code=201)
def add_spec_version(spec_id: str, body: NewSpecBody, _auth: None = Depends(require_token)):
    try:
        return specs.create(body.spec, spec_id=spec_id)
    except SpecError as exc:
        raise _spec_error(exc) from None


def _engagement_spec_error(exc: SpecError) -> HTTPException:
    return HTTPException(status_code=400, detail={"code": "spec_refused", "message": str(exc)})


@app.get("/v1/engagements")
def list_engagements(_auth: None = Depends(require_token)):
    return {"items": user_engagements.list()}


@app.post("/v1/engagements", status_code=201)
def create_engagement(body: Intake, _auth: None = Depends(require_token)):
    try:
        return user_engagements.create(body)
    except SpecError as exc:
        raise _engagement_spec_error(exc) from None


@app.get("/v1/engagements/{engagement_id}")
def get_engagement(engagement_id: str, _auth: None = Depends(require_token)):
    try:
        found = user_engagements.get(engagement_id, with_text=True)
    except VaultError as exc:
        raise _vault_http(exc) from None
    if found is None:
        raise HTTPException(status_code=404, detail={"code": "not_found", "message": "No engagement with that id."})
    return found


@app.post("/v1/engagements/{engagement_id}/evidence", status_code=201)
def add_evidence(engagement_id: str, body: EvidenceIn, _auth: None = Depends(require_token)):
    try:
        return user_engagements.add_evidence(engagement_id, body)
    except SpecError as exc:
        raise _engagement_spec_error(exc) from None
    except VaultError as exc:
        raise _vault_http(exc) from None


@app.delete("/v1/engagements/{engagement_id}")
def delete_engagement(engagement_id: str, _auth: None = Depends(require_token)):
    if not user_engagements.delete(engagement_id):
        raise HTTPException(status_code=404, detail={"code": "not_found", "message": "No engagement with that id."})
    _event("engagement_deleted", engagement=engagement_id)
    return {"deleted": True}
