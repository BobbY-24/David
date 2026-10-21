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
- the model path (`test/scorer_test.dart`, `test/model_provider_test.dart`), run against a scripted fake service:
  - a forged evidence id from the model is never cited
  - a quarantined unit cannot be cited even if the model weights it
  - a blocked question never reaches the model
  - an empty answer holds the memo
  - the panel seats work on model weights, and a lead that rests on one record dissents
- the Settings screen (`test/settings_test.dart`): the key field is masked and clears on save, only the last four characters are shown, the key never appears on screen, and the memo says when Claude scored it

No test calls Anthropic. The service tests use a fake client, so they spend nothing and need no key.

The service tests (`service/tests/`) also check the vault: ciphertext round-trips, a stored key cannot move to another provider, tampering and a changed master key are detected, the database holds no plaintext, the key never appears in a response, an error, or a log, and the optional token and the daily cap are enforced.

## CI

`.github/workflows/ci.yml` runs format, analyze, and `flutter test`, checks that the exported fixtures are current, and runs pytest against Postgres 16.
