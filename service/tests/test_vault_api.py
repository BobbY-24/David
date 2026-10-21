import logging

import pytest
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from fastapi.testclient import TestClient
from sqlalchemy import text

from david_lab import api, llm
from david_lab.db import session_factory
from david_lab.vault import Vault
from tests.fakes import FakeClient, FakeResponse, auth_error, entry, judgment

KEY = "sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789"


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setattr(api, "vault", Vault(master_key=AESGCM.generate_key(bit_length=256)))
    monkeypatch.setattr(api, "meter", llm.UsageMeter(cap=5))
    with TestClient(api.app) as test_client:
        yield test_client


def use_fake(monkeypatch, **kwargs) -> FakeClient:
    fake = FakeClient(**kwargs)
    monkeypatch.setattr(llm, "make_client", lambda _key: fake)
    return fake


def test_saving_a_key_verifies_it_stores_it_sealed_and_returns_only_the_last_four(client, monkeypatch):
    fake = use_fake(monkeypatch)
    response = client.put("/v1/vault/anthropic", json={"key": KEY})
    assert response.status_code == 200
    assert KEY not in response.text
    body = response.json()
    assert body["anthropic"]["configured"] is True
    assert body["anthropic"]["last4"] == KEY[-4:]
    assert body["anthropic"]["verified_at"]
    assert [name for name, _ in fake.calls] == ["models.retrieve"]
    session = session_factory()
    try:
        row = str(session.execute(text("SELECT * FROM api_keys")).all())
    finally:
        session.close()
    assert KEY not in row and KEY[:-4] not in row


def test_a_key_anthropic_rejects_is_not_stored(client, monkeypatch):
    use_fake(monkeypatch, retrieve_error=auth_error())
    response = client.put("/v1/vault/anthropic", json={"key": KEY})
    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "key_rejected"
    assert KEY not in response.text
    assert client.get("/v1/vault").json()["anthropic"]["configured"] is False


def test_bad_formats_and_admin_keys_are_rejected_without_echoing_them(client, monkeypatch):
    fake = use_fake(monkeypatch)
    for bad, code in [("not-a-key", "key_format"), ("sk-ant-admin01-" + "a" * 40, "admin_key"),
                      ("sk-ant-api03-short", "key_format")]:
        response = client.put("/v1/vault/anthropic", json={"key": bad})
        assert response.status_code == 400 and response.json()["detail"]["code"] == code
        assert bad not in response.text
    assert fake.calls == []


def test_a_validation_error_does_not_repeat_the_submitted_value(client):
    huge = "sk-ant-api03-" + "x" * 500
    response = client.put("/v1/vault/anthropic", json={"key": huge})
    assert response.status_code == 422
    assert huge not in response.text and "xxxxxxxx" not in response.text
    response = client.put("/v1/vault/anthropic", json={"key": 12345})
    assert response.status_code == 422 and "12345" not in response.text


def test_the_key_never_appears_in_logs(client, monkeypatch, caplog):
    use_fake(monkeypatch)
    with caplog.at_level(logging.DEBUG):
        client.put("/v1/vault/anthropic", json={"key": KEY})
        client.post("/v1/vault/anthropic/verify")
        client.delete("/v1/vault/anthropic")
    assert KEY not in caplog.text and KEY[:-4] not in caplog.text


def test_verify_and_delete(client, monkeypatch):
    use_fake(monkeypatch)
    client.put("/v1/vault/anthropic", json={"key": KEY})
    assert client.post("/v1/vault/anthropic/verify").status_code == 200
    removed = client.delete("/v1/vault/anthropic")
    assert removed.status_code == 200 and removed.json()["anthropic"]["configured"] is False
    assert client.post("/v1/vault/anthropic/verify").json()["detail"]["code"] == "key_missing"


def test_judge_uses_the_saved_key_and_returns_validated_weights(client, monkeypatch):
    fake = use_fake(monkeypatch)
    client.put("/v1/vault/anthropic", json={"key": KEY})
    fake.response = FakeResponse(judgment([
        {"risk_id": "delivery-reliability", "support": [entry("b-reviews", 2.4)], "contradict": []}]))
    seen = {}
    monkeypatch.setattr(llm, "make_client", lambda key: seen.setdefault("key", key) and fake)
    response = client.post("/v1/model/judge", json={
        "engagement_id": "brightline-supply", "evidence_ids": ["b-reviews", "forged"], "model": "claude-opus-5-5"})
    assert response.status_code == 200
    assert seen["key"] == KEY
    assert KEY not in response.text
    risks = {r["risk_id"]: r for r in response.json()["risks"]}
    assert risks["delivery-reliability"]["support"][0]["evidence_id"] == "b-reviews"
    assert client.get("/v1/vault").json()["usage"]["calls"] == 1


def test_judge_without_a_saved_key_or_for_an_unknown_engagement(client, monkeypatch):
    use_fake(monkeypatch)
    body = {"engagement_id": "brightline-supply", "evidence_ids": ["b-reviews"]}
    missing = client.post("/v1/model/judge", json=body)
    assert missing.status_code == 409 and missing.json()["detail"]["code"] == "key_missing"
    unknown = client.post("/v1/model/judge", json=dict(body, engagement_id="nope"))
    assert unknown.status_code == 404


def test_judge_rejects_a_model_that_is_not_allowed(client, monkeypatch):
    use_fake(monkeypatch)
    client.put("/v1/vault/anthropic", json={"key": KEY})
    response = client.post("/v1/model/judge", json={
        "engagement_id": "brightline-supply", "evidence_ids": ["b-reviews"], "model": "gpt-4"})
    assert response.status_code == 400


def test_the_daily_cap_returns_429(client, monkeypatch):
    fake = use_fake(monkeypatch)
    client.put("/v1/vault/anthropic", json={"key": KEY})
    fake.response = FakeResponse(judgment([]))
    body = {"engagement_id": "brightline-supply", "evidence_ids": ["b-reviews"]}
    for _ in range(5):
        assert client.post("/v1/model/judge", json=body).status_code == 200
    capped = client.post("/v1/model/judge", json=body)
    assert capped.status_code == 429 and capped.json()["detail"]["code"] == "daily_cap_reached"


def test_a_saved_key_that_cannot_be_decrypted_is_reported(client, monkeypatch):
    use_fake(monkeypatch)
    client.put("/v1/vault/anthropic", json={"key": KEY})
    monkeypatch.setattr(api, "vault", Vault(master_key=AESGCM.generate_key(bit_length=256)))
    status = client.get("/v1/vault").json()["anthropic"]
    assert status["configured"] is True and status["readable"] is False
    response = client.post("/v1/model/judge", json={"engagement_id": "brightline-supply", "evidence_ids": ["b-reviews"]})
    assert response.status_code == 409 and response.json()["detail"]["code"] == "key_unreadable"


def test_the_optional_token_protects_vault_and_model_routes(client, monkeypatch):
    use_fake(monkeypatch)
    monkeypatch.setenv("DAVID_API_TOKEN", "s3cret-token")
    assert client.get("/v1/vault").status_code == 401
    assert client.put("/v1/vault/anthropic", json={"key": KEY}).status_code == 401
    assert client.post("/v1/model/judge", json={"engagement_id": "brightline-supply", "evidence_ids": ["x"]}).status_code == 401
    assert client.get("/v1/vault", headers={"X-David-Token": "wrong"}).status_code == 401
    assert client.get("/v1/vault", headers={"X-David-Token": "s3cret-token"}).status_code == 200
    assert client.get("/v1/health").status_code == 200


def test_cors_allows_the_desk_to_put_and_delete_with_the_token_header(client):
    preflight = client.options("/v1/vault/anthropic", headers={
        "Origin": "http://127.0.0.1:43123",
        "Access-Control-Request-Method": "PUT",
        "Access-Control-Request-Headers": "content-type,x-david-token",
    })
    assert preflight.status_code == 200
    assert "PUT" in preflight.headers["access-control-allow-methods"]
    assert "x-david-token" in preflight.headers["access-control-allow-headers"].lower()
    stranger = client.options("/v1/vault/anthropic", headers={
        "Origin": "https://evil.example", "Access-Control-Request-Method": "PUT"})
    assert "access-control-allow-origin" not in stranger.headers
