# Milestone 36C — In-place text verification

27 October 2026. Confirmed validation/message defects repaired; final automated verification **PASSED**. Actual successful TextEdit AI replacement remains **UNVERIFIED**. The exact AX clause behind the user's earlier physical failure is **not yet established**. No commit, push, merge, model download or live inference was performed.

## Observed result and investigation limits

User-observed36B results: disabled Option+1/2 PASS; no unwanted preview PASS; Option+2 replacement in TextEdit NOT PASSED. The user saw “Text changed” while visible dictated text remained unchanged. This report does not convert that observation into a successful replacement or assume the user edited the text.

A read-only capability helper was attempted without requesting permission. It reported helperAXTrusted=false and aborted before inspecting TextEdit attributes. That helper's permission is **not** Wesley Flow's own Accessibility permission; no app permission failure is inferred from it. No actual transcript, original document, clipboard value, prompt or content hash was printed/read by that helper. The historical native validation branch cannot be reconstructed from the old app's generic message alone.

Initial running app: PID83008 under ~/Library/Developer/Xcode/DerivedData/WesleyFlow-cccpncdspkgnnbgnvimlzzhfmozl/Build/Products/Debug/Wesley Flow.app. It was preserved. New development metadata will identify the exact stage during the user-operated reproduction.

## Confirmed defects and exact failing validations

The former NativeDictationRewriteAnchor.checkedDocument used TextTargetError.changed for three large groups:

1. Consumption, cancellation, expiry, activation epoch, Accessibility authorization, secure input and application identity.
2. Focused window/field resolution, element identity, missing AXSubrole and editability.
3. Settable attributes, missing bounded text, document hash, fixed-range extraction, inserted text and collapsed end-caret comparison.

App rewriteSourceExplanation then mapped these to a combined changed/expired sentence; compactAIStatus displayed a changed-text label. Thus a missing subrole, unreadable AX text, invalid range or changed focus was indistinguishable from an actual source mismatch. **This classification defect is confirmed from production source.**

Provenance is created immediately after verified insertion and validates during anchor initialization. A failure there was saved in rewriteEligibility; a later Option+2 could display it with **no anchor and no generation**, even if the user had not edited anything. The message did not prove that validation first failed at shortcut time or that AI ran.

The previous caret check accepted only a collapsed caret at the inserted span's end. It rejected the equally precise state where an editor leaves the proven inserted span selected. This rejection is reproducibly covered by the shared range/caret regression. It is **not claimed to be what TextEdit reported in the user's earlier attempt**, because that AX observation is unavailable.

A second representation defect was reproduced: Swift String equality accepts canonically equivalent strings with different UTF-16 lengths. Initial insertion could therefore appear verified while a later code-unit range did not describe that representation. The new test explicitly demonstrates equal Swift strings but different UTF-16 encodings. This is a confirmed latent verification inconsistency, **not a claim that normalization caused the actual reported TextEdit failure**.

## Repair and provenance

New internal DictationInsertionExpectation is shared by TextInsertionService's direct/paste/Unicode completion checks and native rewrite-anchor creation. It derives the one fixed range from the original authorized selection, builds the expected formatted insertion result, reads the actual bounded post-insertion observation, validates the exact span and complete context, and only then admits provenance. Native anchor originalText is the actual proven slice, not raw speech or a history row. The insertion receipt must already be verified in the owning coordinator; session/PID and exact UTF-16 text are checked before storing the anchor.

Raw-versus-formatted mismatch was investigated and **not found**: finish formats raw speech into cleaned text and passes that same text to insertion and anchor creation. A new regression preserves raw “  check   the button  ” in history while proving generation receives the actual “check the button” insertion. Immutable raw/cleaned history remains unchanged by AI.

Comparison policy is **exact UTF-16**, explicitly without normalization. Spaces, curly/straight punctuation, CRLF/LF and NFC/NFD differences are not silently rewritten or normalized. Canonical-equivalent but code-unit-different initial observations now remain unverified instead of granting a range capability. Invalid surrogate offsets and overflow/out-of-bounds ranges fail closed. Combining Unicode, emoji/ZWJ sequences, multiline content and existing prefix/suffix text are covered. There is no document-wide search or first-match selection.

Before rewriting, native checks still require original app/launch/window/element, Accessibility permission, secure-input exclusion, editability, writable selected-text/range APIs, readable zero-length marked-text state, unchanged whole-context hash, exact own span, freshness and valid selection. The caret may be at the proven span's end **or exactly select that same proven span**. Arbitrary caret movement, partial selection or another field is rejected. Post-selection precommit requires the exact selected span. Neither user edits nor ambiguous text are accepted.

Missing subrole/IME/writability remains unsupported; those conditions were **reclassified, not bypassed**. Own-span differences yield textMismatch; nearby context differences yield contextChanged. Missing text/range, focus/target changes, expiry and caret movement have distinct types. The final commit preserves a typed failure if the target changes after generation, rather than relabeling AX failure as AI unavailability. Dispatch uncertainty remains explicit and is never retried.

## HUD and development diagnostics

“Text changed” is emitted only for typed **textMismatch**, after an exact comparison at the known range. Other outcomes include Cannot verify text, Text location missing, Editor inaccessible, Target changed, Dictation expired, Caret moved, Context changed, Editor unsupported and the existing accurate model/resource outcomes. Zero automatic preview routing is preserved for every condition.

Development-only diagnostics appear under **General → Shortcuts**, below the existing Registration row. They contain only phase/stage enums, matched/different/unavailable/invalid results, expected/current UTF-16 lengths, comparison policy exactUTF16, model status (notRequested/requested/outcome) and replacement attempted/status. Native arrays are bounded32 entries; the visible summary takes the last12 stage entries. No text, title, prompt, clipboard payload or recoverable content hash is logged. Static source/binary SHA256s in build evidence are not user-content hashes.

Expected diagnostic examples are afterInsertion / beforeGeneration / afterGeneration / replacement plus failure=textUnavailable, invalidRange, targetChanged, caretChanged, unsupportedEditor or textMismatch. A pre-anchor failure is visible as afterInsertion with model=notRequested. This permits the next actual TextEdit test to identify the native rejection rather than guessing its cause.

The compact pill/waveform source, AVAudioEngine/speech adapter, atomic RMS transfer, smoothing and Apple model provider are byte-hash unchanged. No UI redesign, typing icon, automatic editor, cloud fallback, download, synthetic Enter or message submission was introduced. The clipboard service changed only its shared completion comparison; lease ownership/restoration, bounded polling, deadlines and no-retry rules are preserved.

## Actual verification

Xcode27.0 / Swift6.4 / SDK27.0, macOS26.0 arm64 target. Actual host macOS27.2; this is not a macOS26 runtime acceptance claim.

| Check | Actual result | Exit |
|---|---|---|
| focused | 219 expanded cases / 107 declarations; 0 failed, 0 skipped | 0 |
| full | 1171 expanded cases / 532 declarations; 0 failed, 0 skipped | 0 |
| replay | 1171 expanded cases / 532 declarations; 0 failed, 0 skipped | 0 |
| debug | passed | 0 |
| release | passed | 0 |
| concurrency | passed | 0 |
| Debug bundle codesign | passed | 0 |
| Changed/new secret/artifact scan | passed; contents not printed | 0 |
| Git diff whitespace | passed | 0 |

Baseline1,137/523 retained;34 expanded cases /9 declarations added, yielding **1,171/532**. Coverage includes exact fresh synthetic text insertion, raw/formatted distinction, trailing whitespace, curly punctuation, CRLF/LF, NFC/NFD, emoji/combining text, UTF-16 offsets, surroundings/duplicate strings, actual text/context changes, invalid/missing ranges/caret, absent editor/composition attributes, all typed failures, no premature canonical-equality verification and final-preflight races. Existing delayed paste, stale-session, cancellation, memory-blocked, popup-spy, clipboard/no-key and recovery tests remain enabled. The Phase1A late-success timeout regression passed in full/replay; no new recovery flakiness occurred. Fixtures model TextEdit-compatible selection states, not a native TextEdit physical pass.

### Failed verification retained

One intermediate focused attempt exited65 at compilation: the app reported the new lastValidationFailure member absent. The freshly compiled PackageFrameworks/Domain.framework module contained it, while an older generated flat Debug/Domain.swiftmodule did not. Evidence/Milestone36C/incremental-module-mismatch.json preserves that difference; FinalVerified/focused preserves the failed log/result. The app's module search included the older variant. No test assertion failed in that run because tests did not execute.

Final verification used fresh **DerivedData/Milestone36C-Verified**, retaining the failed cache/evidence and all source. All final focused/full/replay/builds above passed there. No source guard, test or checking mode was removed to obtain success. Earlier successful runs under Verified/Final are historical; the Acceptance results above are authoritative. Nonblocking AppIntents/linkd warnings remain in logs and are not physical hotkey evidence.

Exact argv/exit/timestamp records: Evidence/Milestone36C/Acceptance/{focused,full,replay,debug,release,concurrency}.json and .log, native .xcresult bundles and summaries. All runs sequential. Commands use:

```
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone36C-Verified -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 ...
```

Full/replay append `-configuration Debug -parallel-testing-enabled NO -resultBundlePath <unique path> test` without exclusions. Focused JSON records selectors including DictationSpanVerificationTests. Builds use Debug/Release build; concurrency adds SWIFT_STRICT_CONCURRENCY=complete. New Domain/SystemOperations files have concrete responsibilities, auto-included through the existing package targets; no package dependency graph change or external dependency.

## Physical acceptance and correct build

The user agreed to test after verification. No new36C physical result is supplied.

| Test |36C result |
|---|---|
| Fresh unedited TextEdit insertion + Option+2 | UNVERIFIED |
| Deliberately edit one word: safe rejection | UNVERIFIED |
| Prefix/suffix content around own insertion | UNVERIFIED |
| Actual on-device generation and replacement | UNVERIFIED |
| Native focus/clipboard/no-submission outcome | UNVERIFIED |

Use **only** `DerivedData/Milestone36C-Verified/Build/Products/Debug/Wesley Flow.app` for acceptance. The shorter Milestone36C folder contains intermediate builds and is not the final acceptance artifact. Fingerprints/signature and bundle metadata are in Acceptance/test-build-identity.json. Version remains0.1.0/build1; Smart Formatting's mode description and optional explicit-preview title identify36C, but the exact executable path distinguishes final/intermediate builds.

At final process check, PID83008 was still running from the default Xcode DerivedData path. Its active dictation/clipboard state was not inspected; it was not quit, replaced or force-terminated. Therefore the new app was **not launched alongside it**. Safely quit the older app normally only when idle and no clipboard recovery warning remains, then open the final bundle above. Saved relevant flags were all true (inPlaceAIRewrite, offlineAIRewriting, promptEngineeringEnabled, previewShortcutsEnabled); none was changed by this task.

In TextEdit, create a blank **plain-text** document. Dictate a fresh short sentence, wait for verified insertion, do not edit or move the caret, then press Option+2 within120 seconds. Either verified replacement or an accurate safe failure is the real observation; never submit. On failure, open General afterward and report only the metadata diagnostic line and status sentence, not transcript or clipboard contents. Then test a separate new dictation with one word edited; it must reject. For surrounding-text testing, create prefix/suffix **before** dictating into the middle; editing context afterward deliberately makes the anchor stale. No unrelated span may change.

## Remaining limitations

The precise earlier TextEdit AX rejection is still unconfirmed. The new build may legitimately report unsupported subrole/IME/range data; missing capability is not assumed safe. The caret-selection correction and stronger representation checks are verified in deterministic production-helper tests, not a proven native replacement success. No actual model run/resource sample was attempted; the existing4GiB floor remains, and live quality/readiness may still block generation.

AX operations remain non-atomic. Preflight rejection leaves text untouched, but a failure after selection/write dispatch can already have changed selection/text and must be treated as uncertain. No retry, rollback, full-document rewrite or relaxed permission/IME check was added. Terminal remains manual-copy only; existing Codex direct-write exclusion remains. Native editor compatibility requires physical verification. Immutable history and existing safety boundaries are preserved.

## Files and Git

36C changes: new Domain/DictationVerification.swift; new SystemOperations/DictationSpanVerification.swift; diagnostic defaults in DictationEnhancements.swift; native provenance/checks in NativeTextInsertion.swift; shared completion comparison in TextInsertionService.swift; coordinator reason/metadata plumbing; one DEBUG-only diagnostic caption in GlobalDictationView.swift;36C explicit-preview identity label; existing AppTests/GlobalDictationTests.swift and WorkspaceTests/FocusedTextResolverTests.swift; this report.

Branch feature/milestone-31-integration, HEAD23caeca630b803fddc2cd007a5159dc9839b71cf unchanged. Nothing staged/committed/pushed/merged. Main and PR#1 unchanged. All prior uncommitted work retained. Cumulative status:

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
?? Packages/WesleyFlowCore/Sources/Domain/DictationEnhancements.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationVerification.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/DictationSpanVerification.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/FocusedTextResolver.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AudioLevelMailbox.swift
?? Packages/WesleyFlowCore/Tests/WorkspaceTests/FocusedTextResolverTests.swift
```

**Status:** confirmed classification/representation/caret defects repaired and automated gates passed. Actual TextEdit in-place AI replacement and the exact prior physical AX failure **remain pending user verification**.
