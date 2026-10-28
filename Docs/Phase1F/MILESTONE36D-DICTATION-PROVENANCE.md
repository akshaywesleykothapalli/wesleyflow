# Milestone 36D — Recent dictation provenance

28 October 2026. Confirmed lifecycle/diagnostic defects repaired and automated gates passed. **Physical TextEdit replacement: UNVERIFIED.** The exact historical cause of the user's36C “No recent dictation” result is not recoverable from that message alone. This report does not claim that native insertion or live AI replacement now succeeds.

## Findings and cause limits

Production owns one authoritative SystemWideDictationCoordinator: WesleyFlowApp's StateObject is passed to FoundationView, AppDelegate, the pill and shortcut registration. FoundationView's other convenience initializer creates a coordinator but is not the production window path. No disconnected production state owner was found.

The old coordinator collapsed skipped creation conditions into the generic message set by begin(): mode disabled at insertion, non-verified receipt, pending clipboard lease, or missing anchor provider. Additionally, a source-validation failure removed the anchor without preserving its failure as the next lookup explanation. A second shortcut therefore lost the more specific cause. These are confirmed, reproducible reporting/lifecycle defects; they do not prove which condition occurred in TextEdit.

A noncooperative insertion adapter could return after cancellation/close and still reach anchor creation: the old session guard occurred only after receipt publication/history work. A deterministic regression now demonstrates a late verified receipt retained truthfully as history without granting edit authority. Native freshness already rejected use after120 seconds, but the coordinator could retain the AX-backed record indefinitely until another operation. It now actively releases that record at expiry and rejects a result that finishes after expiry.

No evidence was found that normal HUD dismissal, audio stop, speech cleanup or ordinary session teardown cleared a successfully admitted anchor. These paths retain it. General preference updates also retain it when unrelated; a new dictation deliberately invalidates the old target. Model rejection is separate and does not erase a still-valid record. No speculative speech or waveform fix was made.

Inspection found one older executable at the default Xcode DerivedData location (PID98801 at inspection). Its on-disk debug dylib contained36C and no36D marker, SHA256 bfe3744b6ffa96273a5bbf9e61fa6aa76a4ba53ad92200725db78743008cfd8c. This identifies the disk artifact, not proof it was unchanged since launch. Saved inPlaceAIRewrite, offlineAIRewriting, promptEngineeringEnabled and previewShortcutsEnabled were all true. No settings were changed, private document/clipboard/history contents read, or AX-tree attributes enabled. The cached preferences and original receipt inside the running process remain unobserved.

## Complete path and authoritative state

1. The human dictation gesture captures a session-bound original target, then starts existing Apple speech.
2. Final speech becomes deterministic formatted text; that identical text goes to the existing insertion service.
3. The actual typed receipt is observed. History remains an outcome record, never edit authority.
4. Only INSERTED_VERIFIED, no pending clipboard recovery, enabled in-place capture and a valid target provider may create a native anchor. Session, PID and exact UTF-16 inserted text must match.
5. A creation failure retains a specific reason. A successful anchor stays in the same coordinator through teardown and HUD dismissal.
6. Option+1/2 looks up that single record, validates original source/PID/native target/range and120-second monotonic lifetime, then requests the existing provider once.
7. Only valid output with the same still-live anchor and successful native revalidation may attempt one exact-span replacement. Any attempted replacement consumes authority; no automatic retry or history resurrection.

One anchor and bounded diagnostic metadata are retained in RAM. Expiry uses the existing injected TaskClock, overflow-safe arithmetic and a cancellable120-second timer; native ContinuousClock freshness checks remain independently enforced. The timer is correlated to session and creation time. Begin, shutdown, source rejection, foreign target and consumption invalidate it. Normal HUD/audio cleanup and a resource-blocked generation do not. A new process begins with no record. Nothing persists AX handles or replacement authority.

Changes for36D: App/SystemWideDictationCoordinator.swift (lifecycle, expiry, accurate metadata), App/WesleyFlowApp.swift (manual panel build marker only), AppTests/GlobalDictationTests.swift (regressions and updated explicit no-receipt wording), and this report. All pre-existing dirty files were preserved. No package/target/dependency, speech, waveform, insertion broker, clipboard lease, model/provider or4GiB floor changes were made for36D.

## Diagnostics and outcomes

General → Text verification diagnostics now exposes36D/build identity, lifecycle, latest observed insertion status, verifiedReceipt, eligibleReceipt, reason, expiration state, target identity match, verification availability, shortcut kind and model state. notChecked is explicit; a PID comparison alone does not claim native range verification. Native stage diagnostics still describe the exact failing validation. Metadata contains no transcript, clipboard value, document title, source hash or private content. Detailed stage history remains bounded; generation annotations are capped.

Reason codes: NONE, NO_INSERTION_RECEIPT, INSERTION_UNCERTAIN, INSERTION_FAILED, RECEIPT_EXPIRED, TARGET_CHANGED, TARGET_INVALID, SESSION_INVALIDATED, SOURCE_RANGE_UNAVAILABLE, CAPTURE_DISABLED, CLIPBOARD_PENDING, RECEIPT_CONSUMED. Typed failure details further distinguish permission, secure input, composition, range, text mismatch, context and caret changes. Actual typed receipt status distinguishes dispatched/uncertain outcomes from failure, including attempted cancelled/unsupported delivery. Model availability/resource rejection is not an insertion failure.

The pill distinguishes no receipt, uncertain insertion, failure, disabled-at-capture, expiry and exact native rejection. Repeated shortcuts retain the original source failure instead of reverting to “No recent dictation.” No failure opens a preview. Only explicit Settings actions retain the existing manual preview.

## Automated evidence

Toolchain: /Applications/Xcode-beta.app/Contents/Developer, Xcode27 / Swift6.4 / SDK27; macOS26 arm64 deployment target. Actual tests ran on MacBook Air arm64, macOS27.2 (26B5112a). This is not a macOS26 runtime acceptance claim.

| Check | Actual result | Exit |
|---|---|---|
| focused | 237 expanded / 116 declarations; 0 failed, 0 skipped | 0 |
| full | 1189 expanded / 541 declarations; 0 failed, 0 skipped | 0 |
| replay | 1189 expanded / 541 declarations; 0 failed, 0 skipped | 0 |
| Debug build | passed after final test addition | 0 |
| Release build | passed; application source identical to final regressions | 0 |
| Release strict concurrency | SWIFT_STRICT_CONCURRENCY=complete passed | 0 |
| Development bundle signature | codesign --verify --strict passed | 0 |
| Repository checks |278 tracked files /581 history objects; no issues | 0 |
| Git whitespace | passed | 0 |

36C baseline1171 cases /532 declarations is retained.18 cases /9 declarations were added. New coverage: verified receipt vs safe range distinction, creation failure, uncertain/failed/cancelled and disabled-at-insertion outcomes, teardown/HUD/unrelated preferences, both shortcuts, repeated failure classification, restart with no history authority, clock-controlled119999/120000/120001ms expiry, passive expiry during held generation, noncooperative late insertion after cancellation, and three successive dictations sharing the single authoritative latest record. Existing typed invalid-element/foreign-editor/user-edit/no-popup/no-submission/clipboard/repeated-pipeline tests remained enabled. Fixture tests do not establish physical AX support.

Final test command/exit/timestamp records, logs, xcresults and extracted summaries: Evidence/Milestone36D/FinalRegression/{focused,full,replay,debug}. Release/concurrency: Evidence/Milestone36D/FinalGate/{release,concurrency}.json and .log. Final source and executable/debug-dylib hashes: FinalRegression/build-and-source-hashes.json. All Xcode work was sequential, no parallel jobs sharing a build database.

Common argv uses xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone36D-Verified -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2. Tests append -configuration Debug -parallel-testing-enabled NO -resultBundlePath <unique evidence path> test. Focused suite selectors are recorded in JSON; full/replay exclude nothing. Build commands append Debug/Release build, with strict concurrency on the latter check. Repository check: python3 Tools/CI/repository_checks.py. Signature: codesign --verify --strict <exact Debug bundle>. Whitespace: git diff --check.

Initial Acceptance/focused exited65: an old assertion expected the generic missing-dictation message, and the new fixture mistakenly classified an attempted failed write as definitely failed. The assertion now checks the accurate no-receipt message; uncertainty uses receipt.status, preserving attempted delivery uncertainty. Initial logs remain. Intermediate focused runs in Final, AcceptanceFinal, Verified and FinalGate passed. No tests were removed, weakened or skipped. FinalRegression includes the additional successive-dictation case. Existing linkd.autoShortcut service and AppIntents metadata warnings remain nonblocking and are not physical shortcut evidence.

## Physical acceptance and safe build handoff

The user answered “I’ll test after verification finishes.” No36D physical outcome was supplied. TextEdit dictation classification, Option+2 delivery, real generation, actual replacement, native focus/clipboard behavior and edited-source rejection remain UNVERIFIED. No live inference or repeated resource probe was performed.

Exact test app: DerivedData/Milestone36D-Verified/Build/Products/Debug/Wesley Flow.app. General/Smart Formatting route description identifies36D; binary hashes are recorded. The old running app was not quit, replaced or force-terminated: its active dictation/clipboard lease state is not established. No second interactive instance was opened and no global keyboard events injected.

1. Quit older copies normally only with dictation and clipboard recovery idle; stop on a warning. Open only the exact36D app.
2. Before testing, confirm36D route description and explicitly enable in-place mode, desired AI feature and preview shortcuts if needed. Saved settings were already true at inspection; they were not changed by this task.
3. In a blank TextEdit plain-text document, dictate a fresh synthetic sentence using the actual dictation shortcut. Confirm it appears. Immediately press Option+2 within120 seconds, leaving field/caret untouched. Do not open General in between: an application switch intentionally invalidates native source focus.
4. After the attempt, inspect only General's metadata/status: outcome=INSERTED_VERIFIED establishes insertion verification; eligibleReceipt, reason, native phase and model state distinguish creation rejection, expiry, target/range checks and generation. Report metadata and whether visible text was physically replaced; do not report private text/clipboard contents.
5. If resource admission rejects, stop without retrying. For Option+1 or edited-source rejection, use a separate fresh dictation. Never submit/press Enter. Check the clipboard privately.

Expected successful progression is verified receipt → eligible anchor → original target validation → model request → output validation → exact replacement verification. Only a physically observed editor replacement can pass that last live gate. Native missing subrole, IME/marked-text state, readable/settable ranges or safe editor identity still reject. Terminal stays manual-copy; Codex direct AX replacement remains unsupported by existing policy. AX is not atomic compare-and-swap; dispatched uncertainty never becomes success or retry. Model availability/quality and unchanged4GiB admission remain limitations.

## Git and stop status

Branch feature/milestone-31-integration; HEAD23caeca630b803fddc2cd007a5159dc9839b71cf unchanged. No staging, commit, push, rebase, merge, remote mutation or PR-state change. Main untouched; PR#1 was left as-is (draft), not remotely re-queried in this local repair. Existing uncommitted36–36C and earlier work remains. Before this additional report, git status was:

```text
 M App/AppComposition.swift
 M App/ClickableDictationPill.swift
 M App/DictationPreferences.swift
 M App/GlobalDictationView.swift
 M App/SystemWideDictationCoordinator.swift
 M App/WesleyFlowApp.swift
 M AppTests/DictationTests.swift
 M AppTests/GlobalDictationTests.swift
 M Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift
 M Packages/WesleyFlowCore/Sources/Domain/PromptEngineering.swift
 M Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
 M Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
 M Packages/WesleyFlowCore/Sources/VoiceInput/AppleDictationInput.swift
 M Packages/WesleyFlowCore/Sources/VoiceInput/NativeSpeechCallbacks.swift
 M Packages/WesleyFlowCore/Tests/Phase1ATests/CoordinatorTests.swift
 M WesleyFlow.xcodeproj/project.pbxproj
?? Docs/Engineering/MILESTONE32-HOSTED-CI.md
?? Docs/Engineering/MILESTONE33-ACCEPTANCE.md
?? Docs/Phase1F/CONTEXT-AWARE-TEXT-CAPTURE.md
?? Docs/Phase1F/GLOBAL-SHORTCUT-DELIVERY-FIX.md
?? Docs/Phase1F/MILESTONE35A-CAPTURE-REPAIR.md
?? Docs/Phase1F/MILESTONE36-SEAMLESS-DICTATION.md
?? Docs/Phase1F/MILESTONE36A-INPLACE-ROUTING.md
?? Docs/Phase1F/MILESTONE36B-WINDOWLESS-AI.md
?? Docs/Phase1F/MILESTONE36C-TEXT-VERIFICATION.md
?? Packages/WesleyFlowCore/Sources/Domain/DictationEnhancements.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationVerification.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/DictationSpanVerification.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/FocusedTextResolver.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AudioLevelMailbox.swift
?? Packages/WesleyFlowCore/Tests/WorkspaceTests/FocusedTextResolverTests.swift
```

This report is additionally untracked. Final automation PASSED; original physical failure diagnosis and actual in-place acceptance remain PENDING user reproduction. Stop after36D; no later milestone started.
