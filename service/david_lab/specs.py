"""Versioned agent specs and the company profile.

A spec is data the user edits: the deal question, the checks to run, the risk
questions to weigh, and what each one recommends. Every save creates a new
immutable version with a content hash, so a memo can name exactly the spec it
was run on.
"""

import hashlib
import json
import re
from datetime import datetime, timezone
from enum import Enum

from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import session_factory
from .schema import AgentSpecVersion, CompanyProfile

SLUG = re.compile(r"^[a-z][a-z0-9-]{1,39}$")
MAX_CHECKS = 12
MAX_RISKS = 8
MIN_RISKS = 2
MAX_CRITERIA = 8
MAX_QUESTIONS = 10
MAX_DEAL_BREAKERS = 10


class DealType(str, Enum):
    customer = "customer"
    vendor = "vendor"
    partner = "partner"
    contractor = "contractor"
    acquisition = "acquisition"
    lease = "lease"


class Outcome(str, Enum):
    proceed = "proceed"
    proceed_with_conditions = "proceed_with_conditions"
    hold = "hold"
    walk_away = "walk_away"


class EvidenceKind(str, Enum):
    record = "record"
    metric = "metric"


class Check(BaseModel):
    model_config = {"extra": "forbid"}

    title: str = Field(min_length=2, max_length=120)
    query: str = Field(min_length=2, max_length=300)
    evidence_kind: EvidenceKind = EvidenceKind.record


class Risk(BaseModel):
    model_config = {"extra": "forbid"}

    id: str = Field(min_length=2, max_length=40)
    title: str = Field(min_length=2, max_length=120)
    statement: str = Field(min_length=5, max_length=600)
    outcome: Outcome = Outcome.hold
    action: str = Field(default="", max_length=300)
    deal_breaker: bool = False

    @field_validator("id")
    @classmethod
    def _slug(cls, value: str) -> str:
        if not SLUG.fullmatch(value):
            raise ValueError("A risk id is lowercase letters, digits and hyphens, starting with a letter.")
        return value


class Spec(BaseModel):
    model_config = {"extra": "forbid"}

    name: str = Field(min_length=2, max_length=120)
    deal_type: DealType
    question: str = Field(min_length=10, max_length=600)
    decision_criteria: list[str] = Field(default_factory=list, max_length=MAX_CRITERIA)
    checks: list[Check] = Field(min_length=1, max_length=MAX_CHECKS)
    risks: list[Risk] = Field(min_length=MIN_RISKS, max_length=MAX_RISKS)
    questions_to_ask: list[str] = Field(default_factory=list, max_length=MAX_QUESTIONS)

    @field_validator("decision_criteria", "questions_to_ask")
    @classmethod
    def _short_lines(cls, values: list[str]) -> list[str]:
        for value in values:
            if not value.strip() or len(value) > 200:
                raise ValueError("Each line must be 1 to 200 characters.")
        return values

    @model_validator(mode="after")
    def _unique_risk_ids(self) -> "Spec":
        ids = [risk.id for risk in self.risks]
        if len(set(ids)) != len(ids):
            raise ValueError("Risk ids must be unique.")
        return self


class Profile(BaseModel):
    model_config = {"extra": "forbid"}

    company_name: str = Field(default="", max_length=120)
    industry: str = Field(default="", max_length=120)
    jurisdictions: str = Field(default="", max_length=200)
    currency: str = Field(default="USD", pattern=r"^[A-Z]{3}$")
    max_exposure: float = Field(default=0, ge=0, le=1_000_000_000)
    deal_breakers: list[str] = Field(default_factory=list, max_length=MAX_DEAL_BREAKERS)
    standing_checks: list[Check] = Field(default_factory=list, max_length=MAX_CHECKS)

    @field_validator("deal_breakers")
    @classmethod
    def _breakers(cls, values: list[str]) -> list[str]:
        for value in values:
            if not value.strip() or len(value) > 200:
                raise ValueError("Each deal-breaker is 1 to 200 characters.")
        return values


class SpecError(Exception):
    """A spec or profile was refused. The message is safe to show."""


def canonical(body: dict) -> str:
    return json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def content_hash(body: dict) -> str:
    return hashlib.sha256(canonical(body).encode("utf-8")).hexdigest()


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class SpecStore:
    """Reads and writes specs and the profile. Versions are never updated."""

    def __init__(self, factory=None) -> None:
        self._factory = factory or session_factory

    def _session(self) -> Session:
        return self._factory()

    @staticmethod
    def _view(row: AgentSpecVersion) -> dict:
        return {
            "spec_id": row.spec_id,
            "version": row.version,
            "hash": row.content_hash,
            "created_at": row.created_at.isoformat(),
            "spec": row.body,
        }

    def list_latest(self) -> list[dict]:
        session = self._session()
        try:
            rows = session.scalars(
                select(AgentSpecVersion).order_by(AgentSpecVersion.spec_id, AgentSpecVersion.version.desc())
            ).all()
            seen: set[str] = set()
            latest = []
            for row in rows:
                if row.spec_id not in seen:
                    seen.add(row.spec_id)
                    latest.append(self._view(row))
            return latest
        finally:
            session.close()

    def get(self, spec_id: str, version: int) -> dict | None:
        session = self._session()
        try:
            row = session.get(AgentSpecVersion, (spec_id, version))
            return None if row is None else self._view(row)
        finally:
            session.close()

    def create(self, spec: Spec, spec_id: str | None = None) -> dict:
        """Start a new spec at version 1, or add the next version to `spec_id`."""
        body = spec.model_dump(mode="json")
        digest = content_hash(body)
        session = self._session()
        try:
            if spec_id is None:
                spec_id = self._new_id(session, spec.name)
                version = 1
            else:
                latest = session.scalars(
                    select(AgentSpecVersion)
                    .where(AgentSpecVersion.spec_id == spec_id)
                    .order_by(AgentSpecVersion.version.desc())
                    .limit(1)
                ).first()
                if latest is None:
                    raise SpecError("No spec has that id.")
                if latest.content_hash == digest:
                    raise SpecError("That is the same as the latest version.")
                version = latest.version + 1
            row = AgentSpecVersion(
                spec_id=spec_id,
                version=version,
                name=spec.name,
                body=body,
                content_hash=digest,
                created_at=utcnow(),
            )
            session.add(row)
            session.commit()
            return self._view(row)
        finally:
            session.close()

    @staticmethod
    def _new_id(session: Session, name: str) -> str:
        base = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:30] or "spec"
        if not base[0].isalpha():
            base = f"s-{base}"[:40]
        candidate = base
        n = 2
        while session.get(AgentSpecVersion, (candidate, 1)) is not None:
            candidate = f"{base}-{n}"[:40]
            n += 1
        return candidate

    def profile(self) -> dict:
        session = self._session()
        try:
            row = session.get(CompanyProfile, "default")
            if row is None:
                return {**Profile().model_dump(mode="json"), "saved_at": None}
            return {**row.body, "saved_at": row.saved_at.isoformat()}
        finally:
            session.close()

    def save_profile(self, profile: Profile) -> dict:
        body = profile.model_dump(mode="json")
        session = self._session()
        try:
            row = session.get(CompanyProfile, "default")
            if row is None:
                row = CompanyProfile(id="default")
                session.add(row)
            row.body = body
            row.saved_at = utcnow()
            session.commit()
            return {**body, "saved_at": row.saved_at.isoformat()}
        finally:
            session.close()


def pinned(spec_view: dict) -> dict:
    """The part of a stored spec that a run records."""
    return {"spec_id": spec_view["spec_id"], "version": spec_view["version"], "hash": spec_view["hash"]}
