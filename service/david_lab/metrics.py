import math
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import SCORER_ID
from .schema import Job


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])
    rank = (len(ordered) - 1) * p
    lo = math.floor(rank)
    hi = math.ceil(rank)
    if lo == hi:
        return float(ordered[lo])
    weight = rank - lo
    return float(ordered[lo] + (ordered[hi] - ordered[lo]) * weight)


def _ms(column, rows: list[Job]) -> list[float]:
    found = []
    for row in rows:
        value = getattr(row, column)
        if value is not None:
            found.append(float(value))
    return found


def snapshot(session: Session, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    rows = list(session.scalars(select(Job)))
    by_status: dict[str, int] = {}
    for row in rows:
        by_status[row.status] = by_status.get(row.status, 0) + 1
    done = [row for row in rows if row.status == "succeeded"]
    window_start = now - timedelta(seconds=60)
    recent = [
        row
        for row in done
        if row.finished_at is not None and row.finished_at >= window_start
    ]
    waits = _ms("queue_wait_ms", done)
    e2e = _ms("e2e_ms", done)
    return {
        "scorer": SCORER_ID,
        "queued": by_status.get("queued", 0),
        "running": by_status.get("running", 0),
        "succeeded": by_status.get("succeeded", 0),
        "dead": by_status.get("dead", 0),
        "depth": by_status.get("queued", 0) + by_status.get("running", 0),
        "throughput_per_s": len(recent) / 60.0,
        "queue_wait_ms": {
            "p50": percentile(waits, 0.50),
            "p95": percentile(waits, 0.95),
            "p99": percentile(waits, 0.99),
        },
        "e2e_ms": {
            "p50": percentile(e2e, 0.50),
            "p95": percentile(e2e, 0.95),
            "p99": percentile(e2e, 0.99),
        },
    }


def prometheus(body: dict) -> str:
    lines = [
        "# HELP david_jobs_depth Jobs queued or running.",
        "# TYPE david_jobs_depth gauge",
        f"david_jobs_depth {body['depth']}",
        "# HELP david_jobs_succeeded_total Succeeded jobs.",
        "# TYPE david_jobs_succeeded_total counter",
        f"david_jobs_succeeded_total {body['succeeded']}",
        "# HELP david_jobs_dead_total Dead jobs.",
        "# TYPE david_jobs_dead_total counter",
        f"david_jobs_dead_total {body['dead']}",
        "# HELP david_throughput_per_s Succeeded jobs in the last 60 seconds, per second.",
        "# TYPE david_throughput_per_s gauge",
        f"david_throughput_per_s {body['throughput_per_s']}",
    ]
    for name, block in (("queue_wait", body["queue_wait_ms"]), ("e2e", body["e2e_ms"])):
        for quantile, value in (("0.5", block["p50"]), ("0.95", block["p95"]), ("0.99", block["p99"])):
            if value is None:
                continue
            lines.append(f'david_{name}_ms{{quantile="{quantile}"}} {value}')
    return "\n".join(lines) + "\n"
