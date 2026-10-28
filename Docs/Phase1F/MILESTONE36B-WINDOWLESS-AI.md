# Milestone 36B — True windowless AI shortcuts

27 October 2026. Windowless routing implementation and automated verification **PASSED**. Physical shortcut and live in-place generation/replacement acceptance remain **UNVERIFIED**. No commit, push or merge. All prior uncommitted work is preserved.

## Confirmed preview-opening cause

36A intentionally retained this branch: invokeShortcutPreview checked inPlaceAIRewrite; when OFF it continued into the old preview/capture flow. That flow could present the editor immediately (manual input, no resolver, or generation already active), or after bounded focused-text resolution, including unsupported/empty/denied results. Thus “This editor does not expose supported readable text. Enter text here instead” was a real **preview-fallback branch**, not a model-memory diagnostic.

The user now explicitly replaces that policy. Initial36B inspection found one interactive instance, PID78652, at DerivedData/Milestone36A/Build/Products/Debug/Wesley Flow.app/Contents/MacOS/Wesley Flow. Saved inPlaceAIRewrite was false; Smart Polish, Prompt Engineering and previewShortcutsEnabled were true. These are saved Boolean observations, not a claim that the exact historical cached state or physical key receipt was observed. Unlike36A's earlier inspection, no second old instance was found at the start of36B.

## Removed automatic paths and deterministic policy

Both native notifications (invoke and invokeFrom) now call **invokeAIShortcut**. That method never calls openExplicitPreview, the focused-text resolver or the presentation-request function. It fences/cancels pending manual capture/generation and hides an existing manual panel, then:

- Saved/memory mode disagreement: pill-only safe rejection; no preference write or route fallback.
- In-place OFF: **“Enable in-place AI rewrite in Settings.”** Pill only; no automatic opt-in.
- In-place ON: request the existing safe in-place operation on the latest eligible own dictation.
- Busy/closed/duplicate operations: reject/ignore without a presentation request.

All three former positive-presentation sites (already-generating preview, immediate manual fallback, asynchronous capture completion/failure) now belong only to **openExplicitPreview**, reached through explicit Smart Formatting buttons. The one private requestExplicitPreviewPresentation seam is the **only** assignment setting previewPresented=true, and is instrumented with an injected presentation-request spy. A delayed manual capture is ticket-fenced when a shortcut arrives, so it cannot reopen the editor afterward.

The explicit preview controller no longer allocates an NSPanel at launch. It lazily creates the existing editor only after an explicit presentation request. The editor is not renamed/disguised as a shortcut fallback; its36B title identifies the optional manual tool. Existing in-app supplied/history previews remain explicit, and legacy bounded-read capture tests now exercise the explicit helper rather than a global key. No source text is re-requested by Option+1/2.

## Existing pill and waveform

The84×32 nonactivating pill is the only automatic shortcut feedback. Polishing/Structuring, verified completion and1.2-second transient dismissal remain. AI failures now show concise text inside that pill, such as Enable in-place AI, No recent dictation, Accessibility needed, Editor unsupported, Memory blocked or Text/target changed. The full safe reason remains in tooltip/accessibility help and the existing General shortcut-status row. No separate error editor appears. No fake waveform is used for AI generation.

App/ClickableDictationPill.swift changed **only HUD status selection/text layout**, allowing two centered lines. The seven teal bars, proportions, materials, placement, real RMS source, smoothing, UI sampling and Reduce Motion waveform handling are unchanged. Byte-hash comparisons confirm AppleDictationInput, AudioLevelMailbox, NativeSpeechCallbacks, DictationAudioEnvelope/anchor Domain file and AppleTranscriptRewriter unchanged. The full pill-file hash changes because of status rendering; it is not presented as an unchanged file.

## Provenance, effects and model safety

Unchanged36/36A safeguards require a new app-owned verified dictation (enable in-place before dictating), original session/PID/launch/window/element, exact UTF-16 span, own original transcript, expected context hash, original focus/caret, writable capability, no secure input/IME composition, and120-second freshness. History is not an authority source. Failed/uncertain insertion and unrelated manually typed text do not become rewrite targets. Unicode/multiline handling uses the existing exact-range implementation.

Option+1 passes the own transcript to Smart Polish with its configured tone; Option+2 passes it to the existing Prompt Engineering contract/provider. Complete output is preservation-validated, then the source is rechecked before one consumed exact-span mutation and verification. No Enter, keystroke, automatic submission, whole-document replacement or clipboard write was added. History/word metrics remain the original dictation. Cancellation returns the retired task for deterministic test completion; cancelled/stale results cannot replace text.

Apple FoundationModels composition, availability/resource policy and4GiB floor are unchanged. No live inference, model download, new memory measurement or cloud call was performed. Automated fixture success is not live model quality evidence.

Exact-range native support remains capability-dependent: unknown AXMarkedTextRange/IME state, stale identity or unreadable/unsettable text ranges reject the operation. ChatGPT/TextEdit/VS Code native rewrite compatibility remains unverified. Existing Codex direct-write exclusion remains; Terminal stays manual-copy only. AXManualAccessibility/AXEnhancedUserInterface activation stays disabled. AX operations are not an atomic compare-and-swap: preflight failure leaves text untouched; a failure after selection/write dispatch can be uncertain and may already have changed selection/text. No retry or automatic rollback is attempted. Universal safe replacement is not claimed.

## Automated evidence

Xcode27.0 at /Applications/Xcode-beta.app/Contents/Developer, Swift6.4, SDK27.0, macOS26.0 arm64 deployment target; actual host macOS27.2. No macOS26 runtime verification is claimed.

| Check | Actual result | Exit |
|---|---|---|
| focused | 185 expanded cases / 98 declarations; 0 failures / 0 skips | 0 |
| full | 1137 expanded cases / 523 declarations; 0 failures / 0 skips | 0 |
| replay | 1137 expanded cases / 523 declarations; 0 failures / 0 skips | 0 |
| debug | passed | 0 |
| release | passed | 0 |
| concurrency | passed | 0 |
| Debug bundle codesign verification | passed | 0 |
| Changed/new secret and artifact scan | passed; values not printed | 0 |
| Git diff whitespace | passed | 0 |

The1,104-case /518-declaration baseline is retained;33 expanded cases /5 declarations yield **1,137 /523**. Historical OFF-mode tests now assert the newly authorized HUD-only behavior. Explicit capture/manual-preview assertions were retained on the explicit entry point, not deleted. New coverage includes:

- A presentation spy at the real coordinator request seam: **zero** requests for both kinds across success, disabled mode, no eligible dictation, permission denial, unsupported/secure/changed/foreign target, resource block, invalid output, unavailable/timed-out model and disabled feature.
- Explicit Settings requests do reach the spy; a positive control proves it detects presentation.
- A held manual capture completed after a shortcut cannot request presentation.
- Duplicate requests, cancellation and source editing during held generation produce no duplicate/stale write or presentation; tests await the cancelled task's actual completion.
- Conflicting saved mode in both directions, concise disabled feedback, deterministic pill dismissal and no native preview allocation.
- Existing dictation, preview contracts, clipboard lease, voice, history and recovery coverage remains. The historical lateSuccessIsDiagnosticAndCannotReplaceTimeout passed in full/replay; no further recovery code/test changes were required.

Initial focused and final focused/full/replay runs all passed. No36B failed tests were hidden or disabled. Nonblocking AppIntents metadata and local com.apple.linkd.autoShortcut warnings remain recorded; they do not prove physical key delivery. No Model Lab execution was needed because this milestone changed no provider, dataset or resource logic.

Exact argv, exit and timestamps: Evidence/Milestone36B/Final/{focused,full,replay,debug,release,concurrency}.json and .log, with native .xcresult bundles and summaries. All builds ran sequentially in DerivedData/Milestone36B. Commands use:

```
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone36B -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 ...
```

Full/replay append `-configuration Debug -parallel-testing-enabled NO -resultBundlePath <unique path> test`, no exclusions. Focused JSON records suite selections. Build commands use Debug/Release build; concurrency adds SWIFT_STRICT_CONCURRENCY=complete. Bundle verification uses codesign --verify --strict. Evidence/source-preservation JSON explicitly records the HUD-file exception above.

## Running build and physical handoff

The user agreed to test after verification; **no physical result has yet been supplied**. No global key event, microphone capture, private editor read or text submission was automated.

After builds, a process recheck found **no running Wesley Flow instance**. None was terminated by this task. The signature-verified36B bundle was then opened successfully (open exit0). The subsequent sole Wesley Flow process was **PID82566**, exact executable:

`/Users/akshaywesley/Developer/WesleyFlow/DerivedData/Milestone36B/Build/Products/Debug/Wesley Flow.app/Contents/MacOS/Wesley Flow`

Bundle local.wesleyflow.WesleyFlow, version0.1.0/build1; actual executable/debug-dylib SHA256s are in Evidence/Milestone36B/Final/build-hashes.json. Running path/version evidence is in running-test-build.json; launch checks in launch.json. The optional manual-preview title and In-place AI description identify36B. No older copy was running at this check. Physical exclusive Carbon ownership/receipt remains UNVERIFIED, rather than inferred from a process name. No active app was replaced or force-quit, and no clipboard recovery was discarded. The saved in-place preference remains OFF; other observed flags remain ON. No options/permissions were enabled on the user's behalf.

| Physical check | Result |
|---|---|
| OFF mode, Option+1/2: pill only | UNVERIFIED |
| ChatGPT fresh dictation + Option+2, no preview/submission | UNVERIFIED |
| TextEdit fresh dictation + Option+2, no preview | UNVERIFIED |
| Option+1 on fresh dictated text in both apps | UNVERIFIED |
| Unsupported/changed target: original retained, no preview | UNVERIFIED |
| Live generation/replacement, focus and clipboard | UNVERIFIED |

Test the already opened36B build. First leave in-place OFF and press/release each shortcut: expect only Enable in-place AI in the pill. Then explicitly enable in-place (the desired features and shortcut registration must be enabled), dictate NEW synthetic text, confirm verified insertion and use a shortcut within120 seconds without moving the caret/switching editor. Try TextEdit then ChatGPT. Use a separate new dictation for the other operation; changed replacements consume the anchor once. Never submit. Edit a new dictation before invoking: it must reject. Unknown capability/model/resource rejection should leave text alone, with no input editor. Read the exact full reason from General's existing status row if needed. Check clipboard privately, never send its contents. Do not repeatedly retry a memory block. Restore optional settings afterward if desired.

## Files and Git

36B changes are limited to App/SystemWideDictationCoordinator.swift, App/WesleyFlowApp.swift (lazy explicit presenter), App/GlobalDictationView.swift (explicit commands/descriptions), App/ClickableDictationPill.swift (AI reason labels only), AppTests/GlobalDictationTests.swift and this report. No new dependencies or package-boundary changes.

Branch feature/milestone-31-integration; HEAD23caeca630b803fddc2cd007a5159dc9839b71cf unchanged. Nothing staged or committed/pushed/merged. Main and PR#1 untouched. Cumulative working tree includes older legitimate work:

```
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
?? Packages/WesleyFlowCore/Sources/Domain/DictationEnhancements.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/FocusedTextResolver.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AudioLevelMailbox.swift
?? Packages/WesleyFlowCore/Tests/WorkspaceTests/FocusedTextResolverTests.swift
```

**Acceptance:** global shortcut source routing and zero-presentation-request regression gate **PASSED**. Real keyboard delivery, editor compatibility and successful native AI replacement **PENDING PHYSICAL VERIFICATION**. No automatic preview fallback remains in36B.
