# Control plane

The router picks the loop from the engagement before any search.

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

## Rails

The rails follow the OWASP LLM Top 10 for 2025.

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

## Decision

Every memo ends in one of four decisions: proceed, proceed with conditions, hold, or walk away.

- **Walk away** when a deal-breaker risk is triggered. It is triggered when its net score is at least 1.0 and it has at least one supporting unit. It applies even when another risk leads.
- **The lead's outcome** when the memo is resolved. Each risk carries the outcome it recommends.
- **Hold** when the memo is not resolved.

A conditional decision lists the lead's action as its condition. The memo shows the decision, any triggered deal-breakers, and the conditions. The decision is untuned: the threshold and the outcomes on the demo risks are judgment calls, not measured values.
