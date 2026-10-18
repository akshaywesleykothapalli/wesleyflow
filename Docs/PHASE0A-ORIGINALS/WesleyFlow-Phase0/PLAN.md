# Phased implementation plan

Each phase requires explicit authorization; completion never starts the next phase automatically.

| Phase | Scope | Exit evidence |
|---|---|---|
| 0A — current review | Environment discovery, architecture, ADRs, standards, testing/security plan and project instructions | Review packet delivered; implementation awaits approval |
| 0B — after architecture approval | Independent Git repo, Xcode app, minimal native window, small Domain module, foundational tests | Actual Debug/Release build and test results; launch status; clean dependency configuration; no voice/agent feature claims |
| 1 — task and permission foundation | Coordinator, durable history, recovery, cancellation, broker; first bounded workspace read operation | State/cancellation/recovery tests; denied operation creates no effect; history survives relaunch |
| 2 — offline voice | Capture/transcription separation, on-device language feasibility, dictation UX and explicit task submission | Network-disabled device test, permission-denial paths, measured latency/memory, no execution from recognition alone |
| 3 — local models | Provider capability contract, measured engine/model selection and one integration | License/format record, offline inference, load/unload/cancel tests and M4/16 GB resource evidence |
| 4 — approved macOS/workspace automation | Narrow useful commands, root-scoped access, process lifecycle and permission UX | Exact approved effects, denied/outside-root cases, process cleanup and partial-effect reporting |
| 5 — project understanding and coding agent | Bounded context, one compatible runtime adapter, reviewed patch proposals and conflict checks | Reproducible small repo task, context/patch audit, changed-file conflict rejection, broker enforcement |
| 6 — build/test verification | Explicit build/test plans, result capture, failure classification and truthful completion reports | Passing and failing fixture projects, cancellation/timeout evidence, uncertain result handling |
| 7 — hardening and provider replacement | Second provider/runtime only if required; performance, accessibility, release security and model artifact extensibility | Provider substitution contract tests, target-OS matrix, signing/notarization, measured memory/thermal behavior |

Future custom fine-tuned model support means compatible model artifacts and provider adapters. Dataset collection, training infrastructure, model quality and licensing require a separate proposal. No training implementation is planned here.

## Decisions and risks still open

- Approve direct distribution without App Sandbox, understanding arbitrary project code is not contained. Strong isolation is a separate design gate before supporting untrusted autonomous execution.
- Choose speech API/languages only after offline availability and quality testing. No cloud fallback.
- Choose inference engine, model and coding runtime after compatibility, licensing, cancellation and memory measurements. None is selected or downloaded now.
- Confirm application bundle identifier and signing team during project setup; unsigned local builds can verify compilation but cannot validate production permission/signing behavior.
- Establish stable Xcode release baseline and macOS 26 test access. The current beta host is insufficient for minimum-OS runtime proof.
- Define task/history retention budgets and measurable product performance targets when real workloads exist.
- Test SwiftData recovery/migration behavior before treating history as durable production infrastructure.

Phase 0B is complete only when the app foundation exists and actual verification is reported. This packet completes Phase 0A, not the whole foundation milestone.
