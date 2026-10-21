import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from david_lab import api
from david_lab.db import session_factory
from david_lab.specs import Profile, Spec, SpecError, SpecStore


def spec_body(**overrides) -> dict:
    body = {
        "name": "New wholesale customer",
        "deal_type": "customer",
        "question": "Should we ship a first order to this customer on 60-day terms?",
        "decision_criteria": ["Identify the legal entity that owes the invoice."],
        "checks": [{"title": "Registry", "query": "registry good standing", "evidence_kind": "record"}],
        "risks": [
            {"id": "successor", "title": "Successor entity", "statement": "The business trades under a new entity.",
             "outcome": "proceed_with_conditions", "action": "Contract with the exact legal name.",
             "deal_breaker": False},
            {"id": "phoenix", "title": "Phoenix company", "statement": "Debts were left behind on dissolution.",
             "outcome": "walk_away", "action": "", "deal_breaker": True},
        ],
        "questions_to_ask": ["Who signs the invoice?"],
    }
    body.update(overrides)
    return body


def store() -> SpecStore:
    return SpecStore(factory=session_factory)


def test_a_new_spec_starts_at_version_one_with_a_hash():
    view = store().create(Spec.model_validate(spec_body()))
    assert view["version"] == 1
    assert len(view["hash"]) == 64
    assert view["spec"]["name"] == "New wholesale customer"
    assert view["spec_id"] == "new-wholesale-customer"


def test_a_new_version_is_a_new_row_and_the_old_one_is_unchanged():
    s = store()
    first = s.create(Spec.model_validate(spec_body()))
    changed = spec_body(question="Should we ship a larger first order on 30-day terms?")
    second = s.create(Spec.model_validate(changed), spec_id=first["spec_id"])
    assert second["version"] == 2
    assert second["hash"] != first["hash"]
    again = s.get(first["spec_id"], 1)
    assert again["spec"]["question"] == spec_body()["question"]
    assert again["hash"] == first["hash"]


def test_saving_the_same_content_again_is_refused():
    s = store()
    first = s.create(Spec.model_validate(spec_body()))
    with pytest.raises(SpecError):
        s.create(Spec.model_validate(spec_body()), spec_id=first["spec_id"])


def test_an_unknown_spec_cannot_get_a_version():
    with pytest.raises(SpecError):
        store().create(Spec.model_validate(spec_body()), spec_id="no-such-spec")


def test_the_same_name_gets_a_new_id_not_a_silent_overwrite():
    s = store()
    first = s.create(Spec.model_validate(spec_body()))
    second = s.create(Spec.model_validate(spec_body(question="A different question for this one.")))
    assert second["spec_id"] != first["spec_id"]
    assert second["version"] == 1


@pytest.mark.parametrize("bad", [
    {"risks": [{"id": "Upper", "title": "x y", "statement": "A statement here."}] * 2},
    {"risks": [{"id": "ok-one", "title": "x y", "statement": "A statement here."}]},
    {"checks": []},
    {"checks": [{"title": "t", "query": "q q", "evidence_kind": "record"}] * 13},
    {"extra_field": "nope"},
    {"deal_type": "casino"},
    {"question": "short"},
    {"risks": [{"id": "same", "title": "x y", "statement": "A statement here."}] * 2},
    {"risks": [{"id": "ok-one", "title": "x y", "statement": "A statement here.", "outcome": "buy"},
               {"id": "ok-two", "title": "x y", "statement": "A statement here."}]},
])
def test_invalid_specs_are_refused(bad):
    with pytest.raises(Exception):
        Spec.model_validate(spec_body(**bad))


def test_the_profile_round_trips_and_rejects_bad_currency():
    s = store()
    saved = s.save_profile(Profile(company_name="Acme Co", currency="EUR", max_exposure=25000,
                                   deal_breakers=["Sanctions hit"]))
    assert saved["company_name"] == "Acme Co"
    assert s.profile()["deal_breakers"] == ["Sanctions hit"]
    with pytest.raises(Exception):
        Profile(currency="euro")


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setenv("DAVID_API_TOKEN", "")
    with TestClient(api.app) as test_client:
        yield test_client


def test_routes_create_version_and_read_back(client):
    created = client.post("/v1/specs", json={"spec": spec_body()})
    assert created.status_code == 201
    spec_id = created.json()["spec_id"]
    listed = client.get("/v1/specs").json()["items"]
    assert [item["spec_id"] for item in listed] == [spec_id]
    v2 = client.post(f"/v1/specs/{spec_id}/versions",
                     json={"spec": spec_body(question="A second question for the customer?")})
    assert v2.status_code == 201 and v2.json()["version"] == 2
    old = client.get(f"/v1/specs/{spec_id}/versions/1")
    assert old.status_code == 200 and old.json()["version"] == 1
    assert client.get(f"/v1/specs/{spec_id}/versions/9").status_code == 404


def test_a_refused_spec_gets_a_readable_400(client):
    response = client.post("/v1/specs", json={"spec": spec_body(risks=[])})
    assert response.status_code == 422


def test_a_validation_error_never_echoes_what_was_typed(client):
    secret = "sk-ant-api03-LEAKCHECKabcdefghijklmnop1234"
    response = client.post("/v1/specs", json={"spec": spec_body(question=secret, deal_type="casino")})
    assert response.status_code == 422
    assert secret not in response.text


def test_profile_routes_round_trip(client):
    put = client.put("/v1/profile", json={"company_name": "Acme", "currency": "USD", "deal_breakers": []})
    assert put.status_code == 200
    assert client.get("/v1/profile").json()["company_name"] == "Acme"
    assert client.put("/v1/profile", json={"currency": "usd"}).status_code == 422


def test_routes_need_the_token_when_one_is_set(client, monkeypatch):
    monkeypatch.setenv("DAVID_API_TOKEN", "s3cret")
    assert client.get("/v1/specs").status_code == 401
    assert client.get("/v1/profile").status_code == 401
    assert client.post("/v1/specs", json={"spec": spec_body()}).status_code == 401
    assert client.get("/v1/specs", headers={"X-David-Token": "s3cret"}).status_code == 200


def test_rows_are_never_updated_in_place(client):
    created = client.post("/v1/specs", json={"spec": spec_body()}).json()
    session = session_factory()
    try:
        rows = session.execute(text("SELECT count(*) FROM agent_spec_versions WHERE spec_id = :s"),
                               {"s": created["spec_id"]}).scalar()
    finally:
        session.close()
    assert rows == 1
