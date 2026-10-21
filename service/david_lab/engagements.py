"""User engagements: a pinned spec version, an intake, and the evidence for it.

Evidence text is sealed with the same envelope scheme as the API key, under a
label that names the engagement and the unit, so one unit's ciphertext cannot
be moved to another. Quarantine is decided when the unit is written and stored
with it, so a model call never sees an instruction-override unit.
"""

import hashlib
import uuid
from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from .db import session_factory
from .schema import EngagementRow, EvidenceUnitRow
from .screen import contains_instruction_override
from .specs import SpecError, SpecStore
from .vault import KeyUnreadable, Vault, VaultUnavailable, master_key_id, seal, unseal

MAX_EVIDENCE = 60
MAX_TEXT = 4000


class Intake(BaseModel):
    model_config = {"extra": "forbid"}

    spec_id: str = Field(min_length=2, max_length=40)
    spec_version: int = Field(ge=1, le=100000)
    counterparty: str = Field(min_length=2, max_length=160)
    deal_value: float = Field(default=0, ge=0, le=1_000_000_000)
    jurisdiction: str = Field(default="", max_length=120)
    website: str = Field(default="", max_length=200)
    context: str = Field(default="", max_length=MAX_TEXT)


class EvidenceIn(BaseModel):
    model_config = {"extra": "forbid"}

    title: str = Field(min_length=2, max_length=160)
    source: str = Field(default="", max_length=160)
    kind: Literal["record", "metric"] = "record"
    observed_at: str = Field(default="", max_length=40)
    text: str = Field(min_length=2, max_length=MAX_TEXT)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class EngagementStore:
    def __init__(self, factory=None, vault: Vault | None = None, specs: SpecStore | None = None) -> None:
        self._factory = factory or session_factory
        self._vault = vault or Vault(factory=self._factory)
        self._specs = specs or SpecStore(factory=self._factory)

    def _session(self) -> Session:
        return self._factory()

    def _master(self, create: bool) -> bytes:
        master = self._vault.master_key(create=create)
        if master is None:
            raise VaultUnavailable("No master key is available for the evidence store.")
        return master

    @staticmethod
    def _view(row: EngagementRow, evidence_count: int) -> dict:
        return {
            "id": row.id,
            "spec_id": row.spec_id,
            "spec_version": row.spec_version,
            "spec_hash": row.spec_hash,
            "deal_type": row.deal_type,
            "counterparty": row.counterparty,
            "deal_value": row.deal_value,
            "jurisdiction": row.jurisdiction,
            "website": row.website,
            "context": row.context,
            "created_at": row.created_at.isoformat(),
            "evidence_count": evidence_count,
        }

    @staticmethod
    def _evidence_view(row: EvidenceUnitRow, text: str | None) -> dict:
        view = {
            "id": row.id,
            "title": row.title,
            "source": row.source,
            "kind": row.kind,
            "observed_at": row.observed_at,
            "content_hash": row.content_hash,
            "quarantined": row.quarantined,
        }
        if text is not None:
            view["text"] = text
        return view

    def create(self, intake: Intake) -> dict:
        pinned = self._specs.get(intake.spec_id, intake.spec_version)
        if pinned is None:
            raise SpecError("That spec version does not exist.")
        row = EngagementRow(
            id=uuid.uuid4().hex,
            spec_id=intake.spec_id,
            spec_version=intake.spec_version,
            spec_hash=pinned["hash"],
            deal_type=pinned["spec"]["deal_type"],
            counterparty=intake.counterparty,
            deal_value=intake.deal_value,
            jurisdiction=intake.jurisdiction,
            website=intake.website,
            context=intake.context,
            created_at=utcnow(),
        )
        session = self._session()
        try:
            session.add(row)
            session.commit()
            return self._view(row, 0)
        finally:
            session.close()

    def list(self) -> list[dict]:
        session = self._session()
        try:
            rows = session.scalars(select(EngagementRow).order_by(EngagementRow.created_at.desc())).all()
            counts = dict(session.execute(
                select(EvidenceUnitRow.engagement_id, func.count()).group_by(EvidenceUnitRow.engagement_id)
            ).all())
            return [self._view(row, counts.get(row.id, 0)) for row in rows]
        finally:
            session.close()

    def get(self, engagement_id: str, with_text: bool = False) -> dict | None:
        session = self._session()
        try:
            row = session.get(EngagementRow, engagement_id)
            if row is None:
                return None
            units = session.scalars(
                select(EvidenceUnitRow)
                .where(EvidenceUnitRow.engagement_id == engagement_id)
                .order_by(EvidenceUnitRow.created_at)
            ).all()
            master = self._master(create=False) if with_text and units else None
            evidence = [
                self._evidence_view(unit, self._open(master, unit) if with_text else None)
                for unit in units
            ]
            view = self._view(row, len(units))
            view["spec"] = self._specs.get(row.spec_id, row.spec_version)
            view["evidence"] = evidence
            return view
        finally:
            session.close()

    @staticmethod
    def _open(master: bytes | None, unit: EvidenceUnitRow) -> str:
        if master is None or unit.key_id != master_key_id(master):
            raise KeyUnreadable("The evidence cannot be read with the current master key.")
        record = {
            "wrapped_dek": unit.wrapped_dek,
            "dek_nonce": unit.dek_nonce,
            "ciphertext": unit.ciphertext,
            "nonce": unit.nonce,
        }
        return unseal(master, _label(unit.engagement_id, unit.id), record)

    def add_evidence(self, engagement_id: str, body: EvidenceIn) -> dict:
        session = self._session()
        try:
            if session.get(EngagementRow, engagement_id) is None:
                raise SpecError("No engagement has that id.")
            count = session.scalar(
                select(func.count()).select_from(EvidenceUnitRow).where(EvidenceUnitRow.engagement_id == engagement_id)
            )
            if count >= MAX_EVIDENCE:
                raise SpecError(f"An engagement holds at most {MAX_EVIDENCE} evidence units.")
            master = self._master(create=True)
            unit_id = uuid.uuid4().hex
            sealed = seal(master, _label(engagement_id, unit_id), body.text)
            row = EvidenceUnitRow(
                id=unit_id,
                engagement_id=engagement_id,
                title=body.title,
                source=body.source,
                kind=body.kind,
                observed_at=body.observed_at,
                content_hash=hashlib.sha256(body.text.encode("utf-8")).hexdigest(),
                quarantined=contains_instruction_override(body.text),
                key_id=master_key_id(master),
                wrapped_dek=sealed["wrapped_dek"],
                dek_nonce=sealed["dek_nonce"],
                ciphertext=sealed["ciphertext"],
                nonce=sealed["nonce"],
                created_at=utcnow(),
            )
            session.add(row)
            session.commit()
            return self._evidence_view(row, None)
        finally:
            session.close()

    def delete(self, engagement_id: str) -> bool:
        session = self._session()
        try:
            row = session.get(EngagementRow, engagement_id)
            if row is None:
                return False
            session.execute(delete(EvidenceUnitRow).where(EvidenceUnitRow.engagement_id == engagement_id))
            session.delete(row)
            session.commit()
            return True
        finally:
            session.close()

    def build_case(self, engagement_id: str) -> dict | None:
        """The shape the model judge reads. Quarantined units are included but flagged."""
        session = self._session()
        try:
            row = session.get(EngagementRow, engagement_id)
            if row is None:
                return None
            units = session.scalars(
                select(EvidenceUnitRow)
                .where(EvidenceUnitRow.engagement_id == engagement_id)
                .order_by(EvidenceUnitRow.created_at)
            ).all()
            master = self._master(create=False) if units else None
            evidence = [
                {"id": unit.id, "text": self._open(master, unit), "quarantined": unit.quarantined}
                for unit in units
            ]
            spec = self._specs.get(row.spec_id, row.spec_version)
            profile = self._specs.profile()
        finally:
            session.close()
        risks = [
            {"id": risk["id"], "title": risk["title"], "statement": risk["statement"]}
            for risk in spec["spec"]["risks"]
        ]
        risks += [
            {"id": f"profile-breaker-{i + 1}", "title": "Your deal-breaker", "statement": text}
            for i, text in enumerate(profile.get("deal_breakers", []))
        ]
        return {
            "id": row.id,
            "title": spec["spec"]["name"],
            "deal_type": row.deal_type,
            "question": f"{spec['spec']['question']} Counterparty: {row.counterparty}.",
            "evidence": evidence,
            "risk_questions": risks,
        }


def _label(engagement_id: str, unit_id: str) -> str:
    return f"evidence:{engagement_id}:{unit_id}"
