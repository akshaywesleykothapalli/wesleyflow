# Phase1C repeated-insertion remediation — 21 October 2026

Result: confirmed stale-clipboard blocker corrected, safe clipboard recovery and verified-build installation completed. Real repeated ChatGPT insertion remains UNVERIFIED pending the requested human test. Simulated success is not a claim that native ChatGPT observations/delivery are reliable. Do not label the overall real-app objective complete yet.

## 1. Current identities and baseline audit

Read actual AGENTS.md, CURRENT_STATE.md, GLOBAL-VOICE-PARITY-REVIEW.md, working tree/diffs and current insertion/coordinator/target/HUD/hotkey/clipboard code and tests. main/HEAD remains 0a3e91c731a716945853a6b84bcfaaf6d9e672d3. 45 files were already outstanding on entry; baseline hashes/status/before-files preserve that work. The pending backup was in the older RUNNING app, not the BUILT parity app. All showed version 0.1.0 build 1, so path and hashes are essential identifiers, not the version label alone.

| Identity | Path | Evidence |
| --- | --- | --- |
| Initially running | Run/Wesley Flow.app | PID 29932; initial executable SHA256 d104dd5613397c71e62e6a82b242deeb78da5c8915fccad215582be2b93cca27; debug dylib 1257fdf80d46b04c6de8ba112a86bc0d9527b77fdb8bad5b864926536de5d906. |
| Previously verified, not installed | DerivedData/GlobalVoiceParity/Build/Products/Debug/Wesley Flow.app | Different executable d7d89c3b141e8dee085deaeb8818878d62d7ca3f5ee339e3a4db8c3e19eabecb;824-case baseline evidence applied to this source. |
| This milestone's verified build | DerivedData/RepeatedInsertionRemediation/Build/Products/Debug/Wesley Flow.app | All accepted verification records match the installed source and bundle hashes. |
| Now installed and running | $REPO_ROOT/Run/Wesley Flow.app | PID 76065, 0.1.0 (1), local.wesleyflow.WesleyFlow; executable SHA256 e641af96cc3c75d0cd6b1e357e68b4d51ca35b31a32a97eaf0641cbbf08690d1; debug dylib ad4495a5756358865fbff6879fb12fdedb863154cf47a3156df00b8d9e9c5bd0. |
| Rollback preserved | $REPO_ROOT/Run/.before-repeated-insertion-remediation-20261021 | File-for-file identical to the original canonical bundle. |

Complete hashes and metadata: initial-identities.json, prepared.json, promotion.json and launched.json under Evidence/RepeatedInsertionRemediation. No claim that the initial binary contained the newer source.

## 2. Clipboard recovery — REAL GUI / READ-ONLY METADATA EVIDENCE

The original app displayed Idle, a retained backup banner and Review clipboard restoration. This proves an idle coordinator retaining recovery state; it does not expose a native event-queue acknowledgement. A metadata-only helper reported changeCount 93, one nonempty item with one representation, no Wesley ownership marker and stable revision. It read no clipboard payload, string, token or private conversation text and made no writes. Public pasteboard metadata does not identify an owner PID; the retained recovery belonged to the inspected Wesley Flow PID 29932, while that lease no longer owned the current pasteboard.

The running binary's supported restore path checks ownership before writing. With a nonempty marker-free newer clipboard, its guarded recovery returned “Your newer clipboard was preserved.” The backup banner disappeared. Metadata remained exactly changeCount 93 / one item / one representation / no marker afterward. This was successful retirement of an obsolete backup, NOT restoration of the old snapshot. No older data was pasted back and no clipboard write was observed. The old paste's actual delivery was not inferred from the elapsed time. No force quit, restart or replacement occurred before recovery completed.

Afterward the old Fn monitor was explicitly disabled through its own Settings. The UI was idle with no backup banner before normal Quit. No orphaned insertion session or active lease was visible after recovery; native queued-event completion itself is not publicly observable through this interface. Facts and limits are recorded in recovery.json and handoff.json.

## 3. Reproduced failure and verified root cause

Affected target identified by the user: ChatGPT macOS-branded app. Earlier static installed metadata identified /Applications/ChatGPT.app as com.openai.codex. Browser ChatGPT is a separate UNVERIFIED target. No ChatGPT/Codex UI was automated or bypassed via AX scripts; only Wesley Flow's own status/metadata was inspected. No private conversation contents entered diagnostics.

CONFIRMED root cause: an unacknowledged paste retained a pending clipboard backup. Both the coordinator pre-recording gate and service paste gate treated any retained backup as a continuing blocker, even when an external clipboard write had already superseded its lease. This caused indefinite refusal of otherwise fresh sessions until manual recovery. It matches the real app's retained backup with a current nonempty marker-free clipboard. It does NOT prove why the initial native ChatGPT paste failed text observation.

Failing regression: externallyReplacedClipboardMustNotBlockAFreshDictation creates an unacknowledged dispatch, performs a simulated external clipboard copy, then attempts a new validated session. The unchanged implementation denied it and retained the obsolete state. reproduced-stale-lease-suite exited65 with that test failing four assertions. A prior method-filtered command exited0 but selected ZERO tests; it is explicitly invalid as verification and was not used as proof. The containing suite was run to reproduce the actual failure, then passed after the fix.

Responsible locations: SystemOperations/TextInsertionService.swift pending state / insertion gate and App/SystemWideDictationCoordinator.swift begin gate. NativeDictationPasteboard supplies revision/token evidence. No reproduction establishes pill focus theft, duplicate native dispatch, AX rerender details or an application-specific timing requirement as the initial ChatGPT cause. No special delay or new ChatGPT-only pipeline was introduced.

## 4. Exact source corrections

- Add a positive isSuperseded ownership check based on native pasteboard changeCount, including the existing empty-lease revision after failed publication/restoration. Default implementations fail closed. A failed marker read at the same revision is UNKNOWN, not evidence of a newer copy.
- TextInsertionService.reconcileClipboardState retires only an idle, positively superseded pending lease. It does not restore, clear, overwrite or republish the pasteboard, retry the old transcript or change its saved uncertain outcome. It runs before a fresh insertion; coordinator calls it before recording, on permission refresh and before normal termination checks. A new physical gesture remains a separate, freshly captured session.
- Preserve pending state and explicit recovery when the app still owns the clipboard or ownership is uncertain. Cancellation/in-flight work cannot be reconciled or restored by another session.
- Bind every retained backup to ClipboardRecovery(id, session, dispatched). The ID is correlation metadata, not authorization. Recovery APIs now require the expected ID. The UI captures it when opening the dialog and freezes it into that confirmation callback; obsolete confirmations cannot restore a later session's clipboard. Existing call sites/tests were updated to pass a bound ID; assertions were retained.
- Native restoration returns unavailable when ownership cannot be established but no new revision is known, retaining the backup rather than falsely declaring newer data preserved.
- Add computed TextInsertionStatus values INSERTED_VERIFIED, DISPATCHED_UNVERIFIED, TARGET_CHANGED, UNSUPPORTED_TARGET, PERMISSION_DENIED, CANCELLED, FAILED and UNCERTAIN. Only observed verified receipts map to INSERTED_VERIFIED. Posted-but-unobserved input stays unverified. Existing persisted enum payloads remain unchanged; old history loads without a schema migration. UI history/details use the explicit status labels.

Single-owner MainActor serialization, original PID/launch/window/field/caret checks, secure rejection, bounded data, no automatic retry and exact expected-text observation are preserved. Fresh sessions capture fresh targets; invalid old nodes are rejected rather than rebound to a random foreground field. The legacy ChatGPT initial-paste selection is preserved, not extended or newly validated. Terminal remains manual-copy only; declined accessibility-tree activation remains disabled.

## 5. SIMULATED TESTS — repeated sessions and failure boundaries

| Scenario | Actual automated result |
| --- | --- |
|3 consecutive paste sessions in the same logical field | Pass: fresh session captures, exact cumulative text, one dispatch/session, clipboard restored after each. |
|10 consecutive paste sessions | Same assertions pass; no duplicates or stale replay. |
| Old AX node invalidated / next capture after rerender | Old fixture target rejected; fresh session succeeds. This is not a native ChatGPT rerender test or automatic rebinding within an uncertain session. |
| Stale confirmation from sessionA while sessionB has a backup | Rejected with unavailable; sessionB recovery identity and clipboard unchanged; current confirmation restores correctly. |
| Unreadable ownership with unchanged revision | Backup retained, no automatic retirement/restoration. |
| Overlapping insertion / cancellation during paste | Second effect blocked; cancellation remains uncertain with the correct session's backup. |
| External copy after unverified paste | Fresh insertion allowed without retrying old text; new copy preserved and obsolete lease retired. |
| Coordinator after external copy | Recording unblocked only for a fresh gesture; old transcript not retried. |
| Three recordings with old transcript/finish callbacks | Old callbacks ignored; one current-target write per recording. |
| Focus/target lost after transcription | No redirection or write; TARGET_CHANGED with transcript retained. |
| Status/wire round trip | Explicit statuses map correctly; legacy history encoding remains readable. |

Existing tests remain for UTF-16 caret/selection replacement, changed process/focus, secure inputs, rapid/short presses, pill nonactivation/84x32 dimensions, generation fencing, permission loss, late callbacks, final-only insertion, rich/multi-item/image/URL/empty clipboard representations, concurrent external copies and failed restoration. Native paste-event construction still asserts exactly Cmd+V down/up, no Return or submission key. No new test posts keyboard events, starts recording or executes a real voice command/AI agent.

## 6. Test/build verification

- focused: 217 expanded cases / 148 functions; failed0, skipped0; exit0.
- full: 841 expanded cases / 375 functions; failed0, skipped0; exit0.
- replay: 841 expanded cases / 375 functions; failed0, skipped0; exit0.
- Debug, Release and optimized Release test compilation: exit0.
- Swift6 concurrency/type checking passed; no Swift compiler warnings/errors in accepted logs. Routine AppIntents metadata-skip and test-host linkd connection messages remain.
- Exact accepted source SHA256 maps matched all six checks and the source reviewed for installation. Package graph/dependencies unchanged. 20 tracked pre-existing test files match HEAD; all baseline assertions remain after binding recovery-call arguments. No test deleted or weakened. git diff --check passed; staging empty.
- Toolchain: explicit /Applications/Xcode-beta.app/Contents/Developer, Swift6.4, SDK27.0, arm64 deployment26. Actual macOS26/Swift6.2.3 runtime compatibility remains unverified.

Commands, timestamps, source hashes, exits and logs: Evidence/RepeatedInsertionRemediation/accepted-*.json/log/xcresult. Counts/diff/baseline/assertion/dependency review are in counts.json, review.diff and review.json. Earlier zero-selection/failing/provisional runs are preserved and distinguished from accepted verification.

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/RepeatedInsertionRemediation -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/RepeatedInsertionRemediation/accepted-focused.xcresult test -only-testing:WesleyFlowAppTests
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/RepeatedInsertionRemediation -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/RepeatedInsertionRemediation/accepted-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/RepeatedInsertionRemediation -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/RepeatedInsertionRemediation/accepted-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/RepeatedInsertionRemediation -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/RepeatedInsertionRemediation/accepted-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/RepeatedInsertionRemediation -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/RepeatedInsertionRemediation/accepted-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/RepeatedInsertionRemediation-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/RepeatedInsertionRemediation/accepted-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```

All commands set DEVELOPER_DIR explicitly and remove SDKROOT. Simulated3/10 repetition is in the actual focused/full/replay suite; no physical compatibility claim follows from it.

## 7. REAL GUI TESTS / UNVERIFIED BEHAVIOR

Actual GUI checks: the running old app's idle/recovery state; supported obsolete-backup recovery; Fn-monitor pause; normal Quit; new canonical app launch, retained history/sidebar and new Settings. Actual metadata checks: unchanged clipboard revision during recovery, process identities, complete source/bundle hashes and deep/strict code-signature verification. These are real app handoff checks, not real speech-to-ChatGPT tests.

| Application/editor | Repeated speech insertion on this exact build | Other evidence |
| --- | --- | --- |
| TextEdit | UNVERIFIED | No physical microphone/insertion test performed. |
| ChatGPT macOS prompt | UNVERIFIED | Prior intermittent first delivery and repeat failures. User asked for three separate harmless Fn tests on the newly installed build; no new success claim. |
| ChatGPT browser prompt | UNVERIFIED | Browser editing may differ; no private page inspected. |
| Codex Desktop prompt | UNVERIFIED | Direct tool automation is prohibited; no alternate AX/script bypass used. |
| VS Code editor | UNVERIFIED | No physical test; integrated terminal is distinct. |
| WhatsApp / native controls | UNVERIFIED on this build | Historical user successes are not revalidated by mocks. |

Requested manual sequence: First insertion test / Second insertion test / Third insertion test, separately released Fn gestures, no sending. Each attempt's capture validity, dispatch, visible text, duplicates/missing text, clipboard lease and focus/submission outcome remains UNVERIFIED until reported/observed. Fresh-focus, selected-text and app-switch variants remain unverified. No raw user prompt/clipboard text is requested for evidence.

## 8. Safe deployment and clipboard restoration evidence

Recovery completed before installation. Old Fn monitoring was disabled, and Idle with no pending banner was observed before Quit. Native UI inspection after the first normal Quit unexpectedly reopened the old build as PID 75763; this was disclosed, occurred after safe recovery, and no backup was lost. It was quit normally again. Process-list-only verification then confirmed no canonical process remained. No signal/kill/force termination was used. Do not call window inspection on a quit binding as a process-exit check.

The verified app was first copied to a unique staging directory, signature-checked and compared file-for-file with accepted Debug output. Only after normal shutdown was the old canonical bundle renamed for rollback and the staging bundle installed. Own stale generated-app launch registrations were removed; canonical registered last. Existing bundles/data were preserved. Full argv/exits, hashes and handoff checks: prepared.json, handoff.json, promotion-*-actions.json, promotion.json and launched.json.

The launched PID/path and complete bundle hashes match the accepted build. Version labels remain0.1.0(1), so hashes distinguish it from earlier builds. The previous GLOBAL-VOICE-PARITY report's not-installed state is historical. Native Settings now displays configurable Fn/Right Option/Right Command, the prior formatting controls, AI disabled and Enable hold-to-talk. Accessibility/microphone/speech consent must be reviewed by the user for this changed ad-hoc binary; no grants, TCC edits, new certificate or permission bypass were automated. The app is left on Settings, not recording, with no pending backup at launch.

## 9. Remaining limitations / acceptance decision

The confirmed post-external-copy blocker is fixed. If a new native paste remains unobservable AND still owns the clipboard, the app intentionally retains its backup and requires explicit recovery; this change does not bypass that safeguard merely to make repeated attempts proceed. Failure of the original ChatGPT text observation is not yet reproduced through accessible native target diagnostics. Real repeated ChatGPT success remains a blocking live acceptance gate, not an inferred consequence of fixture results.

A rerender that invalidates a target within an uncertain session is not automatically rebound. Public native event posting has no reliable delivery acknowledgement here. Synchronous AX calls and cross-process clipboard operations are not atomic transactions; revision/token fences and typed uncertainty remain, without a universal race-free guarantee. Backups are in RAM; normal Quit is guarded, but crashes/force-quits can lose them. No elapsed-time rule was substituted for ownership or text evidence.

All earlier unrelated/uncommitted work, formatting, hotkeys, optional nonactivating pill, local history and Apple on-device speech are preserved. No unrelated redesign, OpenCode, Ollama inference, AI modification, live voice command, cloud transcription, model download, prompt submission, commit, push or remote creation occurred. Stop at this milestone; do not claim a live reliability sign-off until the manual matrix passes.

## 10. Files changed and working tree

This milestone's source/instruction changes relative to its preserved baseline:

- App/GlobalDictationView.swift
- App/SystemWideDictationCoordinator.swift
- AppTests/GlobalDictationTests.swift
- Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
- Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
- Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
- AGENTS.md

Plus this report and short historical forward-pointers in CURRENT_STATE.md and GLOBAL-VOICE-PARITY-REVIEW.md. No package dependency, task/history schema or Xcode project file changed during this remediation. Complete working tree includes previous uncommitted work; nothing is staged. Exact final status follows.

```text
 M .gitignore
 M AGENTS.md
 M App/AppComposition.swift
 M App/FoundationView.swift
 M App/WesleyFlowApp.swift
 M Docs/Phase1B/MODEL-PROVIDER.md
 M Docs/Phase1B/SECURITY-BOUNDARIES.md
 M Packages/WesleyFlowCore/Package.swift
 M Packages/WesleyFlowCore/Tools/OllamaEvaluation/EvaluationMain.swift
 M WesleyFlow.xcodeproj/project.pbxproj
?? App/ClickableDictationPill.swift
?? App/DictationModel.swift
?? App/DictationPreferences.swift
?? App/GlobalDictationView.swift
?? App/SystemWideDictationCoordinator.swift
?? AppTests/DictationTests.swift
?? AppTests/GlobalDictationTests.swift
?? Docs/Phase1C/ACCESSIBILITY-ACTIVATION-PROPOSAL.md
?? Docs/Phase1C/CURRENT_STATE.md
?? Docs/Phase1C/GLOBAL-VOICE-PARITY-REVIEW.md
?? Docs/Phase1C/PHASE1C1-COMPLETION.md
?? Docs/Phase1C/PHASE1C2-CHATGPT-PASTE.md
?? Docs/Phase1C/PHASE1C2-CLIPBOARD-REPAIR.md
?? Docs/Phase1C/PHASE1C2-COMMANDS-AND-COMPATIBILITY.md
?? Docs/Phase1C/PHASE1C2-EDITOR-CAPABILITY.md
?? Docs/Phase1C/PHASE1C2-FN-REFINEMENT.md
?? Docs/Phase1C/PHASE1C2-GLOBAL-DICTATION.md
?? Docs/Phase1C/PHASE1C2-REPEATED-INSERTION.md
?? Docs/Phase1C/PHASE1C2-WHATSAPP-TEXT-COMPATIBILITY.md
?? Docs/Phase1C/REPEATED-INSERTION-REMEDIATION.md
?? Docs/Phase1C/TERMINAL-DRAFT-TYPING-PROPOSAL.md
?? Packages/WesleyFlowCore/Sources/Domain/AppOpeningCommand.swift
?? Packages/WesleyFlowCore/Sources/Domain/Dictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/LocalPromptRewriter.swift
?? Packages/WesleyFlowCore/Sources/Persistence/SwiftDataDictationHistoryStore.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeAppOpening.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AppleDictationInput.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AppleSpeechConfiguration.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/NativeSpeechCallbacks.swift
```
