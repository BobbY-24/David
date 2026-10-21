from datetime import timedelta

from fastapi.testclient import TestClient

from david_lab.api import app, service as api_service
from david_lab.db import session_factory
from david_lab.errors import IdempotencyConflict, QueueFull
from david_lab.metrics import percentile
from david_lab.runners import catalog, engagement
from david_lab.schema import Job
from david_lab.service import JobService, utcnow


def test_percentile_ends():
    assert percentile([], 0.95) is None
    assert percentile([10.0], 0.99) == 10.0
    assert percentile([1, 2, 3, 4], 0.5) == 2.5


def test_engagement_leads_match_the_desk():
    brightline = engagement({"case_id": "brightline-supply"}, None)
    corvid = engagement({"case_id": "corvid-retail"}, None)
    north = engagement({"case_id": "northline-logistics"}, None)
    assert brightline["lead"] == "delivery-reliability"
    assert brightline["loop"] == "plan-execute"
    assert brightline["deal_type"] == "vendor"
    # "no tax lien" must not fire the distress signature.
    assert "tax lien" not in brightline["fired"]
    assert corvid["lead"] == "successor-entity"
    assert corvid["loop"] == "react"
    assert north["lead"] == "related-party-round-trip"
    assert north["loop"] == "panel-vote"
    assert "integration defect" not in north["fired"]


def test_catalog_lists_every_desk_engagement_and_nothing_else():
    items = catalog()
    assert {item["spec"]["case_id"] for item in items} == {
        "brightline-supply",
        "corvid-retail",
        "northline-logistics",
    }
    assert {item["kind"] for item in items} == {"engagement"}


def test_phrase_matcher_agrees_with_every_desk_verdict():
    from david_lab.runners import _EXPORT, phrase_matches

    golden = _EXPORT["phrase_golden"]
    assert len(golden) > 30
    wrong = [(text, phrase, want) for text, phrase, want in golden if phrase_matches(text, phrase) != want]
    assert wrong == []


def test_service_and_desk_read_the_same_cases():
    from david_lab.runners import _CASES

    corvid = {r["id"]: r for r in _CASES["corvid-retail"]["risk_questions"]}
    assert ["new entity", 1.2] in corvid["successor-entity"]["support"]
    assert ["paid within terms", 1.4] in corvid["phoenix-fraud"]["contradict"]
    assert _CASES["northline-logistics"]["deal_type"] == "acquisition"


def test_unrelated_party_is_not_a_related_party():
    from david_lab.runners import phrase_matches

    assert phrase_matches("The related party paid.", "related party")
    assert not phrase_matches("The unrelated party paid.", "related party")
    assert not phrase_matches("Our visit found no sign of a mail drop address.", "mail drop address")
    assert phrase_matches("No dispute. Mail drop address on every invoice.", "mail drop address")


def test_retry_backoff_is_scheduled_not_slept(monkeypatch):
    import time

    monkeypatch.setenv("RETRY_BACKOFF_SECONDS", "1.5")
    now, later = [], []
    jobs = JobService(dispatch=now.append, dispatch_later=lambda job_id, delay: later.append((job_id, delay)))
    view, _ = jobs.enqueue("probe", {"fail_times": 1}, "backoff-1")
    started = time.monotonic()
    jobs.execute(view["id"])
    assert time.monotonic() - started < 1.0
    assert later == [(view["id"], 1.5)]
    assert jobs.get(view["id"])["status"] == "queued"


def test_cors_allows_the_desk_and_not_any_origin():
    client = TestClient(app)
    desk = client.options(
        "/v1/jobs",
        headers={"Origin": "http://127.0.0.1:43123", "Access-Control-Request-Method": "POST"},
    )
    assert desk.headers.get("access-control-allow-origin") == "http://127.0.0.1:43123"
    stranger = client.options(
        "/v1/jobs",
        headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "POST"},
    )
    assert "access-control-allow-origin" not in stranger.headers


def test_idempotency_replays_and_rejects_a_different_body():
    jobs = JobService(dispatch=lambda _job_id: None)
    first, created = jobs.enqueue("probe", {"sleep_ms": 0}, "same-key")
    again, replayed = jobs.enqueue("probe", {"sleep_ms": 0}, "same-key")
    assert created is True
    assert replayed is False
    assert again["id"] == first["id"]
    try:
        jobs.enqueue("probe", {"sleep_ms": 5}, "same-key")
        raise AssertionError("expected conflict")
    except IdempotencyConflict:
        pass


def test_queue_cap_rejects_the_extra_job():
    jobs = JobService(cap=2, dispatch=lambda _job_id: None)
    jobs.enqueue("probe", {}, "a")
    jobs.enqueue("probe", {}, "b")
    try:
        jobs.enqueue("probe", {}, "c")
        raise AssertionError("expected queue full")
    except QueueFull as exc:
        assert exc.cap == 2
        assert exc.depth == 2


def test_retry_then_success_and_dead_letter():
    woke = []
    jobs = JobService(dispatch=woke.append)
    view, _ = jobs.enqueue("probe", {"fail_times": 1}, "retry-me")
    jobs.execute(view["id"])
    mid = jobs.get(view["id"])
    assert mid["status"] == "queued"
    assert mid["attempts"] == 1
    assert woke == [view["id"], view["id"]]
    jobs.execute(view["id"])
    done = jobs.get(view["id"])
    assert done["status"] == "succeeded"
    assert done["attempts"] == 2

    poisoned, _ = jobs.enqueue("probe", {"fail_times": 9}, "poison")
    session = session_factory()
    row = session.get(Job, poisoned["id"])
    row.max_attempts = 2
    session.commit()
    session.close()
    jobs.execute(poisoned["id"])
    jobs.execute(poisoned["id"])
    dead = jobs.get(poisoned["id"])
    assert dead["status"] == "dead"
    assert dead["attempts"] == 2


def test_expired_lease_is_requeued_once():
    jobs = JobService(dispatch=lambda _job_id: None)
    view, _ = jobs.enqueue("probe", {}, "lease")
    claimed = jobs.claim(view["id"], "worker-a")
    assert claimed is not None
    session = session_factory()
    row = session.get(Job, view["id"])
    row.started_at = utcnow() - timedelta(seconds=120)
    session.commit()
    session.close()
    reclaimed = jobs.reclaim_expired()
    assert view["id"] in reclaimed
    assert jobs.get(view["id"])["status"] == "queued"
    jobs.execute(view["id"])
    done = jobs.get(view["id"])
    assert done["status"] == "succeeded"
    assert done["attempts"] == 2


def test_unknown_case_is_dead_without_retry():
    jobs = JobService(dispatch=lambda _job_id: None)
    view, _ = jobs.enqueue("engagement", {"case_id": "missing"}, "missing")
    jobs.execute(view["id"])
    done = jobs.get(view["id"])
    assert done["status"] == "dead"
    assert done["attempts"] == 1


def test_load_shape_records_wait_and_e2e():
    jobs = JobService(cap=30, dispatch=lambda _job_id: None)
    ids = []
    for index in range(12):
        view, _ = jobs.enqueue("probe", {"sleep_ms": 15}, f"load-{index}")
        ids.append(view["id"])
    for job_id in ids:
        jobs.execute(job_id)
    body = jobs.metrics()
    assert body["succeeded"] == 12
    assert body["depth"] == 0
    assert body["e2e_ms"]["p95"] is not None
    assert body["e2e_ms"]["p99"] is not None
    assert body["e2e_ms"]["p99"] >= body["e2e_ms"]["p95"]
    assert body["queue_wait_ms"]["p95"] is not None
    assert body["throughput_per_s"] > 0


def test_api_enqueue_requires_a_key_and_serves_metrics():
    with TestClient(app) as client:
        missing = client.post("/v1/jobs", json={"kind": "probe", "spec": {}})
        assert missing.status_code == 400
        health = client.get("/v1/health")
        assert health.status_code == 200
        assert health.json()["scorer"] == "demo-scorer-v3"
        created = client.post(
            "/v1/jobs",
            headers={"Idempotency-Key": "api-probe"},
            json={"kind": "probe", "spec": {}},
        )
        assert created.status_code == 202
        job_id = created.json()["id"]
        api_service.execute(job_id)
        fetched = client.get(f"/v1/jobs/{job_id}")
        assert fetched.json()["status"] == "succeeded"
        metrics = client.get("/metrics")
        assert "david_jobs_depth" in metrics.text
        catalog = client.get("/v1/catalog")
        titles = [item["title"] for item in catalog.json()["items"]]
        assert titles == ["Brightline Supply", "Corvid Retail", "Northline Logistics"]
