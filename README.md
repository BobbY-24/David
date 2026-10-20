# Fieldline

Fieldline is an investigation desk for business due diligence and physical-anomaly cases. It keeps sensor readings and records sealed with provenance, retrieves them as grounded evidence, and runs a multi-stage agent that scores competing explanations before writing a decision memo.

The three bundled cases are synthetic fixtures. The running policy is deterministic and offline (`grounded-policy-v1`). It does not call a live model, and a memo from these fixtures is not a finding about a real site or a real transaction.

## Run

Install Flutter 3.47 or newer, then:

```bash
flutter pub get
flutter test
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 43123
```

Open http://127.0.0.1:43123

## Desk

- **Brief.** The question, the decision criteria, the retrieval passes, and the explanations the agent is allowed to score.
- **Observations.** Sensor series and records. Open a point to read the collection and ingest seal.
- **Retrieve.** BM25 over that case, with modality and source filters. A blank query browses the newest units and scores them at zero.
- **Agent.** Scope, planned searches, a second pass for any missing modality, a support-and-falsify probe for each explanation, adjudication, then the memo.
- **Explanations.** Support minus falsifiers, with the evidence ids that fired.
- **Report.** Decision memo. Every citation is an id retrieved in that run.

A phrase does not count when `no`, `not`, `without`, `never`, or `none` appears within the three tokens in front of it. "No integration defect" is not evidence of an integration defect.

## Control plane

The router picks the loop from the case before any search:

- **Plan and execute** when the brief already decomposes the work. Searches run as a batch, then one memo. Vault C-12. This is the ReWOO shape: fewer dependent steps, higher throughput.
- **ReAct** when a sensor conflict is present or six or more modalities are required. The next search depends on what is still missing, and a repeated query stops the loop. Harbor Substation 4. A margin under 0.45 escalates to the panel instead of another open-ended loop.
- **Panel vote** for due diligence. Operations, measurement, and adversary seats score the same retrieved set. A majority has to match the unweighted lead or the memo stays held. Northline Logistics.

Rails follow the OWASP LLM Top 10 for 2025 and the current agent-SDK split between automatic checks and human approval:

- Input rail blocks instruction overrides and missing case grants before a tool call (LLM01).
- Evidence that contains an instruction override is quarantined and cannot support a hypothesis.
- The tool gateway allowlists `search`, checks the case grant, and spends a per-run call budget. `reenergize` and any other tool is denied and still audited (LLM06, excessive agency).
- The audit log stores a redacted query and a hash chain, not the raw evidence text (LLM02, RAG logging guidance).
- The output rail holds a memo whose citations were not retrieved, whose confidence exceeds 95%, or that speaks as if an operational action already ran.
- Approval is required before anything that would re-energize equipment, release lots, or move money. No such tool exists on the allowlist.

`InvestigationQueue` is the batch lane: a fixed number of runs in flight and a hard cap on the batch. A larger submit is rejected.

## Code

- `lib/src/retrieval/evidence_index.dart` searches one case corpus.
- `lib/src/agent/investigation_agent.dart` runs the routed investigation.
- `lib/src/control/` holds the router, rails, tool gateway, and queue.
- `lib/src/data/` holds Harbor Substation 4, Northline Logistics, and Vault C-12.
- `lib/src/ui/` is the desk. The Control tab shows the loop, the rails, the seats, and the audit.

`flutter test` checks retrieval, negation, which explanation leads each case, that cited ids were actually retrieved, and the desk at desktop and phone width.
