# Milestone 37 — Core dictation reliability

> Acceptance update, 28 October 2026: the user confirms 3/3 physical ChatGPT dictations passed on 37R2. Earlier failure/pending statements below describe the historical investigation. Other editors, clipboard/focus edge cases and AI replacement are not thereby physically verified. Automatic replacement in the affected editors remains unsupported. See [publication review](MILESTONE37-PUBLICATION-REVIEW.md).

Date: 2026-10-28. **MILESTONE INCOMPLETE — ChatGPT physical dictation failure reported.**

Implementation and automated verification passed. The user agreed to perform physical tests; no Milestone37 physical results have been supplied. ChatGPT's actual current failing native stage and the difference from WhatsApp remain **UNDETERMINED**. Neither fixtures nor event dispatch establish native delivery.

## Investigation and evidence limits

Inspected AGENTS.md, prior voice/reliability reports, current uncommitted source, history, tests and running executable. Starting branch: `feature/milestone-31-integration`; HEAD: `23caeca630b803fddc2cd007a5159dc9839b71cf`. Existing cumulative work was preserved.

The available Git history aggregates the older insertion implementation into baseline b90976c; it does not identify the specific previously physically working ChatGPT build. Both baseline b90976c and published HEAD require complete original text and caret before ordinary target acquisition. History snapshots are saved locally in Evidence/Milestone37/native-history-*.swift.txt. The working tree contains many subsequent uncommitted milestones; a source diff alone cannot attribute the reported live regression to one commit.

Confirmed architectural restriction: ordinary paste was coupled to exact original-text/range capture, although an editor can expose editable identity without readable full text/range. This is repaired below. It is **not proof that this restriction caused the user's particular ChatGPT failure**. No current user diagnostic trace was available. Native editor attribute failures, current permissions, focus transitions and actual paste acceptance still require physical observation.

The installed ChatGPT application's bundle identity is `com.openai.codex`. Existing direct-AX-replacement exclusion for that identity predates this repair and remains intact. It is not evidence that direct writing caused the regression. An independent helper's AX authorization result does not establish the running app's authorization.

## Changes and delivery architecture

One existing production SystemWideDictationCoordinator remains authoritative:

Fn gesture → bind original app/window/element/session → audio/transcription → existing deterministic formatting → revalidate target/focus → one insertion dispatch → assess independent readback → guarded clipboard recovery → existing history/Insights outcomes.

1. Domain InsertionTarget.original is optional. Nil means unavailable exact text/caret, never an invented empty field. Target metadata now carries bundle identity.
2. Native target acquisition can retain an identity-only ordinary-paste target when a supported enabled, nonsecure, nonconsole element affirmatively exposes editability or writable text. A selectable read-only conversation is insufficient. Explicit AX denial or invalid-element results stop acquisition. Where original selection is observable it remains bound and is rechecked.
3. Original application launch/PID, bundle metadata, window/element identity, minimized state and focus epoch are checked. An observed away/back app activation invalidates the target. No automatic application activation is added. Native editor behavior across fullscreen, sleep/wake and multiple displays remains physically unverified.
4. TextInsertionService creates exact expectations only with actual original context. With no such context it uses the existing one-shot PID-bound paste path, never direct AX rewriting or unverifiable Unicode typing. After dispatch it records dispatched-unverified, preserves recovery state and does not retry. Readable targets retain exact UTF-16 validation and existing bounded read-only settling.
5. AI replacement still requires independent exact context and verified receipts/anchors. An opaque paste creates no AI authority. Its uncertain history outcome is not upgraded by human clipboard confirmation.
6. Cancellation after an awaited pre-dispatch clock now restores the owned backup before returning without any event. Cancellation cannot continue past that suspension into paste.
7. Native pasteboard ownership now verifies the app's own bounded published payload, marker/types and ownership revision. Same-revision mutation is treated as supersession when positively observable. Unknown unreadable state retains recovery, rather than proving ownership or consumption. Failed post-publication ownership checking preserves recovery identity through ClipboardPublicationFailure.
8. Added explicit lease-aware Copy latest dictation recovery. It remains disabled while a pending backup prevents safe copy. No automatic copy, new preview popup, typing icon or unrelated UI redesign.
9. General diagnostics expose CAPTURE_RESULT, TRANSCRIPTION_RESULT, TARGET_CAPTURE_RESULT, TARGET_VALIDATION_RESULT, PASTEBOARD_LEASE_RESULT, INSERTION_DISPATCH_RESULT, DESTINATION_READBACK_RESULT, INSERTION_OUTCOME and existing replacement capability. Existing operation/build/stage/timing metadata remains; sanitized bundle identity was added. No transcripts, clipboard contents, raw editor text or text hashes enter diagnostics. Audio start acknowledgement is not proof of microphone quality.

Milestone37 source changes are limited to:

- App/SystemWideDictationCoordinator.swift
- App/GlobalDictationView.swift
- App/WesleyFlowApp.swift (37 build marker)
- AppTests/GlobalDictationTests.swift
- Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
- Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
- Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
- Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift (optional-context adaptation for the existing strict AX-only adapter; no hotkey redesign)

## Clipboard findings and remaining limit

Apple documents changeCount as an ownership-change counter, not a destination paste acknowledgement ([NSPasteboard.changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount)). Posting a CGEvent does not provide destination acceptance ([CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)). No elapsed-time or ownership heuristic was promoted to proof of consumption.

A regression test uses an isolated uniquely named real NSPasteboard, never the general clipboard: setString can alter the published payload while changeCount remains unchanged. The repaired guard detects that and preserves the newer synthetic contents. A second isolated native-board test covers mutation during publication before dispatch. Test values remain synthetic.

**Production limitation:** an editor may visibly accept paste while offering no independent readback. Its outcome remains uncertain and its previous clipboard backup is retained. A subsequent dictation is blocked until explicit user-confirmed restoration or positively observed clipboard supersession. This can impede seamless repeated use. It is intentional under current safety requirements, and is not presented as production-grade repeated-insertion acceptance. There is no fixed-delay restoration, blind retry or automatic lease bypass. Pending backup recovery across forced termination remains a limitation; do not kill or replace an app holding a backup.

## Automated verification

Host: Apple Silicon MacBook Air, macOS27.2 (26B5112a). Explicit Xcode beta27.0 / Swift6.4 / macOS27 SDK, macOS26 deployment. These results do not establish execution on macOS26 or other hardware.

| Gate | Actual result | Exit |
| --- | --- | --- |
| Focused voice/insertion/AI-isolation regressions | 381 expanded cases; 202 declarations, 0 failures/skips | 0 |
| Complete application suite | 1,250 expanded cases; 573 declarations, 0 failures/skips | 0 |
| Independent full replay | 1,250 expanded cases; 573 declarations, 0 failures/skips | 0 |
| Debug build | Passed | 0 |
| Release build | Passed | 0 |
| Release strict-concurrency build | Passed with SWIFT_STRICT_CONCURRENCY=complete | 0 |
| Offline Model Lab regressions | 152 tests | 0 |
| Native resource-guard regressions | 7 tests | 0 |
| Repository/license/artifact/secret/workflow check | Passed; 278 tracked files, 581 history objects, no reported issue categories | 0 |
| Git diff whitespace check | Passed | 0 |

Prior36F evidence reported1,237 cases /563 declarations. Thirteen expanded cases in ten declarations were added; existing tests were retained. New coverage includes paste accepted/rejected without readback, no direct-write fallback, denied/secure/changed targets, no unsafe typing when clipboard unsupported, no fake AI authority, history/diagnostics, user supersession, same-revision native-board mutation, cancellation at the pre-dispatch suspension, and publication mismatch. Existing full-suite repeated-session, target, cancellation, Unicode/multiline, waveform, receipt, formatting and recovery tests ran unchanged apart from necessary optional-context fixture adaptation. Fixture acceptance never substitutes for physical editor results.

Evidence: Evidence/Milestone37/ReleaseCandidate/{focused,full,replay}.xcresult and *-summary.json. JSON command records and logs are adjacent. Expanded counts come from devicesAndConfigurations[].passedTests; top-level counts are declarations. Earlier intermediate passing runs remain in Acceptance, Final and Verified. The final AX-denial guard was then tested again through ReleaseCandidate focused/full/replay and all builds. All final commands are recorded below; no generated-code-only success claim.

## Preserved features and boundaries

Compared SHA-256 against the task-start snapshot: ClickableDictationPill, AppleDictationInput, NativeSpeechCallbacks, AudioLevelMailbox, Package.swift, OfflineRewrite and PromptEngineering Domain contracts, and every ModelProviders Swift file remain byte-identical. Thus this task changed neither waveform design, audio callback implementation, prompts/providers, dependencies nor provider resource policy. Existing 4GiB floor, opt-in AI routing and generation guards remain. Model Lab datasets/models/training were not modified or loaded; no inference, downloads or training ran. No OpenCode execution, Return/Enter, Command+A, synthetic microphone input, automatic submission or accessibility-tree activation was added. Terminal remains manual-copy only.

Source hash evidence: Evidence/Milestone37/baseline-hashes.json and final-source-hashes.json. These are source/build hashes, never user-text hashes. Repository scanning covers tracked files/history; it is not proof that all untracked cumulative material is publication-safe. Nothing was staged or uploaded.

## Physical acceptance matrix

All results below concern the Milestone37 build, not historical anecdotes. User willingness is recorded; actual results are pending.

| Application/context | Three fresh dictations | Readback / exact replacement | Duplicate/submission/focus/clipboard |
| --- | --- | --- | --- |
| ChatGPT macOS composer | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| WhatsApp macOS draft | UNVERIFIED (user reported working before37) | UNVERIFIED | UNVERIFIED |
| TextEdit plain text | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| Codex Desktop composer | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| VS Code editor | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| Apple Notes | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| Safari input / textarea / contenteditable | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| Chrome input / textarea / contenteditable | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| Word / Pages / Slack, if available | UNVERIFIED | UNVERIFIED | UNVERIFIED |

Cross-app sequences ChatGPT→WhatsApp→ChatGPT, TextEdit→VSCode→TextEdit, ChatGPT→Codex→ChatGPT: UNVERIFIED. Native short/long utterances, punctuation, cancellation, focus-loss, secure-field exclusion, sleep/wake, multiple windows/displays and fullscreen: not physically tested this milestone. Deterministic coverage does not prove those device interactions.

## Test build, reproduction and recovery

Verified test bundle:
`/Users/akshaywesley/Developer/WesleyFlow/DerivedData/Milestone37-Verified/Build/Products/Debug/Wesley Flow.app`

General diagnostics build marker:37. Code fingerprints below bind the actual built files; the marker alone does not identify a loaded process. At final process inspection PID36184 still ran the older default-Xcode-DerivedData app. No old process was killed, no installed app was overwritten, and no second persistent app was launched for the user. Xcode test-host processes were temporary test execution, not evidence of physical acceptance. Opening the new interactive build remains a safe user-operated handoff.

1. Finish recording and resolve any clipboard recovery in the old app. Quit normally; stop on a warning, never force quit. Open the exact bundle above and confirm37 in General.
2. Use harmless fresh unsent drafts. Hold Fn, speak, release. Start with three sessions each in ChatGPT, WhatsApp and TextEdit, then Codex and VSCode. Never submit messages/prompts or use terminal commands as test text.
3. Observe actual text, duplicates, focus and clipboard preservation. Dispatch is not success. If recovery is pending, only confirm after observing the text and using the existing recovery control. Do not repeatedly retry a possibly delivered utterance. If readback is unsupported, retain that distinction even when text visibly appeared.
4. If paste is rejected/unknown, preserve the transcript, inspect General's stage codes, and use explicit Copy only when allowed. Restore a backup only through its session-bound user confirmation. A newer user clipboard copy must remain untouched.
5. Test cross-app sequences and cancel/focus-loss with separate fresh drafts. Report only pass/fail, counts and diagnostic codes, never private transcript/clipboard contents.
6. Browser tests may use `Evidence/Milestone37/Fixtures/editor-check.html`: local synthetic single-line, multiline, contenteditable and secure-field controls with no network/scripts/submission. Opening and typing are user-operated.

No physical keyboard events were injected or private chats/clipboard contents inspected by verification tools. No live AI was used. Actual36/37 permissions and native editor readback remain user-device gates.

## Remaining release blockers

- Actual ChatGPT failure stage and physical regression cause are unresolved until the new diagnostic trace is supplied.
- Required3-session primary-app tests and transitions remain UNVERIFIED. P0 release blocker remains open.
- Opaque paste requires explicit recovery before seamless repetition; cannot truthfully claim universal or production-grade cross-app delivery.
- Capability/focus/caret changes between synchronous checks and the destination consuming an asynchronous event remain native interaction limits. PID-bound dispatch and validation reduce risk, not provide an OS delivery transaction.
- Secure/read-only/unsupported editor contexts fail closed; Terminal automatic insertion remains unsupported.
- AI replacement remains narrower than ordinary paste; these tests confer no new AI authority.

## Git state

Branch and HEAD remain unchanged as above. No staged files, commits, pushes, merges, rebases, resets or remote operations. All pre-existing cumulative changes remain; the tree is intentionally dirty. The status snapshot below was taken immediately before writing this new report; this report adds one further untracked documentation file. Evidence/ and DerivedData/ remain ignored local artifacts.

```text
 M App/AppComposition.swift
 M App/ClickableDictationPill.swift
 M App/DictationPreferences.swift
 M App/GlobalDictationView.swift
 M App/SystemWideDictationCoordinator.swift
 M App/WesleyFlowApp.swift
 M AppTests/DictationTests.swift
 M AppTests/GlobalDictationTests.swift
 M Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
 M Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift
 M Packages/WesleyFlowCore/Sources/Domain/PromptEngineering.swift
 M Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift
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
?? Docs/Phase1F/MILESTONE36D-DICTATION-PROVENANCE.md
?? Docs/Phase1F/MILESTONE36E-INSERTION-VERIFICATION.md
?? Docs/Phase1F/MILESTONE36F-CROSS-APP-RELIABILITY.md
?? Packages/WesleyFlowCore/Sources/Domain/DictationEnhancements.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationVerification.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/DictationSpanVerification.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/FocusedTextResolver.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AudioLevelMailbox.swift
?? Packages/WesleyFlowCore/Tests/WorkspaceTests/FocusedTextResolverTests.swift
```

## Exact verification commands

The following commands ran in the repository. All evidence paths are local ignored outputs, not publication artifacts.

### focused

Exit code: **0**. 2026-10-28T09:18:46.456565+00:00 → 2026-10-28T09:19:05.436104+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-Verified -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug -parallel-testing-enabled NO -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Milestone37/ReleaseCandidate/focused.xcresult test -only-testing:WesleyFlowAppTests/CoreDelivery37Tests -only-testing:WesleyFlowAppTests/CrossAppReliabilityTests -only-testing:WesleyFlowAppTests/InsertionReadbackRepairTests -only-testing:WesleyFlowAppTests/GlobalInsertionTests -only-testing:WorkspaceTests/DictationSpanVerificationTests -only-testing:WesleyFlowAppTests/GlobalCoordinatorTests -only-testing:WesleyFlowAppTests/ContinuousHUDTests -only-testing:WesleyFlowAppTests/LiveAudioEnergyTests -only-testing:WesleyFlowAppTests/InPlaceRewriteTests -only-testing:WesleyFlowAppTests/FocusedPreviewCaptureTests -only-testing:WorkspaceTests/FocusedTextResolverTests -only-testing:WesleyFlowAppTests/ShortcutDeliveryDiagnosisTests -only-testing:WesleyFlowAppTests/GlobalAIShortcutWorkflowTests -only-testing:WesleyFlowAppTests/ExplicitPreviewAppTests -only-testing:WorkspaceTests/GlobalPreviewDeliveryTests
```

### full

Exit code: **0**. 2026-10-28T09:19:05.489147+00:00 → 2026-10-28T09:19:17.922361+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-Verified -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug -parallel-testing-enabled NO -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Milestone37/ReleaseCandidate/full.xcresult test
```

### replay

Exit code: **0**. 2026-10-28T09:19:17.971820+00:00 → 2026-10-28T09:19:30.009038+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-Verified -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug -parallel-testing-enabled NO -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Milestone37/ReleaseCandidate/replay.xcresult test
```

### debug

Exit code: **0**. 2026-10-28T09:19:30.058029+00:00 → 2026-10-28T09:19:33.876000+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-Verified -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug build
```

### release

Exit code: **0**. 2026-10-28T09:19:33.947039+00:00 → 2026-10-28T09:20:00.980598+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-Verified -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Release build
```

### concurrency

Exit code: **0**. 2026-10-28T09:20:01.031333+00:00 → 2026-10-28T09:20:04.331442+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-Verified -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Release SWIFT_STRICT_CONCURRENCY=complete build
```

### repository

Exit code: **0**. 2026-10-28T09:19:22.838507+00:00 → 2026-10-28T09:19:43.841922+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/opt/homebrew/bin/python3.11 Tools/CI/repository_checks.py
```

### Offline Model Lab

Exit code: **0**. 152 Model Lab tests and 7 native resource-guard tests passed. This ran before the final private native AX-denial guard; no Model Lab/provider/validator source changed afterward.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/opt/homebrew/bin/python3.11 Tools/CI/run_checks.py model-lab --output /Users/akshaywesley/Developer/WesleyFlow/Evidence/Milestone37/Verified/model-lab
```

## Verified Debug build fingerprints

```json
{
  "DerivedData/Milestone37-Verified/Build/Products/Debug/Wesley Flow.app/Contents/MacOS/Wesley Flow": "267626fe712628ff5fadb166412b223450a1f838d584ce8306ceedfee3740d8a",
  "DerivedData/Milestone37-Verified/Build/Products/Debug/Wesley Flow.app/Contents/MacOS/Wesley Flow.debug.dylib": "e36b426a9b92b95aebe3f5d437ceef276e823549a4b892b3128dda974de32aea"
}
```

## User-operated follow-up — 2026-10-28

The user reports WhatsApp dictation works, while ChatGPT macOS dictation still fails with an exclamation symbol after speaking. Option+1 and Option+2 in WhatsApp report Editor unsupported. Exact stage codes, three-session counts, duplicate/focus/clipboard observations have not yet been supplied. These are physical observations, not inferred fixture outcomes.

A process identity check confirmed PID45749 executes DerivedData/Milestone37-Verified/Build/Products/Debug/Wesley Flow.app/Contents/MacOS/Wesley Flow. Therefore a different running app path is not an established explanation for this report. No app was stopped, replaced or relaunched.

Updated status: ChatGPT ordinary dictation FAILED in the reported attempt; WhatsApp ordinary dictation WORKING as reported, repetition gate still UNVERIFIED; WhatsApp exact AI replacement REJECTED AS UNSUPPORTED, precise capability reason pending diagnostics. Other matrix entries remain UNVERIFIED. The earlier pending matrix is retained as the pre-follow-up record. Successful ordinary insertion must not grant exact AI replacement authority.

Requested only General diagnostic codes/status following a failed ChatGPT dictation; no private text or clipboard contents. The exclamation symbol alone does not establish whether acquisition, identity validation, paste dispatch, or lease recovery failed. No speculative source change, safeguard weakening, commit, push or additional model execution was performed in this follow-up.

### Supplied diagnostic interpretation

The subsequently supplied trace identifies destinationBundle=net.whatsapp.WhatsApp, operation=promptEngineering, outcome=INSERTED_VERIFIED, TRANSCRIPTION_RESULT=SUCCESS, TARGET_VALIDATION_RESULT=SUCCESS, and DESTINATION_READBACK_RESULT=VERIFIED_INSERTION_AVAILABLE. WhatsApp ordinary insertion was independently verified for that session. The trace reports SELECTED_TEXT_WRITABLE unsupported, SELECTION_RANGE_WRITABLE success, PRECISE_REPLACEMENT_CAPABILITY unsupported, eligibleReceipt=false and EDITOR_REPLACEMENT_UNSUPPORTED. The application withheld exact replacement authority; AI_GENERATION=NOT_REQUESTED. This is not a model-resource failure and is not a ChatGPT trace. The generic INSERTION_DISPATCH_RESULT=DISPATCHED_UNVERIFIED describes dispatch itself; the separate readback/outcome reports verified completion. No private text from the user was requested or stored.

Requested a fresh failed ChatGPT dictation followed immediately by General, with no intervening WhatsApp attempt or AI shortcut, to avoid inspecting a different session's diagnostic result. ChatGPT's first failing stage remains unresolved.

### Confirmed ChatGPT acquisition failure

A fresh user-supplied Milestone37 trace identifies destinationBundle=com.openai.codex with CAPTURE_RESULT=SUCCESS, TRANSCRIPTION_RESULT=SUCCESS, TARGET_CAPTURE_RESULT=FAILED, outcome=UNSUPPORTED_TARGET, TARGET_VALIDATION_RESULT=NOT_STARTED, PASTEBOARD_LEASE_RESULT=NOT_NEEDED, INSERTION_DISPATCH_RESULT=NOT_STARTED, and DESTINATION_READBACK_RESULT=NOT_REQUESTED. This establishes that ordinary dictation stops at native target acquisition before any pasteboard lease, dispatch, readback or model request. The trace contains only TARGET_CAPTURE_FAILED, without EDITABLE_ROLE_SUPPORTED. In the current initializer this narrows the unsupported exit to application identity acquisition, focused-window acquisition, or focused-editor resolution; it does not prove which native AX attribute is missing. Actual app identity is recorded, but launch-date availability is not established by that fact alone. The existing Dictation-page failureExplanation distinguishes these stages; its exact privacy-safe sentence was requested before changing the mechanism.

The separately supplied WhatsApp trace again shows INSERTED_VERIFIED, supported readback and CLIPBOARD_RESTORED, with AI replacement withheld as EDITOR_REPLACEMENT_UNSUPPORTED. No clipboard-delivery failure is demonstrated by the ChatGPT trace, so modifying clipboard timing or adding a paste retry is not justified. No source behavior was changed based on this report.

## Focused-editor diagnostic follow-up (37R1)

The user's screenshot confirms the exact application warning: “The app does not expose a focused text field. Copy the transcript from History.” Combined with the preceding com.openai.codex trace, this identifies failure inside focusedElement resolution after original application and focused-window acquisition. The screenshot background does not by itself establish the destination app; the correlated prior diagnostic trace does. No unrelated screenshot text was used as evidence or copied into repository artifacts.

Source inspection found that the resolver already checks application focus, system focus and a focused-window descendant search bounded to64 nodes/depth8/250ms. It requires an explicitly focused supported editor; it does not choose any convenient text box. The current metadata discards native errors for focus reads, so this report cannot yet distinguish missing AX focus from a returned non-editor container or a transient native failure. Broadening roles, activating the accessibility tree or blindly pasting would not be justified by that evidence.

37R1 therefore adds fixed-vocabulary APPLICATION_FOCUSED_ELEMENT, SYSTEM_FOCUSED_ELEMENT, FOCUSED_WINDOW, FOCUS_CANDIDATE_IS_EDITOR, FOCUSED_EDITOR_SEARCH, FOCUS_SEARCH_LIMIT and FOCUS_SEARCH_DEADLINE diagnostics. It records numeric native status and bounded search activity, never labels, text values, conversation contents or clipboard data. Application/system/window focus query closures now propagate explicit denied/invalid-element errors instead of silently treating those as missing attributes and falling through. Ordinary missing focus still allows the same existing bounded fallback. No new discovery route or supported-role expansion was added. The search diagnostic's observed field describes the visited node count, not transcript length.

Added regression coverage: denied/changed application focus reads stop fallback; denied system focus stops window search; missing application/system focus retains the existing owned-editor window route. Existing foreign-owner, secure-element, read-only and no-guessing tests remain. This is diagnostic hardening, **not a physically confirmed ChatGPT compatibility repair**.

The build uses a separate DerivedData/Milestone37-FocusR1 directory and the General marker37R1. The running37 app was not overwritten or stopped. Verification results and build identity follow below once completed. ChatGPT remains FAILED for the last observed37 attempt; 37R1 physical acceptance is UNVERIFIED.

### 37R1 verification and handoff

Final focused results:385 expanded cases /205 declarations; complete suite:1,254 cases /576 declarations; independent replay:1,254 cases /576 declarations. All have zero failures and skips. Debug, Release and Release SWIFT_STRICT_CONCURRENCY=complete builds passed. Offline Model Lab:152 tests; native resource guards:7 tests; no model inference. All command exit codes are0. Four expanded cases in three declarations were added after the previous1,250-case baseline; no tests removed or weakened. The final results are in Evidence/Milestone37/FocusR1; summary JSON files preserve actual Xcode counts. Source-preservation checks in frozen-source-check.json are all true. Git diff --check passed; nothing staged, committed or pushed.

The test bundle is `/Users/akshaywesley/Developer/WesleyFlow/DerivedData/Milestone37-FocusR1/Build/Products/Debug/Wesley Flow.app`, General marker37R1. At handoff PID45749 still runs the previous Milestone37-Verified path; the diagnostic app has not been launched interactively, and no existing app was replaced or quit. Build fingerprints are in FocusR1/build-identity.json.

Next action: user finishes recording and clipboard recovery, quits the older app normally (stop on any warning), opens the exact37R1 bundle, and makes one fresh unsent ChatGPT dictation. Immediately inspect General and return only the APPLICATION_FOCUSED_ELEMENT, SYSTEM_FOCUSED_ELEMENT, FOCUSED_WINDOW, FOCUS_CANDIDATE_IS_EDITOR, FOCUSED_EDITOR_SEARCH and any limit/deadline/error codes. No WhatsApp attempt or AI shortcut should intervene. Native delivery/compatibility remains UNVERIFIED for37R1; the last physically observed37 ChatGPT attempt FAILED. No broad new compatibility claim is made.

Apple documents the application-level focus attributes in [kAXFocusedUIElemenAttribute](https://developer.apple.com/documentation/applicationservices/carbon_accessibility/attributes/kaxfocuseduielemenattribute) and [kAXFocusedWindowAttribute](https://developer.apple.com/documentation/applicationservices/kaxfocusedwindowattribute). This change observes existing supported APIs; it does not claim every editor implements them.

Exact37R1 commands and outcomes (repository working directory):

- focused: exit0; 2026-10-28T09:30:45.760129+00:00 to 2026-10-28T09:32:32.431972+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-FocusR1 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug -parallel-testing-enabled NO -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Milestone37/FocusR1/focused.xcresult test -only-testing:WesleyFlowAppTests/CoreDelivery37Tests -only-testing:WesleyFlowAppTests/CrossAppReliabilityTests -only-testing:WesleyFlowAppTests/InsertionReadbackRepairTests -only-testing:WesleyFlowAppTests/GlobalInsertionTests -only-testing:WorkspaceTests/DictationSpanVerificationTests -only-testing:WesleyFlowAppTests/GlobalCoordinatorTests -only-testing:WesleyFlowAppTests/ContinuousHUDTests -only-testing:WesleyFlowAppTests/LiveAudioEnergyTests -only-testing:WesleyFlowAppTests/InPlaceRewriteTests -only-testing:WesleyFlowAppTests/FocusedPreviewCaptureTests -only-testing:WorkspaceTests/FocusedTextResolverTests -only-testing:WesleyFlowAppTests/ShortcutDeliveryDiagnosisTests -only-testing:WesleyFlowAppTests/GlobalAIShortcutWorkflowTests -only-testing:WesleyFlowAppTests/ExplicitPreviewAppTests -only-testing:WorkspaceTests/GlobalPreviewDeliveryTests
```

- full: exit0; 2026-10-28T09:32:39.566210+00:00 to 2026-10-28T09:32:58.374670+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-FocusR1 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug -parallel-testing-enabled NO -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Milestone37/FocusR1/full.xcresult test
```

- replay: exit0; 2026-10-28T09:32:58.437948+00:00 to 2026-10-28T09:33:14.609072+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-FocusR1 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug -parallel-testing-enabled NO -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Milestone37/FocusR1/replay.xcresult test
```

- debug: exit0; 2026-10-28T09:33:14.663648+00:00 to 2026-10-28T09:33:18.882515+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-FocusR1 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug build
```

- release: exit0; 2026-10-28T09:33:18.930137+00:00 to 2026-10-28T09:34:40.840153+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-FocusR1 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Release build
```

- concurrency: exit0; 2026-10-28T09:34:40.924319+00:00 to 2026-10-28T09:34:44.070117+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-FocusR1 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Release SWIFT_STRICT_CONCURRENCY=complete build
```

- model-lab: exit0; 2026-10-28T09:34:44.117384+00:00 to 2026-10-28T09:35:13.061299+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/opt/homebrew/bin/python3.11 Tools/CI/run_checks.py model-lab --output /Users/akshaywesley/Developer/WesleyFlow/Evidence/Milestone37/FocusR1/model-lab
```


## Confirmed37R1 native observation — 2026-10-28

User reports continued ChatGPT insertion failure. Read Wesley Flow's own General diagnostics directly, without inspecting or interacting with the ChatGPT editor or reading the clipboard. The observed37R1 session for destinationBundle=com.openai.codex reports:

- FOCUSED_WINDOW:success, AX=0.
- APPLICATION_FOCUSED_ELEMENT:unsupported, AX=-25212.
- SYSTEM_FOCUSED_ELEMENT:unsupported, AX=-25212.
- FOCUSED_EDITOR_SEARCH:unsupported, observed=7 visited nodes.
- TARGET_CAPTURE_FAILED and UNSUPPORTED_TARGET after successful speech/transcription.

Verified in the installed SDK HIServices AXError.h: kAXErrorNoValue=-25212, distinct from kAXErrorAPIDisabled=-25211. General shows Accessibility Allowed. Thus the observed failure is no focused editor returned by either focus API and none found in the exposed bounded window tree. It is not a demonstrated memory-admission, microphone or clipboard-timing failure. No destination event is sent. This explains the current resolver rejection, but does not establish why older native sessions once worked or prove which internal ChatGPT configuration produced this accessibility surface. The7-node search does not reach the64-node limit; increasing that limit has no demonstrated justification.

No field exists in this observed accessibility surface that the current safe resolver can bind. A blind frontmost-app paste would weaken the editor identity/secure-field requirements and is not implemented. The previously declined AXManualAccessibility/AXEnhancedUserInterface activation remains disabled; no new consent was inferred or requested. Manual recovery remains Copy latest dictation followed by user-operated paste into ChatGPT, subject to existing lease controls. This is a workaround, not successful automatic delivery.

The first computer-use app selection by display name accidentally opened the idle older Milestone29 bundle (PID54567). Its own General screen showed microphone/speech not requested, no active dictation, history unavailable, and shortcut registration conflict. It was quit normally with Command+Q; no force termination or clipboard operation. Exact-path selection then read the existing37R1 app (PID54395). A subsequent process check confirmed37R1 was the sole running Wesley Flow instance. No permissions/settings were enabled; no ChatGPT/Codex global keys, microphone experiments or insertion actions were automated. The older-copy launch is an inspection error and must not be confused with the original37R1 failure; the observed failure diagnostics already belonged to37R1.

Sanitized metadata is recorded in Evidence/Milestone37/FocusR1/native-chatgpt-capture-failure.json. No screenshot containing private conversations, transcripts or clipboard data was saved to the repository. Application source was not modified during this observation, so the preceding1,254-case/replay/build evidence remains applicable to the unchanged37R1 source.

**Current disposition: Milestone37 INCOMPLETE; automatic ChatGPT insertion BLOCKED under the observed editor capabilities and preserved safety constraints. WhatsApp remains independently verified in supplied traces; its exact AI replacement remains unsupported. No universal compatibility or completion claim.**

## Subsequent user-observed ChatGPT success — 2026-10-28

The user now reports: “rn its working on chatgpt too.” Record this as user-observed successful ChatGPT insertion, superseding the prior blanket current-blocked status. The earlier no-focused-element observation remains valid for that failed session; it does not establish a permanent editor limitation. No application source, permission, or accessibility-tree setting was changed by this follow-up. The exact build/session, number of consecutive successes, independent readback outcome, duplicate/focus behavior and clipboard recovery were not supplied with this success report. Do not infer those results.

Current acceptance: ChatGPT automatic insertion WORKING IN USER-REPORTED USE; repeated-session reliability UNVERIFIED, with earlier failed sessions documented. Requested three consecutive fresh unsent dictations and observations of missing text, duplicates and clipboard warnings. The change from failure to success warrants treating focused-editor exposure as session-dependent pending evidence; its underlying cause remains unresolved. Milestone37 remains INCOMPLETE until the required repetition and cross-application safety gates are demonstrated. No tests rerun because this update changes documentation only. No commit or push.
