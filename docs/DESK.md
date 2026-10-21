# Desk guide

The desk is the Flutter web app. Each engagement opens on its own brief and has these tabs.

- **Brief.** The question, the decision criteria, the retrieval passes, and the risk questions the agent is allowed to score.
- **Evidence.** Records and metric series. Open one to read its source, collection time, and ingest seal.
- **Retrieve.** BM25 over that engagement, with modality and source filters. A blank query browses the newest units and scores them at zero.
- **Agent.** Scope, planned searches, a second pass for any missing kind of evidence, a support-and-falsify probe for each risk, adjudication, then the memo.
- **Risks.** Support minus falsifiers, with the evidence ids that fired.
- **Report.** Decision memo. Every citation is an id retrieved in that run.
- **Control.** The loop the router picked, the rails, the panel seats, and the audit log.
- **Jobs.** Submits engagements to the job service. See [Job service](JOB_SERVICE.md).
- **Library.** Your company profile and the agent specs you run, saved as numbered versions. See [Agent specs](SPECS.md).
- **Settings.** Connect your own Claude key, choose the model, and choose between the offline demo and Claude. See [Your own model key](KEYS.md).

## How negation is handled

A phrase does not count when `no`, `not`, `without`, `never`, or `none` appears among the three content words in front of it, in the same sentence.

- Function words such as "of" and "a" do not use up the window, so "no sign of a mail drop address" is negated.
- A sentence break ends the window, so in "No dispute. Mail drop address on every invoice." the phrase still counts.
- "No integration defect" is not evidence of an integration defect.

## Providers

`EngagementProvider` is where a run's reasoning comes from. There are two.

- **`DemoProvider`** is offline and deterministic. It scores hand-written phrase signatures over BM25 retrieval and needs no key.
- **`ModelProvider`** scores with your own Claude key. It retrieves offline first, asks the job service for per-risk evidence weights, then runs the agent again with those weights, so the router, the panel seats, the memo, and the rails apply unchanged. It can only cite ids the run retrieved. See [Your own model key](KEYS.md).

A provider key never belongs in this client: it lives encrypted in the job service. Both providers sit behind `RiskScorer`, so a run differs only in how a risk is weighed.

## Code map

- `lib/src/retrieval/evidence_index.dart` searches one engagement's corpus.
- `lib/src/agent/provider.dart` defines `EngagementProvider` and `DemoProvider`.
- `lib/src/agent/scorer.dart` defines `RiskScorer`, `PhraseScorer`, and `ModelScorer`.
- `lib/src/agent/model_provider.dart` runs an engagement on the user's Claude key.
- `lib/src/jobs/model_service.dart` is the desk's client for the key vault and the model route.
- `lib/src/agent/engagement_agent.dart` runs the routed engagement.
- `lib/src/control/` holds the router, rails, tool gateway, and queue.
- `lib/src/data/` holds Brightline Supply, Corvid Retail, and Northline Logistics.
- `lib/src/ui/` is the desk.
