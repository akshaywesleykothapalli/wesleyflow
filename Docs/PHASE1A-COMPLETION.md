# Phase 1A completion report

18 October 2026 · `$REPO_ROOT`

**Decision: Phase 1A service foundation complete on the recorded development lane. Stop after Phase 1A.** Durable task orchestration, bounded FIFO scheduling, scoped permission policy, persistence, cancellation/timeouts, interrupted recovery, sanitized event logging and revision-bound verification interfaces are implemented and tested. Only deterministic no-effect executors are supplied in tests. See [implementation decisions and limits](PHASE1A-IMPLEMENTATION.md).

## Actual acceptance results

| Check | Actual result | Evidence under `Evidence/Phase1A/` |
|---|---|---|
| Debug native build | Exit 0 | `final-debug-confirm.json`, `.log`, `.xcresult` |
| Release native build | Exit 0 | `final-release.json`, `.log`, `.xcresult` |
| Full native automated suite | Exit 0; 43 functions, 219 concrete cases; zero failures/skips | `final-tests-confirm.*`, `final-tests-confirm-summary.log` |
| Separate test-without-building replay | Exit 0; same 43 functions/219 cases; zero failures/skips | `final-replay-confirm.*`, `final-replay-confirm-summary.log` |
| Abrupt exit after committed intent | Expected exit 77, observed 77 | `crash-probe-write-v3.json`, `.log` |
| Fresh-process recovery, then second reopen | Both exit 0; interrupted from running, inspection required, no restored approval, zero executor calls; audit count remains 3 | `crash-probe-recover-v3.*`, `crash-probe-second-recover-v3.*` |
| Dependencies, source identity, preservation, Git | No external package dependencies; final evidence source hashes match; historical documents and original Domain tests preserved; diff whitespace check passes | `final-package.*`, `final-settings.*`, `final-audit.json` |

The 43 functions comprise 11 existing Domain functions, 5 app composition functions and 27 Phase1A functions. Parameter expansion accounts for the 219 cases; this is read from xcresult's device summary, not inferred from discovery. The hosted app ran during composition tests. No separate manual UI, consent or production-adapter acceptance is claimed. Raw results and critical recovery scenarios were inspected/replayed in this task; no separate human or second-agent review is claimed.

Tests cover finite transitions, immutable retry linkage, ordered intent/outcome persistence, exact one-use grants, denial/expiry/revocation/stale session/scope/digest/generation, unsupported effect rejection, FIFO overflow, each-step/verification approval, verification failure/stale evidence, virtual deadlines and cumulative budget, held workers, five-second quarantine, late callbacks, cancellation across pre-dispatch/result saves, emergency cleanup during storage failure, uncertain save acknowledgements, single-writer protection, corrupt/unknown stores, quota rejection, safe retention, and interrupted recovery from six lifecycle states. The real SwiftData repository is reopened in tests; coordinator fault scheduling uses deterministic doubles and explicit barriers.

## Environment and scope

Explicit developer directory: `/Applications/Xcode-beta.app/Contents/Developer`. Xcode 27.0 beta (27A5237l), Swift 6.4, macOS SDK 27.0; host macOS 27.2 (26B5091g), Apple M4, 16 GiB RAM, arm64. Swift 6 mode, tools 6.2 and deployment target 26.0 remain configured. Binary deployment metadata and exact tool outputs are in `final-audit.json`; commands, UTC timestamps, exits, log hashes and source hashes accompany each run. Build caches are in `DerivedData/Phase1A-Final/`. No global toolchain selection or dependency installation was changed.

All permission-requiring repository writes and build/test executions used native Codex approval. No legacy source was inspected/copied, unrelated project files changed, application microphone/Accessibility/Automation permissions requested, or GitHub push performed. The only abrupt exit belongs to the purpose-built evidence fixture, which writes its own isolated store.

## Failures found and resolved

Earlier attempts remain in the evidence directory. A Swift test continuation inference compile error was fixed with its explicit type. A SwiftData context queue-affinity warning was fixed with off-caller construction and its serial model executor; final test summaries contain no runtime warnings. Cancellation barrier tests initially released a held commit before revocation actually occurred; they now await an explicit completed-revocation handshake.

A stale mixed module layout caused an outdated policy signature to be imported. An attempted explicit-dynamic package configuration was rejected by Xcode's package graph; automatic products were restored and a fresh final build directory used. All final compiles/tests pass. A test-only replay after a standalone app build failed because that build removed the hosted test bundle; regenerating tests and immediately replaying them passed. Final successful replay evidence is `final-replay-confirm`, not the failed `final-replay` bundle.

Remaining nonfatal diagnostics include Xcode's unused AppIntents metadata warning and host linkd registration noise. The standalone recovery-probe source also has an unnecessary-await warning; its compile and expected runtime exits passed. These are retained, not omitted from evidence.

## Remaining gates and handoff

Actual macOS 26.0 runtime and full Xcode 26.3/Swift 6.2.3 compatibility remain unverified. Current results do not satisfy GC or shipping/signing/notarization gates. No real filesystem/process effects, agent, speech, inference, automation, approval UI or real build/test verification adapter is enabled. This narrower Phase1A completion does not claim full future G1/GE integration matrices: path/symlink races, artifact publication, future schema migrations, physical quota enforcement and real provider containment need their own implementation and evidence. Store admission estimates and explicit retention maintenance are described precisely in the implementation record.

Git remains on `main` at baseline commit `936089b5618ef5fdf9d6495570a4a59d7a144a96`; Phase1A changes are intentionally uncommitted and unstaged. Existing files were preserved and extended, with new Domain/service/test/document files. Exact final status and tracked diff are retained in `final-audit.json` and `git-final.txt`; build products/raw evidence are Git-ignored. No commit, remote or push was added. No later phase has started.
