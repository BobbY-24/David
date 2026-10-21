# Your engagements

An engagement is one counterparty decision you run: a new customer, a vendor, a partner, a contractor, an acquisition, or a lease. You start one from a spec you saved in the Library, add the evidence for it, and run it on your own Claude key.

## Creating one

1. Press **New engagement** in the left rail.
2. Pick a spec, then enter the counterparty, the deal value, and optionally the jurisdiction, website, and context.
3. The engagement **pins the spec version** you chose, with its content hash. A memo states that version, so it can be traced later.

## Adding evidence

Open the **Evidence** tab of your engagement and paste a record: a title, its source, whether it is a record or a metric, the date it was observed, and the text.

- The text is encrypted on the job service. The desk keeps it only in memory.
- Text that tries to instruct the model (for example "ignore previous instructions") is **quarantined** when it is saved. It is shown as quarantined and is never sent to Claude.
- Each engagement holds at most 60 units, and each unit is at most 4,000 characters.

## Running it

Running a user engagement needs your Claude key (see [Your own model key](KEYS.md)). The model reads the evidence the run retrieved and returns weights, and David computes the decision. The memo then applies the company's **exposure rule**:

- If the deal value is larger than the **maximum exposure per counterparty** in your company profile, a "proceed" becomes "proceed with conditions". The memo names the limit as a condition.

The profile's deal-breakers are added to every engagement as risk questions. A triggered deal-breaker forces walk away. See [Control plane](CONTROL_PLANE.md#decision).

## Limits

- Pasted text only. Files and PDFs are not supported yet.
- Engagements are kept in the job service, with no accounts yet. Keep the service on a local host or set `DAVID_API_TOKEN`.
- The exposure rule and the deal-breaker rule are untuned rules, not measured ones.
