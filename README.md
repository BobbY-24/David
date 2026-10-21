![David: Your deal. Your evidence. A memo you approve.](assets/github-banner.svg)

# David

[![ci](https://github.com/BobbY-24/David/actions/workflows/ci.yml/badge.svg)](https://github.com/BobbY-24/David/actions/workflows/ci.yml) ![flutter](https://img.shields.io/badge/flutter-3.47%2B-blue) ![python](https://img.shields.io/badge/python-3.12-blue) ![license](https://img.shields.io/badge/license-MIT-green)

**Check a customer, vendor, or acquisition before you commit money — with a memo that cites every record it used.**
Synthetic engagements and an offline demo scorer. No model calls. Nothing here is legal, credit, or investment advice.

[Quick start](#quick-start) · [Engagements](#engagements) · [How it decides](docs/CONTROL_PLANE.md) · [Job service](docs/JOB_SERVICE.md) · [Docs](#documentation)

<picture>
  <source media="(max-width: 760px)" srcset="assets/workflow-mobile.svg">
  <img src="assets/workflow.svg" alt="From a deal question to a memo you approve: describe the deal, the router picks a loop, the gateway gathers sealed evidence, the agent scores risk questions, and the rails hold or release the memo.">
</picture>

## Quick start

Paste into **Claude Code, Codex or another local coding agent**:

```text
Set up David from https://github.com/BobbY-24/David.
Install Flutter 3.47.7 if it is missing, run flutter pub get and
flutter test, then serve the desk on 127.0.0.1:43123 and open it.
```

Flutter 3.47 or newer · runs offline, no keys needed.

<details>
<summary>Prefer manual setup? Copy these commands.</summary>

```sh
gh repo clone BobbY-24/David
cd David
flutter pub get
flutter test
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 43123
```

Open http://127.0.0.1:43123. For the job service and its Postgres setup, see [Job service →](docs/JOB_SERVICE.md).

</details>

The default run is the offline `DemoProvider`: deterministic, synthetic engagements, no network calls, and no key. A bring-your-own-key model provider is planned for the job service, and keys never go in the client. [Providers →](docs/DESK.md#providers)

## Engagements

| Engagement | Deal type | Loop | What the demo shows |
|---|---|---|---|
| Brightline Supply | Vendor | Plan and execute | A real, solvent vendor with a delivery problem. "No tax lien" does not count as a tax lien. |
| Corvid Retail | New customer | ReAct | The registry says dissolved, but the website shows orders. The business trades through a successor entity. |
| Northline Logistics | Acquisition | Panel vote | A revenue spike resting on a related party. The robustness seat dissents because the lead depends on one memo. |

Pick one and press **Run diligence**. The Control tab shows which loop ran and why.

## What every memo guarantees

- It cites only evidence that run retrieved.
- A negated phrase does not count as support.
- A thin margin holds the decision instead of guessing.
- David never pays, signs, orders, or contacts the counterparty. A person approves those.
- It is decision support, not legal, credit, or investment advice.

## Documentation

[Desk guide](docs/DESK.md) · [Control plane](docs/CONTROL_PLANE.md) · [Job service](docs/JOB_SERVICE.md) · [Testing](docs/TESTING.md)

David P0 · `grounded-control-v4` · [MIT license](LICENSE).
