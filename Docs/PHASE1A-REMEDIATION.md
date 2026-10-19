# Phase 1A remediation and final verification

19 October 2026 · Wesley Flow · Authorized Phase1A repair only

## Executive summary

**All four P1 findings are FIXED on the available development lane. The P2 observer finding is also FIXED.** Fresh Debug/Release builds pass. The final complete test run and separate replay each pass **63 functions / 258 concrete cases, zero failures/skips**. This retains the original test functions and adds 20 functions covering 39 additional cases. Six fresh-process recovery scenarios pass, including actual coordinator cancellation, exits before/after a save, and a database written by the pre-remediation v1 binary.

No Phase1B, voice, model, agent, tool executor, automation or UI redesign was implemented. The amended architecture, historical completion report and engineering audit remain unchanged. The audit findings and their reproduction evidence remain available; this record supersedes their readiness disposition for the defects repaired here.

## Corrections and second review

| Finding | Root cause and correction | Files / principal functions | Regression evidence | Status |
|---|---|---|---|---|
| A1: false cancellation resolution | Cleanup assigned all intents to outcomes. Removed that inference: stopped means resource termination only. Unknown operation disposition remains unresolved/inspectable; known terminal cancellation remains terminal. Late diagnostics never fabricate an outcome. Reopen/pruning preserve unknown evidence. | `Sources/TaskExecution/TaskCoordinator.swift`: cleanupFinished, recordLateResult; `Sources/Domain/TaskServices.swift`: acknowledgement contract | cancellationDoesNotInventOperationDisposition; cancellationBeforeExecutionDoesNotInventUncertainty; cancelledUnknownDispositionSurvivesReopenAndCannotBePruned; before/after-save interruption tests and crash matrix | **FIXED** |
| A2: late success defeats deadline | Completion trusted watchdog ordering. Retain an absolute session deadline, persist its diagnostic anchor with intent, and recheck monotonic time after provider completion and before accepting results. Exactly at the deadline is expired. Acceptance and timeout are actor-serialized; generation checks reject revoked completions. Sanitized late result diagnostics retain pass/match facts without replacing the outcome. | TaskCoordinator: resumeApproval, dispatch, finished, cancelOwned; TaskServices: optional executionDeadline/lateResults; Persistence validation/event accounting | completionDeadlineIsCheckedWithoutTimerDelivery (-1/0/+1); verificationDeadlineCannotBeBypassedByLateSuccess (-1/0/+1); finalCumulativeBudgetChecksResultsWithoutTimerDelivery (-1/0/+1); lateSuccessIsDiagnosticAndCannotReplaceTimeout; existing cancellation result-save race tests | **FIXED** |
| A3: stalled persistence blocks shutdown | Durable mutation lock remained held across indefinitely suspended I/O. Repository writes now have owned handles, acknowledgement continuations and a genuinely concurrent adapter-call boundary. The five-second watchdog can interrupt the *wait*, publish explicitly uncommitted terminal uncertainty and finish bounded shutdown independently of the lock/backend. Underlying writes remain owned; late success/failure is recorded separately and never overwrites emergency status. Healthy storage can persist emergency cleanup; stalled storage cannot be claimed saved. | TaskCoordinator: write, commitOnRepository, interruptWrites, cancellationDeadline, persistEmergency, shutdownDeadline; App/AppComposition.swift: TaskServices.close | shutdownReturnsAtBudgetWithStalledHistoryAndRepeatedCallers (late backend success/failure); stalledAdmissionIsRejectedAndRemainsVisibleAfterBoundedShutdown; realStoreStallCannotBlockBoundedShutdownAndLateReceiptIsHonest; existing storage failure tests | **FIXED** |
| A4: admission succeeds after shutdown | Submission checked admission only before save; shutdown omitted in-flight admissions. Register admissions before suspension, close the gate synchronously at shutdown entry, and require save acknowledgement plus an open gate at admission linearization. Known committed but unacknowledged admissions are cancelled before rejection. Unknown commits remain visible as uncommitted failures and are recovered from actual durable state. | TaskCoordinator: submit, persistAdmission, cancel, beginShutdown, checkShutdown | shutdownAccountsForPendingAdmissionBeforeReturning; cancellationDuringAdmissionNeverDispatchesOrReportsAcceptance; cancelledCallerCannotAcknowledgeAdmissionAfterCommit; admissionFailurePreservesUncertaintyAndNeverAcknowledges (before/after save); duplicate admission test; concurrentAdmissionShutdownStress | **FIXED** |
| A5 / P2: cancelled observers retained | Waiters had no cancellation removal. Tokenized throwing continuations now use cancellation-safe registration/removal and exactly-once completion. A finite nonthrowing actor hop performs cancellation cleanup. | TaskCoordinator: waitForState, cancelWaiter, publish | registeredObserverCancellationRemovesItsContinuation; cancelledObserversTerminateAndReleaseCapturedResources (32 dispose/capture-release cycles) | **FIXED** |

Core source paths above are under `Packages/WesleyFlowCore/`. Tests reside in `Tests/Phase1ATests/CoordinatorTests.swift`, `PersistenceTests.swift` and `TestSupport.swift`.

The final review checked actor reentrancy, acknowledgement/cancellation ordering, exactly-once continuation resumption, generation fences, late writes, uncertain leases, terminal immutability and restart semantics against the audit. There is no external-review/second-agent claim. No P1 repair remains partial or unresolved within this scope.

## Ordering, shutdown and durability contract

Admission succeeds only after its initial state/event transaction acknowledges and the admission gate is still open, without a further productive suspension before acknowledgement. Caller scheduling after that linearization does not create a new admission. Shutdown closes the gate before its first suspension, tracks admissions already entering, and rejects subsequent submissions with `closed`. Pre-start `notStarted` behavior is preserved. Pending transactions are not assumed rolled back simply because acknowledgement is rejected.

The first shutdown request establishes one five-second clock budget; repeated callers join it. Normally, cancellations and known writes settle before shutdown returns. At the budget, pending saves are explicitly uncertain, new persistence dispatch is disabled, active/nonterminal snapshots become uncommitted terminal failures and unsafe ownership is quarantined. `shutdownCompleted` means this bounded reporting protocol has finished; it does **not** mean a stuck backend or provider has been physically killed. `hasPendingPersistence`, task durability/inspection flags and typed late acknowledgement receipts expose that distinction.

The persistence tasks are supervised, actor-owned and non-detached. Their errors are returned to active waiters or retained as typed late failure acknowledgements. A structured task group cannot provide this timeout guarantee because it waits for noncooperative children. `commitOnRepository` uses `@concurrent` so synchronous SwiftData work cannot inherit/block the coordinator's execution context. The real-store stall regression verified this boundary; an asynchronous repository double alone did not expose it.

After an unknown write, the coordinator does not retry or overwrite it blindly. It retains the task/receipt until acknowledgement, or until the process ends. A late database commit may therefore exist even though the in-memory emergency terminal record was never committed. Recovery uses actual durable state: nonterminal records become interrupted, original state is retained, unknown intent requires inspection, and no work or approval is restored. The in-memory emergency snapshot never falsely claims that a different terminal state was durable.

TaskServices.close returns after bounded shutdown and avoids awaiting close on a repository with tracked pending writes. Its owner can explicitly retry close after settlement. The opt-in diagnostic `waitForPersistenceSettlement` can wait indefinitely and is deliberately excluded from shutdown/close. This bounds coordinator-owned write shutdown, not arbitrary direct repository/startup calls or physical destruction of an unavailable SwiftData backend. SwiftData may retain SQLite handles until context/executor teardown; new tests retain their isolated temporary fixtures instead of unlinking live stores.

## Deadline and database compatibility contract

Production elapsed-time enforcement uses SystemTaskClock's monotonic ContinuousClock anchor. Provider completion must be observed strictly before its absolute deadline; watchdog delivery order cannot authorize late success. An on-time result is accepted at that actor-serialized check, so slow later storage does not retroactively turn it into an execution timeout. Storage uncertainty remains separately reported. Cancellation that wins the generation race prevents later promotion.

Persisted executionDeadline is a diagnostic timestamp from the originating clock/session, not a resumable cross-process budget. Restart never restores remaining execution time or approval timers: every nonterminal task is interrupted even if its stored deadline appears expired or future. Late diagnostics contain only operation identity/generation, time and boolean success/revision/digest match facts, with a bounded count; no raw source, argv, output or provider error text was added.

SwiftData schema v1/model identities and migration plan are unchanged. New JSON fields are optional, so old payloads decode without reset or destructive migration. Both missing-field decoding/reopen and an actual store written by the old compiled v1 binary were verified. This does not promise downgrade compatibility or validate future schema upgrades.

## Actual execution evidence

[Evidence/Phase1A-Remediation](/Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1A-Remediation) contains exact argv, environment, UTC timestamps, exits, source/log hashes, raw logs and result bundles. `final-proof.json` confirms all 18 app/core/test/project code files match every final build/test run, original test function names remain present, historical architecture/audit bytes are preserved and there are no external package dependencies.

| Executed check | Actual result | Artifact prefix |
|---|---|---|
| Fresh Debug build | Exit 0 | final-debug |
| Fresh Release build | Exit 0 | final-release |
| Focused remediation suite | Exit 0; 16 functions / 35 cases, including 12 stress cases | final-focused |
| Complete native suite | Exit 0; 63 functions / 258 concrete cases; 0 failed/skipped | final-full; final-full-summary |
| Separate complete test-without-building replay | Exit 0; 63 functions / 258 concrete cases; 0 failed/skipped | final-replay; final-replay-summary |
| Recovery probe compile | Exit 0 | final-recovery-compile |
| Six deliberate crash seeds | Expected and observed exit 77 each | final-recovery-*-seed |
| Fresh recovery and second reopen for each seed | Twelve runs exit 0; 0 executor calls; no restored approval; stable event count on second reopen | final-recovery-*-recover / -reopen |
| Source/dependency/environment/deployment/Git checks | Passed; exact results retained | proof-*; final-proof; staged-review; git-final |

The 12 cohort-based stress cases each release 32 submissions concurrently with shutdown (384 submission attempts per complete run). They allow only acknowledged, closed or bounded-queue-full outcomes, require every visible record to be terminal after shutdown, reject further submissions and assert zero executor calls. Outcomes are printed per case. Full suite and separate replay both execute these cases. Other regression synchronization uses explicit commit holds, clock registration, async notifications and continuation barriers; it does not depend on arbitrary sleeps.

Final lane: explicit `/Applications/Xcode-beta.app/Contents/Developer`, Xcode 27.0 beta 27A5237l, Swift 6.4, SDK 27.0, arm64 host macOS 27.2 / 26B5112a on M4/16 GiB. Swift mode 6, tools 6.2, minimum OS 26.0 and module edges are preserved. `proof-*.json` records actual tool, effective settings and Release binary deployment metadata. No toolchain installation or global selection change occurred.

The recorded build/test commands use this common prefix:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Phase1A-Remediation-Final -disableAutomaticPackageResolution -skipPackageUpdates
```

Each JSON below contains the complete, unabridged command; suffixes were:

- `final-debug.json`: `-configuration Debug -resultBundlePath Evidence/Phase1A-Remediation/final-debug.xcresult build`
- `final-release.json`: corresponding Release configuration and final-release bundle, `build`.
- `final-focused.json`: Debug, final-focused bundle, `-only-testing:Phase1ATests/RemediationTests test`.
- `final-full.json`: Debug, final-full bundle, `test`.
- `final-replay.json`: Debug, final-replay bundle, `test-without-building`.

Recorded bundle arguments are absolute paths. `final-recovery-compile.json` contains the complete Swift compiler/framework/rpath argv; each recovery JSON contains the actual helper executable, mode, isolated store path and expected exit. Runner/probe sources are retained with evidence for reproduction.

### Recovery results

| Seed | Recovered state | Audit events after first / second recovery |
|---|---|---|
| Actual coordinator running with committed intent | failed.interrupted; prior running; unresolved inspection | 6 / 6 |
| Actual cancelled task after resource acknowledgement, unknown disposition | cancelled; unresolved inspection retained | 7 / 7 |
| Previously approved pending request with expired diagnostic deadline | failed.interrupted; prior awaitingApproval; approval removed | 5 / 5 |
| Exit immediately before cancellation save | failed.interrupted; prior running; unresolved inspection | 6 / 6 |
| Exit immediately after save but before acknowledgement | failed.interrupted; prior cancelling; unresolved inspection | 7 / 7 |
| Pre-remediation v1 compiled writer | failed.interrupted; prior running; optional new fields absent | 3 / 3 |

Every recovery rejects any recorded old request against the new broker session and makes zero executor calls. These tests verify named process-exit boundaries, not arbitrary power-loss/storage-hardware behavior.

### Failures retained and resolved during remediation

Baseline probes reproduced all four defects before implementation. `regression-before` exited 65 with six assertion issues across the new cancellation/deadline tests, confirming the tests detect the old behavior. The first expanded run was deliberately interrupted (-15) when a diagnostic event could not be persisted; healthy-store emergency persistence was corrected, and the regression then passed.

`full-attempt1` exited 65 because its older queued-admission test required a failed admission to disappear. That assertion was replaced with stronger checks for a visible failed.storage/uncommitted record plus zero durable submitted events; active-work revocation checks remain. No existing test function was removed.

The real synchronous SwiftData stall initially timed out (`complete-validation`, `persistence-regressions`, exit 65); a checkpoint run was stopped (-15) and a stack sample retained. A too-narrow Swift Testing selector once exited 0 while executing zero tests; it is not counted as verification. A synchronous stream notification fixed fixture signalling, while the production concurrent I/O boundary fixed the remaining coordinator-executor stall. The final real-store regression passes in both the full run and replay.

Earlier checkpoint testing also exposed live temporary SQLite-store unlink diagnostics. New remediation fixtures now remain isolated for diagnosis instead of being removed while SwiftData may retain handles. Final full/replay logs contain no such diagnostics, no SwiftData queue-affinity warning and no Swift concurrency compile failure; xcresult runtimeWarnings is empty. Xcode's nonfatal unused-AppIntents metadata/host linkd diagnostics remain in raw build/test logs. No warnings were suppressed.

## Files changed

Relative to the audited uncommitted Phase1A baseline, production changes are limited to `App/AppComposition.swift`, Domain/TaskServices.swift, TaskExecution/TaskCoordinator.swift and Persistence/SwiftDataTaskRepository.swift. Test changes are CoordinatorTests.swift, PersistenceTests.swift and TestSupport.swift. AGENTS.md records current scoped authorization; README and this report document the repaired contract. `remediation-only.patch` retains the exact baseline-to-repair diff.

The local commit necessarily also records the already-uncommitted Phase1A implementation/project/test/report files, since its parent was the Phase0B commit. Those changes were preserved and reviewed rather than discarded or split into another commit. The original permission broker, original pure Domain test source, app composition tests, approved architecture and historical audit reports remain byte-identical to the remediation baseline. No new dependency or module edge was introduced; build products/raw evidence remain ignored.

## Remaining limitations and readiness

The macOS 26 runtime and full Xcode 26.3/Swift 6.2.3 lane remain unverified, as do release signing/consent, real adapter containment, resource budgets and future migration/artifact matrices. Store quota is projected application admission accounting, not demonstrated hard filesystem enforcement. No production executor or operational task/approval UI is enabled. A genuinely stuck in-process backend/provider remains retained/quarantined until acknowledgement or process exit; bounded reporting cannot kill it or guarantee the eventual write did not commit.

**Phase1A remediation is complete on the verified lane. Phase1B can be considered for separately scoped authorization; it has not begun and is not automatically approved.** Existing compatibility, effect and release gates still apply.

## Git status and local commit

The authorized single local commit is named `fix(core): resolve task lifecycle concurrency defects`. Its full resulting hash and commit exit are recorded in [commit.json](/Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1A-Remediation/commit.json), and final status is in [git-final.txt](/Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1A-Remediation/git-final.txt). These sidecars are generated after the commit: this report is itself included in that commit, so embedding its own final hash would be self-referential. The full hash is also reported in the chat handoff.

All staged paths were reviewed for scope and source-hash identity before committing. No remote was added, no push performed, and no unrelated project/user data was changed. Stop after this remediation.
