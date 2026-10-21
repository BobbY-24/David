# Testing

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

## CI

`.github/workflows/ci.yml` runs format, analyze, and `flutter test`, checks that the exported fixtures are current, and runs pytest against Postgres 16.
