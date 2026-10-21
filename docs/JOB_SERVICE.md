# Job service

The Jobs tab submits work to a single-host service.

- FastAPI accepts the request, PostgreSQL stores the job, and a Celery worker wakes from Redis and runs it.
- The worker's claim is a conditional row update, so a duplicate delivery cannot finish the same attempt twice.
- Transient failures requeue until `MAX_ATTEMPTS`. Each retry is scheduled on the broker with a countdown, so a job in backoff does not hold a worker slot.
- A full lane returns HTTP 429.
- `GET /v1/metrics` reports queue depth, throughput over the last minute, and p95/p99 queue wait and end-to-end latency.
- CORS allows only the desk dev server (`http://127.0.0.1:43123` and `http://localhost:43123`) by default. Set `CORS_ORIGINS` to a comma-separated list to change that.
- The job routes have no authentication, so keep the service on a local host. The vault and model routes accept an optional `DAVID_API_TOKEN`.

## Job kinds

- **Engagement.** Each desk engagement is read from `david_lab/cases.json`.
  - That file is exported from the desk engagement packs with `dart run tool/export_cases.dart`, so the desk is the only place an engagement is written.
  - The service ports the desk phrase matcher, and its tests check it against every match verdict the desk exported.
  - It sums signature weights without BM25, so a margin is on a different scale from the desk's. The desk agent is still the citation path.
- **Probe.** A load-test job that does nothing but optionally sleep.

## Key vault and model routes

These let the desk use your own Claude key. See [Your own model key](KEYS.md) for how the key is stored and what the model sees.

| Route | Purpose |
|---|---|
| `GET /v1/vault` | Status only: whether a key is saved, its last four characters, today's usage, and the allowed models. |
| `PUT /v1/vault/anthropic` | Verifies a key with a free call, then stores it encrypted. Admin keys are refused. |
| `POST /v1/vault/anthropic/verify` | Re-checks the saved key. |
| `DELETE /v1/vault/anthropic` | Removes it. |
| `POST /v1/model/judge` | Scores retrieved evidence for an engagement. Reads the sealed text itself and enforces the model allowlist and the daily cap. |

## Run it locally

From `service/`, with PostgreSQL and Redis already running:

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt
export DATABASE_URL=postgresql+psycopg://david:david@127.0.0.1:5432/david
export REDIS_URL=redis://127.0.0.1:6379/0
.venv/bin/uvicorn david_lab.api:app --host 127.0.0.1 --port 43124
.venv/bin/celery -A david_lab.worker:celery_app worker --loglevel=INFO --concurrency=2
```

The database password in these commands is a development default.

## Docker Compose

Compose runs the same four processes:

```bash
docker compose -f service/docker-compose.yml up --build
```

That publishes the API on port 43124, Postgres on 54329, and Redis on 63799, all on `127.0.0.1` only. Postgres data and the key vault's master key live in the `pgdata` and `david-data` volumes.

## Tests

```bash
cd service && .venv/bin/pytest
```

The tests use `postgresql+psycopg://david:david@127.0.0.1:5432/david_test` unless `TEST_DATABASE_URL` is set.
