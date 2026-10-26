# Phase 1A final engineering audit

19 October 2026 · Wesley Flow · Audit of the existing uncommitted working tree

**Recommendation: HOLD Phase 1B.** Fresh Debug/Release builds and the existing 219 concrete test cases pass, but four independently driven adversarial scenarios reproduce P1 correctness defects. No P0 finding was established in the currently restricted, no-real-executor scope. One P2 observation concerns cancellation of state observers. The earlier Phase1A completion report remains preserved as a historical implementation record; passing its checks does not establish readiness for Phase1B.

## Scope and method

Read root AGENTS.md, the amended architecture/dependency graph, ADRs, security, development, environment, testing and phase plan, amendment traceability/consistency/risk material, both Phase1A reports, every application/core/test source file, package manifest, shared scheme, and Git changes. Reviewed all three new service modules and their Domain ports against the inward dependency allowlist.

Used a new build directory and fresh result bundles, inspected raw output, and ran standalone audit drivers against the freshly built modules. The drivers reuse existing deterministic fixture implementations; the new adversarial orchestration is outside application/test source. One fixture clock additionally advances time without delivering its timer continuation, representing delayed timer scheduling. No real system effects are supplied. Recovery probes use isolated audit stores. This is a separate audit execution and reasoning pass in this chat, not a claim of an external human or second-agent review.

No application, package, project or existing test source was modified. No repository was initialized, commit/staging/push performed, or Phase1B/voice/AI feature added. Additions are this report and Git-ignored audit evidence. The final source guard compares all pre-existing tracked/untracked file bytes with the pre-build snapshot.

## Verified execution

All artifacts below are in [Evidence/Phase1A-Audit-2026-10-19](../Evidence/Phase1A-Audit-2026-10-19). Each command has a JSON record with argv, exit, timestamp and its log. Build/test records include source hashes and report `source_unchanged: true`.

| Execution | Exit/outcome | Evidence |
|---|---|---|
| Fresh Debug native build | 0, BUILD SUCCEEDED | `debug.json`, `debug.log`, `debug.xcresult` |
| Fresh Release native build | 0, BUILD SUCCEEDED | `release.json`, `release.log`, `release.xcresult` |
| Complete existing native suite | 0, TEST SUCCEEDED; 43 functions / 219 concrete cases; 0 failed, 0 skipped | `tests.json`, `tests.log`, `tests.xcresult`, `tests-summary.log` |
| Recovery tests within suite | Six interrupted-state cases and two save-fault cases pass, alongside reopen, single-writer, corruption, quota and retention tests | `tests.log`, `tests.xcresult` |
| Standalone abrupt-exit probe compilation | 0 | `crash-compile.json`, `.log` |
| Abrupt exit after committed synthetic running/intent snapshot | Expected 77; actual 77 | `crash-write.json`, `.log` |
| Fresh-process recovery and second reopen | 0, 0; failed.interrupted, prior running, inspection required, no restored approval, zero executor calls; event count stays 3 | `crash-recover.*`, `crash-recover-again.*` |
| Four adversarial probes | Each driver exits 0 after recording the defect; these are **not four passing acceptance tests** | `probe-cancel-evidence.*`, `probe-late-result.*`, `probe-stalled-save.*`, `probe-submit-shutdown.*` |
| Observer cancellation probe | Driver exits 0; cancelled observer remains suspended | `probe-cancelled-observer.*` |

Counts come from the fresh xcresult summary: 11 Domain, 5 composition and 27 Phase1A test functions; parameter expansion yields 219 cases. No test was skipped or relabeled. The crash fixture proves recovery of its committed synthetic ledger, not power-loss durability or a complete crash matrix during live coordinator execution.

Selected environment was explicitly `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`: Xcode 27.0 beta build 27A5237l, Swift 6.4 (swiftlang-6.4.0.30.4), SDK 27.0. Actual audit host is macOS 27.2 **26B5112a**, arm64, Apple M4, 16 GiB. This differs from the old report's host build. Release binary metadata reports minimum OS 26.0 / SDK 27.0. No global developer selection was changed. `env-*.json/.log` retain tool, effective app settings, package, binary and Git inspection output. The manifest has no external dependencies; TaskExecution/Persistence/SystemOperations depend only on Domain.

The actual build/test commands, run from the repository root with that developer-directory override, were:

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Phase1A-Audit-20261019 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1A-Audit-2026-10-19/debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Phase1A-Audit-20261019 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1A-Audit-2026-10-19/release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Phase1A-Audit-20261019 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1A-Audit-2026-10-19/tests.xcresult test
```

Exact Swift compiler/linker commands and standalone probe invocations are in `audit-probes-compile.json`, `observer-probe-compile.json`, `crash-compile.json` and the corresponding per-probe JSON. Sources and runner scripts are retained alongside them. Raw diagnostics include nonfatal unused-AppIntents metadata and host linkd registration messages; the copied crash helper has an unnecessary-await warning. No SwiftData queue-affinity warning or Swift concurrency compile failure appeared; xcresult runtimeWarnings is empty. Passing compilation does not exclude actor reentrancy bugs.

## Findings

### A1 — P1: cleanup invents resolution of unknown operation outcomes

**Location:** [TaskCoordinator.swift:332](../Packages/WesleyFlowCore/Sources/TaskExecution/TaskCoordinator.swift), also startup recovery at line 70; [TaskServices.swift:93](../Packages/WesleyFlowCore/Sources/Domain/TaskServices.swift).

**Problem:** `.stopped` acknowledges resource cleanup, but the coordinator assigns every intent to `outcomes` without an operation result or per-operation effect disposition. Stopping a provider cannot establish whether an operation completed, partially completed, or never applied. This removes the unresolved-intent signal used by recovery and retention. The problem is audit-state accuracy; no real filesystem modification is claimed in this probe.

**Evidence:** `probe-cancel-evidence.log` uses the real SwiftData repository and a held deterministic executor. After cancellation it records `intents=[inspect]`, `outcomes=[inspect]`, **zero outcome events**, and `unresolved_after_cancel=false`. A restarted coordinator reports `inspection_after_restart=false` and `blocked_after_restart=false`. Thus a cleanup acknowledgement erases uncertainty without any corresponding operation outcome. Safe pruning can subsequently treat that record as resolved.

**Correction:** Separate resource-release acknowledgement from operation disposition. Preserve unresolved intent unless an explicit trusted result/reconciliation establishes its status; retain inspection-required metadata for unknown dispositions. Keep task cancellation and resource lease release distinct from evidence resolution. Add cancelled-after-dispatch, partial-result and reopen/pruning regressions.

### A2 — P1: late success can defeat operation and total-task deadlines

**Location:** [TaskCoordinator.swift:210](../Packages/WesleyFlowCore/Sources/TaskExecution/TaskCoordinator.swift), deadline creation at line 184 and watchdog at lines 191–194.

**Problem:** `finished` checks generation/state, then cancels the watchdog and accepts success without checking the absolute execution deadline. Timer delivery is a scheduled task, not a guarantee that timeout runs before a provider completion. Delayed timer scheduling therefore permits a success observed after the enforced budget to become terminal success.

**Evidence:** `probe-late-result.log` advances the monotonic fixture time past the operation deadline while delaying timer continuation delivery, then releases the provider. It records deadline **301000**, completion time **301001**, and state **succeeded**. This specifically tests timer-delivery ordering; it does not use a five-minute wall-clock wait.

**Correction:** Retain absolute operation/task deadlines with operation identity and revalidate them after the provider await and before accepting/committing completion. Keep the watchdog as a wake-up mechanism, not the sole source of timeout truth. Add delayed-timer success, verification, and final cumulative-budget boundary tests.

### A3 — P1: history stalls defeat bounded cleanup and shutdown

**Location:** [TaskCoordinator.swift:299](../Packages/WesleyFlowCore/Sources/TaskExecution/TaskCoordinator.swift), [TaskCoordinator.swift:316](../Packages/WesleyFlowCore/Sources/TaskExecution/TaskCoordinator.swift), and shutdown at lines 354–358.

**Problem:** Provider cancellation starts before the cancellation save, but cancellation waits indefinitely for that save. The five-second cleanup callback first acquires the same mutation lock held across the stalled history await. Consequently it cannot publish uncommitted failure/quarantine or allow shutdown to finish within its budget. The existing test proves cleanup *invocation* before save completion, not bounded terminal reporting/quit when the save never returns.

**Evidence:** `probe-stalled-save.log` holds the cancellation commit and provider cleanup, waits for the five-second timer to be scheduled, then advances past it. At 5001 virtual milliseconds, shutdown has not returned, state is still running, and quarantine is false. The lock dependency makes this persist until the history save is released; the fixture releases it afterward to cleanly finish the audit process.

**Correction:** Make emergency revocation, quarantine and bounded shutdown reporting independent of the durable mutation gate. Track and reconcile any pending save if it eventually completes; expose an explicitly uncommitted state and retain uncertain ownership. Do not abandon an in-flight commit and claim it failed or durably terminalized. Add a never-returning-history fixture asserting bounded shutdown, visible uncertainty and no later dispatch.

### A4 — P1: in-flight admission can succeed after shutdown returns

**Location:** [TaskCoordinator.swift:86](../Packages/WesleyFlowCore/Sources/TaskExecution/TaskCoordinator.swift), especially lines 94–100, and shutdown at lines 354–358.

**Problem:** `submit` checks `stopped` only before awaiting the history commit. While that await is suspended, shutdown marks stopped and snapshots the queue/active task, which do not yet contain the submission. Shutdown returns. When the commit resumes, submission publishes/enqueues the task and returns success without rechecking shutdown. The queued task is outside the completed shutdown cancellation set; service composition may already have closed history.

**Evidence:** `probe-submit-shutdown.log` holds the submitted-event save, completes shutdown, then releases the save. It records `shutdown_returned_before_submit=true`, `submit_returned_success=true`, and `state_after_shutdown=queued`. No productive effect is dispatched because pump checks stopped, but admission/close/lifecycle ordering is incorrect.

**Correction:** Include pending admissions in shutdown ownership and define their acknowledgement/commit ordering. Recheck a shutdown/admission generation after suspension and reconcile any already-committed admission rather than silently accepting it after close. Make shutdown drain or account for pending admissions within its bounded policy. Add held-submit versus shutdown/close and cancel-during-admission tests.

### A5 — P2: cancelled state observers remain retained until a later transition

**Location:** [TaskCoordinator.swift:58](../Packages/WesleyFlowCore/Sources/TaskExecution/TaskCoordinator.swift), waiter storage/publishing at lines 25, 47–54.

**Problem:** `waitForState` stores a checked continuation without cancellation registration or waiter removal. Cancelling its calling task neither completes the wait nor releases captured observer state. Repeated short-lived observers can accumulate while the underlying task is paused/stalled. This is a demonstrated retention/lifetime issue, not an instrumented claim of a permanent heap leak.

**Evidence:** `probe-cancelled-observer.log` records `observer_cancelled=true`, `observer_completed=false` while the underlying task remains awaiting approval. It completes only after the fixture cancels/terminalizes the underlying task.

**Correction:** Give waiters identities and cancellation-safe registration/removal with exactly-once continuation completion, or provide a bounded cancellation-aware observation stream. Add observer cancellation before/during registration and repeated subscription disposal tests. Can be deferred from the Phase1B gate, but fix before relying on short-lived UI observers.

## Review conclusions and remaining risks

- **Concurrency, isolation, scheduling and lifecycle:** Framework objects remain private, mutable services are actors, UI is explicitly MainActor, and module dependencies point inward. Exhaustive pure state/event assertions are meaningful. A2–A4 are logical races/liveness problems that actor isolation and a green compiler cannot prevent.
- **Cancellation, timeouts and memory:** Generation rejection, fresh per-operation approvals and normal cooperative cancellation tests are useful. A1–A3 defeat stronger evidence/deadline guarantees; A5 retains cancelled observation tasks. No Instruments/heap-growth or Thread Sanitizer campaign was performed, so absence of other leaks/data races is not claimed.
- **Persistence and transactions:** Actual state/event saves, rollback/reopen, duplicate/stale sequence rejection, lock protection and narrow crash recovery pass. Corruption/unknown marker handling preserves fixtures. A1 undermines the semantic integrity of outcomes despite atomic database transactions. Future schema upgrades, power loss and the full crash-point matrix remain unverified.
- **Permission policy and duplicate execution:** Exact scope/digest/generation/session matching, one-use consumption, expiry and revocation tests pass; source inspection confirms actor-serialized consume after its clock await. Unsupported writes/processes/automation remain rejected. These are API boundaries, not OS containment. No current grant bypass or duplicate productive execution was established. Pending-admission shutdown ordering remains defective under A4.
- **Errors and tests:** Typed failures and visibly uncommitted storage-failure handling exist. The suite's independent transition oracle and real repository tests provide meaningful evidence. Its cancellation save test releases the save; its timeout tests deliver the timer; neither covers A2–A4. Audit drivers expose these missing assertions without changing the suite.
- **Incomplete features:** The application still shows a foundation shell. Services require explicit store URL and injected executors; no production executor, task/approval UI, voice/model/agent or real tool verification adapter is enabled. This is accurately documented and is not treated as a working future feature.
- **Other gates:** macOS 26 runtime, full Xcode 26.3/Swift 6.2.3 lane, release signing/consent, real adapter containment and model/speech resource gates remain open. Storage quota accounting is a projected-write estimate, not demonstrated hard 100 MiB enforcement; reserve behavior near capacity and physical allocation growth need evidence before production storage acceptance. Retention is explicit maintenance, not an automatically scheduled service.

## Phase1B decision and preservation

**Do not authorize Phase1B on this audit.** Resolve A1–A4 in a separately scoped repair, add the missing deterministic regressions, then rerun Debug/Release, the full suite and relevant adversarial/recovery probes. A5 is deferrable with its stated observer-use condition. Compatibility/real-effect/release gates remain separate and cannot be inferred from this host's passing suite.

The audited HEAD remains `936089b5618ef5fdf9d6495570a4a59d7a144a96`, branch main, with the prior implementation uncommitted and unstaged. No remotes are configured. Original dirty work is preserved; this report is the only additional non-ignored file. `source-preservation.json`, `git-final.txt` and `artifact-hashes.json` retain final audit preservation/status evidence. Stop after reporting; no fixes or Phase1B work were performed.
