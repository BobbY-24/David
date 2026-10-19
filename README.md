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

## Code

- `lib/src/retrieval/evidence_index.dart` searches one case corpus.
- `lib/src/agent/investigation_agent.dart` runs the investigation.
- `lib/src/data/` holds Harbor Substation 4, Northline Logistics, and Vault C-12.
- `lib/src/ui/` is the desk.

`flutter test` checks retrieval, negation, which explanation leads each case, that cited ids were actually retrieved, and the desk at desktop and phone width.
