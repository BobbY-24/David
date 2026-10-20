# David

David is a due-diligence desk for one-person companies and small businesses. Each check is an **engagement**: a decision about a counterparty (a new customer, a vendor, a partner, a contractor, an acquisition target, or a lease). David keeps the records and metrics for that decision sealed with provenance, retrieves them as grounded evidence, scores the engagement's **risk questions**, and writes a decision memo that a person approves.

The bundled engagements are synthetic fixtures. Runs go through the offline `DemoProvider` (policy `grounded-control-v4`), and the job service uses `demo-scorer-v3`. Neither calls a live model. A memo from these fixtures is not a finding about a real business, and nothing here is legal, credit, or investment advice.

## Run

Install Flutter 3.47 or newer, then:

```bash
flutter pub get
flutter test
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 43123
```

Open http://127.0.0.1:43123

## Engagements

| Engagement | Deal type | Loop | What the demo shows |
|---|---|---|---|
| Brightline Supply | Vendor | Plan and execute | A real, solvent vendor with a delivery problem. "No tax lien" does not count as a tax lien. |
| Corvid Retail | New customer | ReAct | The registry says dissolved, but the website shows orders. The business trades through a successor entity. |
| Northline Logistics | Acquisition | Panel vote | A revenue spike resting on a related party. The robustness seat dissents because the lead depends on one memo. |

## Desk

- **Brief.** The question, the decision criteria, the retrieval passes, and the risk questions the agent is allowed to score.
- **Evidence.** Records and metric series. Open one to read its source, collection time, and ingest seal.
- **Retrieve.** BM25 over that engagement, with modality and source filters. A blank query browses the newest units and scores them at zero.
- **Agent.** Scope, planned searches, a second pass for any missing kind of evidence, a support-and-falsify probe for each risk, adjudication, then the memo.
- **Risks.** Support minus falsifiers, with the evidence ids that fired.
- **Report.** Decision memo. Every citation is an id retrieved in that run.

### How negation is handled

A phrase does not count when `no`, `not`, `without`, `never`, or `none` appears among the three content words in front of it, in the same sentence.

- Function words such as "of" and "a" do not use up the window, so "no sign of a mail drop address" is negated.
- A sentence break ends the window, so in "No dispute. Mail drop address on every invoice." the phrase still counts.
- "No integration defect" is not evidence of an integration defect.

## Providers

`EngagementProvider` is where a run's reasoning comes from. P0 ships only `DemoProvider`, which is offline and deterministic: it scores hand-written phrase signatures over BM25 retrieval. A model-backed provider will run in the job service with the customer's own key, and will still have to cite only ids its run retrieved. A provider key never belongs in this client.

## Control plane

The router picks the loop from the engagement before any search:

- **Plan and execute** when the brief already lists the checks. Searches run as a batch, then one memo. Example: Brightline Supply.
- **ReAct** when the brief reports conflicting records, or six or more kinds of evidence are required. Example: Corvid Retail.
  - The next search depends on what is still missing, and a repeated query stops the loop.
  - A margin under 0.45 escalates to the panel instead of another open-ended loop.
  - After escalation, the memo is released only if all three seats agree on a strict lead, and confidence is capped at 50%.
- **Panel vote** for an acquisition. Example: Northline Logistics. The three seats read the same retrieved set through different tests, and no seat is weighted toward a named risk:
  - The analyst scores it plainly.
  - The robustness seat drops the single strongest supporting record behind each risk, so a lead that rests on one record does not survive.
  - The skeptic counts falsifiers double.

  A seat with a tie abstains. A majority has to match the unweighted lead, or the memo stays held. A dissenting seat is written into the memo's gaps.

### Rails

The rails follow the OWASP LLM Top 10 for 2025:

- **Input rail:** blocks instruction overrides and missing engagement grants before any tool call (LLM01).
- **Quarantine:** evidence that contains an instruction override cannot support a risk, and the data rail shows a flag.
  - Patterns run on lowercased text with zero-width characters and punctuation removed.
  - They are a tripwire, not a classifier, so a paraphrase can still get through.
- **Tool gateway:** allowlists `search`, checks the engagement grant, and spends a per-run call budget. `send_payment` and any other tool is denied, and the attempt is still audited (LLM06, excessive agency).
- **Audit log:** stores a redacted query and a hash chain, not the raw evidence text (LLM02).
- **Output rail:** holds a memo when:
  - a citation was not retrieved
  - confidence exceeds 95%
  - its headline, note, findings, or action speak as if a payment, signature, order, or message already happened

  The scorer itself has no confidence ceiling, so the rail is the only place the cap is enforced.
- **Approval:** a person approves anything that would pay, sign, order, or contact the counterparty. No such tool exists on the allowlist.

`EngagementQueue` is the batch lane: a fixed number of runs in flight and a hard cap on the batch. A larger submit is rejected.

## Code

- `lib/src/retrieval/evidence_index.dart` searches one engagement's corpus.
- `lib/src/agent/provider.dart` defines `EngagementProvider` and `DemoProvider`.
- `lib/src/agent/engagement_agent.dart` runs the routed engagement.
- `lib/src/control/` holds the router, rails, tool gateway, and queue.
- `lib/src/data/` holds Brightline Supply, Corvid Retail, and Northline Logistics.
- `lib/src/ui/` is the desk. The Control tab shows the loop, the rails, the seats, and the audit.

`flutter test` checks:

- retrieval, negation, and which risk leads each engagement
- that cited ids were actually retrieved
- the desk at desktop and phone width
- the rails on forged drafts: an unretrieved citation, confidence over the cap, a claim that an action ran, and obfuscated instruction overrides (`test/rails_test.dart`)
- escalation: a thin margin that holds up is released, and a thin lead that rests on one record is not
- `test/heldout_test.dart`: supplier-invoice cases written to break a phrase scorer:
  - a far negation
  - a negation across a sentence break
  - keyword stuffing
  - a planted zero-width instruction
  - a tie
  - every risk falsified

  This is a regression check for the demo provider, not a measure of model quality.
- that `service/david_lab/cases.json` matches the desk engagement packs

## Job plane

The Jobs tab submits work to a single-host service:

- FastAPI accepts the request, PostgreSQL stores the job, and a Celery worker wakes from Redis and runs it.
- The worker's claim is a conditional row update, so a duplicate delivery cannot finish the same attempt twice.
- Transient failures requeue until `MAX_ATTEMPTS`. Each retry is scheduled on the broker with a countdown, so a job in backoff does not hold a worker slot.
- A full lane returns HTTP 429.
- `GET /v1/metrics` reports queue depth, throughput over the last minute, and p95/p99 queue wait and end-to-end latency.
- CORS allows only the desk dev server (`http://127.0.0.1:43123` and `http://localhost:43123`) by default. Set `CORS_ORIGINS` to a comma-separated list to change that.
- The API has no authentication, so keep it on a local host.

The service runs two job kinds:

- **Engagement.** Each desk engagement is read from `david_lab/cases.json`.
  - That file is exported from the desk engagement packs with `dart run tool/export_cases.dart`, so the desk is the only place an engagement is written.
  - The service ports the desk phrase matcher, and its tests check it against every match verdict the desk exported.
  - It sums signature weights without BM25, so a margin is on a different scale from the desk's. The desk agent is still the citation path.
- **Probe.** A load-test job that does nothing but optionally sleep.

From `service/`, with PostgreSQL and Redis already running:

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt
export DATABASE_URL=postgresql+psycopg://david:david@127.0.0.1:5432/david
export REDIS_URL=redis://127.0.0.1:6379/0
.venv/bin/uvicorn david_lab.api:app --host 0.0.0.0 --port 43124
.venv/bin/celery -A david_lab.worker:celery_app worker --loglevel=INFO --concurrency=2
```

The local database password above is a development default.

Docker Compose runs the same four processes:

```bash
docker compose -f service/docker-compose.yml up --build
```

That publishes the API on port 43124, Postgres on 54329, and Redis on 63799.

```bash
cd service && .venv/bin/pytest
```

The tests use `postgresql+psycopg://david:david@127.0.0.1:5432/david_test` unless `TEST_DATABASE_URL` is set.

CI (`.github/workflows/ci.yml`) runs format, analyze, and `flutter test`, checks that the exported fixtures are current, and runs pytest against Postgres 16.
