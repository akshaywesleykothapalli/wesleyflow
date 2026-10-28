# Milestone37R2 — Pill refinement and Smart Formatting support review

> Acceptance update, 28 October 2026: the user confirms 3/3 physical ChatGPT dictations passed on 37R2. Earlier failure/pending statements below describe the historical investigation. Other editors, clipboard/focus edge cases and AI replacement are not thereby physically verified. Automatic replacement in the affected editors remains unsupported. See [publication review](MILESTONE37-PUBLICATION-REVIEW.md).

2026-10-28. Pill presentation implemented and automated verification passed. Physical UI acceptance remains UNVERIFIED. In-place AI replacement in the affected editors remains UNSUPPORTED; it is not reported as fixed.

## Requested presentation

- No exclamation symbol: removed the warning symbol rendering. Ordinary dictation errors hide the pill and remain actionable on the Dictation page with existing transcript/recovery controls.
- No Preparing label: the native panel stays hidden while preparing; the existing real microphone-reactive waveform appears only when recording is acknowledged.
- After speech: finalizing and inserting both display Transcribing…. Finishing is removed. The underlying processing stages and diagnostics remain separate.
- AI progress and compact textual AI errors remain, with no warning glyph. Existing verified checkmark and idle/Ready behavior are unchanged.
- The84×32 dimensions, bar rendering, audio bars, nonactivating panel, Reduce Motion handling, cancellation and clipboard broker are unchanged.

One shared pillContent resolver is used by the renderer and native panel visibility check, so hidden startup/error content does not leave an empty visible panel.

## Smart Formatting review and remaining limitation

Option+1/2 currently invoke exact in-place replacement. Ordinary dictation success does not confer authority to rewrite existing text. ChatGPT's existing com.openai.codex direct-AX-replacement exclusion remains. The supplied WhatsApp traces report selected-text writes unsupported, so the current exact replacement adapter rejects that capability even when paste/readback works. The adapter also checks composition, exact text/context/caret, session identity and focus before writes. No native paste-based range-replacement adapter is implemented or physically verified here.

No safety guard was removed to make an unsupported editor appear supported. The rejection message now points to Smart Formatting's existing manual preview and Copy workflow. A user may explicitly choose a saved dictation or supply text and open the manual Smart Polish/Prompt Engineering preview, review generated output and copy explicitly. No preview is automatically opened by global shortcuts, no text is automatically copied or submitted, and no model was run during this task. Existing resource admission may still block generation. Manual generation quality was not reverified in this UI refinement.

## Source scope and preservation

Changed in this follow-up only: App/ClickableDictationPill.swift, App/SystemWideDictationCoordinator.swift (build marker37R2 and actionable rejection wording), AppTests/GlobalDictationTests.swift and this report. All earlier uncommitted work remains. VoiceInput files, ModelProviders files, AI Domain prompts and Package.swift matched the task-start hashes; evidence in frozen-check.json. No speech engine, waveform algorithm, AI provider, model dataset,4GiB floor, hotkey behavior or clipboard lease change. No third-party dependency or permission activation. No commit/push.

## Actual verification

| Gate | Result | Exit |
| --- | --- | --- |
| Focused regression | 387 expanded cases /207 declarations, no failures/skips | 0 |
| Complete suite | 1,256 cases /578 declarations, no failures/skips | 0 |
| Independent replay | 1,256 cases /578 declarations, no failures/skips | 0 |
| Debug | Passed | 0 |
| Release | Passed | 0 |
| Release strict concurrency | Passed, SWIFT_STRICT_CONCURRENCY=complete | 0 |
| git diff --check | Passed | 0 |

Two tests were added for hidden preparation/error presentation and the shared post-speech label. The existing inserting-label assertion was updated to the new requested behavior; all other regression expectations remain. Initial focused run exited65: changing the unsupported-editor sentence broke two parameterized compact-status assertions because that existing mapper recognizes a message prefix. Restored the recognized prefix and appended the guidance instead, without weakening tests or changing error classification. The corrected focused/full/replay/build runs above all passed. Initial failure evidence remains in Evidence/Milestone37/PillR2; final evidence is PillR2-Final. Model Lab tests were not rerun for presentation-only source changes; the preceding37R1 run remains historical152+7 passes, not a fresh result.

Actual visual/physical acceptance and live inference were not simulated. No interactive new build was launched and no running instance was quit/replaced in this follow-up. Safely finish active recording/clipboard recovery and quit the older app normally before opening the new build; stop on warnings.

Verified bundle: `/Users/akshaywesley/Developer/WesleyFlow/DerivedData/Milestone37-PillR2/Build/Products/Debug/Wesley Flow.app`. General marker37R2. Its code hashes are in PillR2-Final/build-identity.json. The working tree remains dirty with cumulative work; nothing staged. Branch feature/milestone-31-integration, HEAD23caeca630b803fddc2cd007a5159dc9839b71cf unchanged. Overall Milestone37 physical acceptance remains incomplete; recent user reports successful ChatGPT and WhatsApp dictation but not the full repetition/safety matrix.

## Commands and exit evidence

### focused

Exit0. 2026-10-28T10:15:15.535921+00:00 → 2026-10-28T10:15:30.564692+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-PillR2 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug -parallel-testing-enabled NO -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Milestone37/PillR2-Final/focused.xcresult test -only-testing:WesleyFlowAppTests/CoreDelivery37Tests -only-testing:WesleyFlowAppTests/CrossAppReliabilityTests -only-testing:WesleyFlowAppTests/InsertionReadbackRepairTests -only-testing:WesleyFlowAppTests/GlobalInsertionTests -only-testing:WorkspaceTests/DictationSpanVerificationTests -only-testing:WesleyFlowAppTests/GlobalCoordinatorTests -only-testing:WesleyFlowAppTests/ContinuousHUDTests -only-testing:WesleyFlowAppTests/LiveAudioEnergyTests -only-testing:WesleyFlowAppTests/InPlaceRewriteTests -only-testing:WesleyFlowAppTests/FocusedPreviewCaptureTests -only-testing:WorkspaceTests/FocusedTextResolverTests -only-testing:WesleyFlowAppTests/ShortcutDeliveryDiagnosisTests -only-testing:WesleyFlowAppTests/GlobalAIShortcutWorkflowTests -only-testing:WesleyFlowAppTests/ExplicitPreviewAppTests -only-testing:WorkspaceTests/GlobalPreviewDeliveryTests
```

### full

Exit0. 2026-10-28T10:15:30.617817+00:00 → 2026-10-28T10:15:45.591135+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-PillR2 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug -parallel-testing-enabled NO -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Milestone37/PillR2-Final/full.xcresult test
```

### replay

Exit0. 2026-10-28T10:15:45.639739+00:00 → 2026-10-28T10:15:57.780986+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-PillR2 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug -parallel-testing-enabled NO -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Milestone37/PillR2-Final/replay.xcresult test
```

### debug

Exit0. 2026-10-28T10:15:57.831620+00:00 → 2026-10-28T10:16:01.617846+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-PillR2 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug build
```

### release

Exit0. 2026-10-28T10:16:01.669254+00:00 → 2026-10-28T10:17:11.652303+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-PillR2 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Release build
```

### concurrency

Exit0. 2026-10-28T10:17:11.716563+00:00 → 2026-10-28T10:17:14.367202+00:00

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone37-PillR2 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Release SWIFT_STRICT_CONCURRENCY=complete build
```

## Git snapshot

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
?? Docs/Engineering/MILESTONE37-CORE-DICTATION.md
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
