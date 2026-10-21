import uuid
from datetime import datetime

from sqlalchemy import DateTime, Float, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import JSON

from .db import Base


def new_id() -> str:
    return str(uuid.uuid4())


class Job(Base):
    __tablename__ = "jobs"
    __table_args__ = (UniqueConstraint("idempotency_key", name="uq_jobs_idempotency"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    idempotency_key: Mapped[str] = mapped_column(String(200))
    payload_hash: Mapped[str] = mapped_column(String(64))
    kind: Mapped[str] = mapped_column(String(40))
    spec: Mapped[dict] = mapped_column(JSON)
    status: Mapped[str] = mapped_column(String(20), index=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    max_attempts: Mapped[int] = mapped_column(Integer)
    queued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    dispatched_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    queue_wait_ms: Mapped[float | None] = mapped_column(Float, nullable=True)
    e2e_ms: Mapped[float | None] = mapped_column(Float, nullable=True)
    result: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    worker_token: Mapped[str | None] = mapped_column(String(64), nullable=True)


class ApiKey(Base):
    """One sealed provider key. Ciphertext only; see vault.py."""

    __tablename__ = "api_keys"

    provider: Mapped[str] = mapped_column(String(40), primary_key=True)
    key_id: Mapped[str] = mapped_column(String(16))
    wrapped_dek: Mapped[str] = mapped_column(Text)
    dek_nonce: Mapped[str] = mapped_column(String(64))
    ciphertext: Mapped[str] = mapped_column(Text)
    nonce: Mapped[str] = mapped_column(String(64))
    last4: Mapped[str] = mapped_column(String(4))
    saved_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ModelUsage(Base):
    """Calls and tokens spent through the user's key, one row per UTC day."""

    __tablename__ = "model_usage"

    day: Mapped[str] = mapped_column(String(10), primary_key=True)
    calls: Mapped[int] = mapped_column(Integer, default=0)
    input_tokens: Mapped[int] = mapped_column(Integer, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0)
