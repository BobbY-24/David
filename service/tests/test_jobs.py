from datetime import timedelta

from fastapi.testclient import TestClient

from fieldline_lab.api import app, service as api_service
from fieldline_lab.db import session_factory
from fieldline_lab.errors import IdempotencyConflict, QueueFull
from fieldline_lab.metrics import percentile
from fieldline_lab.runners import churn, hypertension, investigation
from fieldline_lab.schema import Job
from fieldline_lab.service import JobService, utcnow


def test_percentile_ends():
    assert percentile([], 0.95) is None
    assert percentile([10.0], 0.99) == 10.0
    assert percentile([1, 2, 3, 4], 0.5) == 2.5


def test_investigation_leads_match_the_desk():
    harbor = investigation({"case_id": "harbor-substation-4"}, None)
    north = investigation({"case_id": "northline-logistics"}, None)
    vault = investigation({"case_id": "vault-c12"}, None)
    assert harbor["lead"] == "internal-thermal-fault"
    assert harbor["loop"] == "react"
    assert north["lead"] == "related-party-round-trip"
    assert north["loop"] == "panel-vote"
    assert "integration defect" not in north["fired"]
    assert vault["lead"] == "door-ajar"
    assert vault["loop"] == "plan-execute"


def test_hypertension_ignores_instruction_notes():
    result = hypertension({"cohort": "ward"}, None)
    by_id = {row["id"]: row for row in result["rows"]}
    assert by_id["w2"]["band"] == "low"
    assert result["counts"]["higher"] == 3
    assert result["clinical_use"] is False
    assert result["fixture"] is True


def test_churn_does_not_send():
    result = churn({"book": "northwind"}, None)
    assert result["counts"]["likely-leave"] == 2
    assert result["message_sent"] is False
    leaving = [row for row in result["rows"] if row["band"] == "likely-leave"]
    assert {row["id"] for row in leaving} == {"c1", "c3"}


def test_portfolio_reads_sql_and_does_not_trade():
    woke = []
    jobs = JobService(dispatch=woke.append)
    view, created = jobs.enqueue("portfolio", {"account": "cedar"}, "book-1")
    assert created is True
    jobs.execute(view["id"])
    done = jobs.get(view["id"])
    assert done["status"] == "succeeded"
    assert done["lead"] == "concentration-breach"
    assert done["result"]["largest_symbol"] == "NVDA"
    assert done["result"]["largest_weight"] > 0.5
    assert done["result"]["order_placed"] is False
    assert done["queue_wait_ms"] is not None
    assert done["e2e_ms"] is not None


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
    view, _ = jobs.enqueue("investigation", {"case_id": "missing"}, "missing")
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
        assert health.json()["scorer"] == "fixture-scorer-v1"
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
        assert "fieldline_jobs_depth" in metrics.text
        catalog = client.get("/v1/catalog")
        titles = [item["title"] for item in catalog.json()["items"]]
        assert "Cedar book" in titles
        assert "Ward cohort" in titles
        assert "Northwind accounts" in titles
