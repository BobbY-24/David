# Your own model key

David can score an engagement with your own Claude API key. The Settings tab is where you connect it. Without a key, David runs its offline demo, and nothing leaves your machine.

## Connect a key

1. Start the job service (see [Job service](JOB_SERVICE.md)). The key vault lives there, not in the desk.
2. Open **Settings**, paste a regular Anthropic API key (`sk-ant-…`), and press **Save and verify**.
3. The service checks the key with a free call that reads model metadata, then stores it encrypted. Admin keys are refused.
4. Choose **Claude, your key** under "Run diligence with", pick a model, and press **Run with Claude** on any engagement.

The default model is Claude Opus 5.5. Sonnet 5.5 and Haiku 5.5 are there for lower cost. David does not choose a cheaper model for you.

## What happens to the key

- The desk sends it once to the job service on this machine, and the field clears at that moment. The desk never stores, shows, or reads it back.
- The service encrypts it with AES-256-GCM. Each key gets its own random data key, and a master key wraps that data key. The provider name is bound into both, so a stored key cannot be moved to another provider.
- Postgres holds ciphertext, the wrapped data key, the nonces, and the last four characters. The master key is never in the database.
- The master key comes from `DAVID_MASTER_KEY` (base64, 32 bytes). If that is not set, the service creates `master.key` in `DAVID_DATA_DIR` with mode 0600. The Docker setup keeps it in the `david-data` volume.
- The key is never returned by the API, never logged, and never echoed in an error. Validation errors drop the submitted value on purpose.
- The service is published on `127.0.0.1` only. An optional `DAVID_API_TOKEN` makes the vault and model routes require an `X-David-Token` header. The Settings tab has a field for it, kept in memory only.

## What the model sees and does

- A run retrieves evidence offline first. Only then does the service call Claude, with the ids of the retrieved units. The service reads their sealed text itself. The desk cannot send it different text.
- Evidence the input checks quarantined for instruction overrides is never sent.
- The model has no tools and cannot browse. It returns, for each risk question, which retrieved units support or contradict it and how strongly.
- The desk validates that answer again. A unit the run did not retrieve counts for nothing, weights are clamped, and many weak units cannot out-vote one decisive one.
- The desk computes the decision from those weights: the margin bar, the panel seats, escalation, the confidence cap, and the output rail all apply as they do for the demo.
- If Anthropic refuses, rate limits, or is unreachable, you see the reason. David does not quietly fall back to the demo.

## Limits and cost

- The service stops model calls at `DAVID_MAX_MODEL_CALLS_PER_DAY` (100 by default). Settings shows today's calls and tokens.
- Each run makes one model call, bounded to 8,000 output tokens and 60 evidence units of at most 1,500 characters.
- Calls use your key and your Anthropic billing.

## What this does not protect against

- Someone who already controls this machine and its files can read the master key and the database. The encryption protects a database dump, a backup, or a copied volume.
- The service has no user accounts. It is built for one person on one machine.
- If you lose the master key, the saved key cannot be decrypted. Settings says so and you enter the key again.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `DAVID_MASTER_KEY` | unset | Base64 of 32 random bytes. Overrides the key file. |
| `DAVID_DATA_DIR` | `~/.david` | Where `master.key` is created. |
| `DAVID_API_TOKEN` | unset | Required as `X-David-Token` on vault and model routes when set. |
| `DAVID_MAX_MODEL_CALLS_PER_DAY` | `100` | Hard cap on model calls per UTC day. |

To make your own master key: `openssl rand -base64 32`.
