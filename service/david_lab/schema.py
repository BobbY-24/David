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


class AgentSpecVersion(Base):
    """One immutable version of a user's agent spec. Never updated."""

    __tablename__ = "agent_spec_versions"

    spec_id: Mapped[str] = mapped_column(String(40), primary_key=True)
    version: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    body: Mapped[dict] = mapped_column(JSON)
    content_hash: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class CompanyProfile(Base):
    """The one company profile this install uses."""

    __tablename__ = "company_profiles"

    id: Mapped[str] = mapped_column(String(20), primary_key=True)
    body: Mapped[dict] = mapped_column(JSON, default=dict)
    saved_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class EngagementRow(Base):
    """A user's engagement: a pinned spec version and the intake for it."""

    __tablename__ = "engagements"

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    spec_id: Mapped[str] = mapped_column(String(40))
    spec_version: Mapped[int] = mapped_column(Integer)
    spec_hash: Mapped[str] = mapped_column(String(64))
    deal_type: Mapped[str] = mapped_column(String(20))
    counterparty: Mapped[str] = mapped_column(String(160))
    deal_value: Mapped[float] = mapped_column(Float)
    jurisdiction: Mapped[str] = mapped_column(String(120), default="")
    website: Mapped[str] = mapped_column(String(200), default="")
    context: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class EvidenceUnitRow(Base):
    """One pasted unit of evidence. The text is sealed; the rest is metadata."""

    __tablename__ = "evidence_units"

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    engagement_id: Mapped[str] = mapped_column(String(40), index=True)
    title: Mapped[str] = mapped_column(String(160))
    source: Mapped[str] = mapped_column(String(160), default="")
    kind: Mapped[str] = mapped_column(String(20))
    observed_at: Mapped[str] = mapped_column(String(40), default="")
    content_hash: Mapped[str] = mapped_column(String(64))
    quarantined: Mapped[bool] = mapped_column(default=False)
    key_id: Mapped[str] = mapped_column(String(16))
    wrapped_dek: Mapped[str] = mapped_column(Text)
    dek_nonce: Mapped[str] = mapped_column(String(64))
    ciphertext: Mapped[str] = mapped_column(Text)
    nonce: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
