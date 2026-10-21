# Agent specs and the company profile

A spec is the agent you define: the deal question, the checks to run, the risk questions to weigh, and what each one recommends. You edit it in the **Library** tab. The offline demo has no specs of its own; specs are for runs on your own Claude key.

## Specs are versioned

- Saving a new spec creates **version 1**. Saving a change to an existing spec creates the **next version**. Earlier versions are never edited.
- Each version carries a content hash. A run records the spec id, version, and hash it used, so a memo can always be traced to the exact spec behind it.
- Saving the same content again is refused, so a version always means a real change.

## What a spec contains

- **Deal type and question.** What is being decided, for example "Should we ship a first order on 60-day terms?"
- **Decision criteria.** Up to eight lines the decision should satisfy.
- **Checks.** Up to twelve searches the run makes, each a title, a search phrase, and a kind (record or metric).
- **Risk questions.** Two to eight. Each has an id, a title, the statement that would be true if the risk is real, the outcome it recommends (proceed, proceed with conditions, hold, or walk away), the action to take if it leads, and whether it is a **deal-breaker**.
- **Questions to ask** the counterparty.

## Deal-breakers and the company profile

- A deal-breaker risk with enough support forces **walk away**, even when another risk leads. See [Control plane](CONTROL_PLANE.md#decision).
- The company profile holds the name, industry, jurisdictions, currency, and maximum exposure per counterparty, plus deal-breakers that apply to every engagement. It is one record per install.

## Starter templates

Six templates ship with the desk: new wholesale customer, vendor, partner or reseller, contractor or freelancer business, acquisition target, and lease or landlord. Each passes the same rules the service enforces. Start from one, then edit it. The templates are a starting point and have not been measured against real outcomes.

## Limits

- Specs are stored in the job service, with no accounts yet. Anyone who can reach the service can read and change them, so keep the service on a local host or set `DAVID_API_TOKEN`.
- A user risk has no hand-written phrases, so the offline demo cannot score it. Specs run on your own key.
