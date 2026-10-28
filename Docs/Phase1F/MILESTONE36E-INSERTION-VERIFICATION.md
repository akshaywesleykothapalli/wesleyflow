# Milestone 36E — Physical insertion verification repair

28 October 2026. **Confirmed verification defects repaired; automated gates PASSED. Physical36E acceptance UNVERIFIED.** The precise native AX response behind the user's TextEdit failure is still unknown. No live AI replacement success is claimed.

## Confirmed observation and exact classification path

The user reports that a complete dictated sentence visibly appeared in TextEdit, then immediate Option+1 displayed “Insertion uncertain” and performed no rewrite. Visible delivery is accepted as a user observation, not programmatic verification or replacement authority. Speech capture was not changed.

The exact HUD condition is SystemWideDictationCoordinator.compactAIStatus: provenanceReason is INSERTION_UNCERTAIN and the current message is the insertion-eligibility explanation. finish assigns that reason only when the actual receipt status is UNCERTAIN or DISPATCHED_UNVERIFIED. Such receipts cannot create rewrite anchors. They may arise from direct-update acknowledgement/readback failure, paste/typing readback deadline, cancellation or other unverified attempted delivery. The old short message alone does not reveal which native branch ran.

Two concrete code defects were found and exercised with deterministic fixtures:

1. TextInsertionService's direct AX branch performed one immediate observedText check and stopped. Unlike paste, it provided no read-only settling period. An original/stale or temporarily unavailable readback could therefore reject a visibly completed update. A delayed direct-readback fixture now verifies after the original single write.
2. Any error from replaceSelection immediately returned uncertainty without attempting readback. The native adapter collapsed a non-success AX mutation acknowledgement into the same generic unsupported error as a pre-dispatch capability failure. A mutation may be dispatched without a successful acknowledgement. The adapter now distinguishes that case; the broker observes the original bound editor and succeeds only if exact readback proves the expected result. A failed acknowledgement without matching readback remains uncertain. It never resends the write.

These are confirmed defects in the verification paths, **not proof that timing or a particular AX error caused the real TextEdit observation**. The36E instrumentation is needed to correlate the user's next physical attempt with an actual native stage/error. No historic text, clipboard payload, conversation, document or prompt was inspected to guess the cause.

## Source review and Accessibility findings

Reviewed AGENTS.md, reports36–36D, Domain insertion/receipt ports, native target capture/readers/identity and paste dispatch, broker deadlines/clipboard leases, coordinator formatting/receipt admission/expiry, both shortcuts and existing tests. Production still uses one shared coordinator. Actual formatted cleaned text, not raw speech or a history row, is inserted and supplied to the exact UTF-16 expectation.

The native target retains its original app/launch, window and editable AX element plus original text/selection. New readbackText validates that original identity before and after the AX read without mistakenly requiring the old pre-insertion text/caret. It does not retarget the current editor or inspect another app when identity changes. The old observedText read did not perform this full post-dispatch identity check.

Native reading supports bounded plain AXValue, attributed AXValue, and existing bounded AXStringForRange/AXAttributedStringForRange fallbacks driven by actual character-count responses. The attributed AXValue conversion was previously absent. Responses retain exact UTF-16; no whitespace, smart-quote, punctuation, newline or Unicode normalization is assumed safe. Invalid/partial/oversized results fail closed. Attributed conversion and range bounds are fixture-tested; actual plain/rich TextEdit support remains unverified.

AX errors are now preserved as numeric development metadata. APIDisabled maps to denied; invalidUIElement to changed target; cannotComplete/noValue to temporary unavailability; missing parameterized range support to range unavailable; unsupported attributes to unsupported; unusable range/data to invalid range. Native busy/denied errors are not labeled API-unsupported. Selected-range availability/result and numeric offsets are recorded without selected text. Native receipt admission still separately verifies writable range/selection, original unchanged text/context, caret and IME/composition capabilities.

A separate read-only metadata helper was attempted with no prompt, activation or text read. It returned helperAXTrusted=false, HelperNotAuthorized_NoTargetInspected. Evidence: Evidence/Milestone36E/ax-metadata-probe.json. That is the helper's permission, **not** Wesley Flow's permission and not a finding that TextEdit lacks AXValue. No actual TextEdit attribute values, counts or rich-text capabilities were obtained by that helper. The app-owned diagnostics will record those actual responses during the user's explicit test.

## Timing and effects

All routes now use typed, read-only post-effect observation. The existing operation budget is unchanged:1500ms from operation start, maximum32 observations,50ms cancellable spacing. Direct readback may settle when it still reports original text or is temporarily unavailable. A concrete different direct result fails conservatively; it is not silently normalized or assumed temporary. Paste/typing retain their bounded polling policy. No destination mutation occurs while waiting.

Cancellation and deadline are checked before and after observation. Exact expected text becoming readable only after the deadline is not success. Synchronous AX messaging has its existing per-call timeout and cannot be interrupted mid-call; this is a bounded observation design, not a hard real-time guarantee for an unresponsive external process.

An unconfirmed native AX write may be observed only after that mutation call was dispatched. Pre-dispatch validation/capability errors do not enter this path. No method retry, second AX write, fallback paste after uncertain direct update, Command+A, whole-document replacement or Return/Enter is introduced. Dispatch itself is never delivery evidence.

Clipboard snapshot/publication/ownership/recovery logic is preserved. Direct updates use no clipboard. Paste restores the original clipboard only after exact verification and only under the existing ownership check. Unverified or cancelled paste retains its RAM backup for explicit recovery; a newer clipboard is not overwritten. No elapsed-time acknowledgement or automatic recovery retry was added.

## Verification, receipts and lifetime

Successful readback must prove the fixed range derived from the original selection contains the exact formatted insertion and the complete expected original surrounding context is unchanged. Duplicate occurrences are never searched. Emoji, combining Unicode, punctuation, whitespace and multiline/surrounding content are tested without normalization. A matching span with changed surrounding content remains unverified.

Only INSERTED_VERIFIED can proceed to existing native anchor creation. Session/PID/text identity, no pending lease, enabled in-place mode and safe native range/caret/composition capabilities still apply. Insertion verification and eligibility are separate: a genuinely verified insertion may still have its replacement receipt withheld by a later capability check. No history presence grants authority.

The36D record remains bounded, in memory and120 seconds maximum. It survives normal speech/HUD teardown, expires actively, and is invalidated by new/conflicting sessions, source changes, consumption or close. Both Option+1 and Option+2 retrieve that same record. No stale receipt or cancelled late result can authorize replacement. Provider output must still pass the existing preservation contracts and final native checks; a changed replacement is attempted once.

## Development diagnostics

General → Text verification diagnostics now includes a bounded native + broker timeline, plus the existing provenance/model status and explicit SHORTCUT_RECEIPT_LOOKUP with operation, presence and session-correlation Boolean. No actual session identifier is displayed.

Timeline stages cover target acquisition, retained original element/selection, formatted length, clipboard lease where applicable, direct/paste/typing dispatch, initial vs settling readback, exact span/context classification and eligible receipt creation/withholding. Direct routes omit clipboard/paste stages because they do not use those mechanisms. Metadata contains only fixed codes, success/failure/unsupported/pending status, timing category, AX numeric errors, UTF-16 lengths/ranges and correlation outcomes. Native and broker buffers are capped32 entries; the visible summary selects bounded slices. No transcripts, clipboard contents, document titles, text hashes or model prompts are logged.

Codes include PASTE_DISPATCHED, DIRECT_UPDATE_DISPATCHED, TARGET_READBACK_SUPPORTED, TARGET_READBACK_UNSUPPORTED, TARGET_READBACK_DENIED, TARGET_READBACK_TEMPORARILY_UNAVAILABLE, TARGET_READBACK_TIMEOUT, TARGET_IDENTITY_CHANGED, INSERTION_RANGE_UNAVAILABLE, INSERTION_RANGE_INVALID, INSERTED_TEXT_MISMATCH, INSERTION_CONTEXT_MISMATCH, PRE_INSERTION_TEXT, INSERTION_VERIFIED, INSERTION_RECEIPT_CREATED and INSERTION_UNCERTAIN. AX_VALUE, AX_CHARACTER_COUNT, AX_SELECTED_RANGE and both range-reader codes preserve native response categories. A withheld eligible receipt is labeled separately, rather than falsely calling every verified-but-ineligible insertion uncertain.

The existing concise uncertainty HUD is retained; exact mismatch is never inferred from a missing AX value, unsupported range or permission denial. No automatic AI Preview opens, and no typing icon was added.

## Changes and preservation

Changed for36E:

- Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift: additive typed readback/diagnostic ports with defaults; no persisted history/receipt schema migration or authority initializer.
- Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift: one-shot dispatch followed by bounded typed verification and safe timeline.
- Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift: original-target readback, native error categories, attributed AXValue and unconfirmed-dispatch distinction.
- App/SystemWideDictationCoordinator.swift: metadata timeline/receipt lookup and36E marker, preserving routing/admission.
- App/WesleyFlowApp.swift: explicit manual-preview build marker only.
- AppTests/GlobalDictationTests.swift: controlled delayed/typed-error fixtures and26 additional cases.
- This report.

Byte-hash comparison to the captured36E baseline proves ClickableDictationPill, AppleDictationInput, NativeSpeechCallbacks, AudioLevelMailbox and Package.swift unchanged. Evidence: FinalVerified/preservation.json. No waveform, speech, hold-to-talk, tone, Prompt Engineering,4GiB floor, provider, preference, package/dependency or model changes. No AXManualAccessibility/AXEnhancedUserInterface activation, Terminal typing, Codex direct-write enablement, cloud AI, model download, training or generated-code execution.

## Actual verification

Xcode27 / Swift6.4 / SDK27 at /Applications/Xcode-beta.app/Contents/Developer; macOS26 arm64 deployment target. Actual host is MacBook Air arm64 running macOS27.2 (26B5112a). This is not a macOS26 runtime acceptance claim.

| Check | Actual result | Exit |
|---|---|---|
| focused | 346 expanded cases / 180 declarations; 0 failed, 0 skipped | 0 |
| full | 1215 expanded cases / 551 declarations; 0 failed, 0 skipped | 0 |
| replay | 1215 expanded cases / 551 declarations; 0 failed, 0 skipped | 0 |
| Debug build | passed | 0 |
| Release build | passed | 0 |
| Strict concurrency Release | SWIFT_STRICT_CONCURRENCY=complete passed | 0 |
| Debug bundle signature | codesign --verify --strict passed | 0 |
| Repository license/artifact/basic secret checks | passed | 0 |
| Git whitespace and unstaged index check | passed | 0 |

36D baseline1189 cases /541 declarations retained;26 cases /10 declarations added. Coverage includes delayed direct/paste readback, unsupported/denied/range/identity/secure failures, temporary availability, cancellation, timeout/late success rejection, exact UTF-16/surroundings, formatting mismatch, actual AX error classification, attributed conversion, both shortcuts receiving only a verified receipt, no automatic preview/clipboard change, and unconfirmed AX acknowledgement requiring actual readback. Existing HUD retention, user-edit rejection, no duplicate replacement, repeated pipeline, clipboard lease and stale-session tests remain enabled. Tests use disposable fixtures, not real TextEdit insertion; naming them TextEdit-like does not claim native acceptance.

Exact argv/exit/timestamps, logs, xcresult bundles and summaries: Evidence/Milestone36E/FinalVerified/{focused,full,replay,debug,release,concurrency}.json/.log. Full/replay exclude nothing. Common Xcode command uses -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone36E-VerifiedFinal -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2. Tests add -configuration Debug -parallel-testing-enabled NO -resultBundlePath <unique evidence bundle> test; focused selectors are in JSON. Builds add Debug/Release build; concurrency adds SWIFT_STRICT_CONCURRENCY=complete. All builds ran sequentially.

Source/binary hashes, individual hygiene commands/exit codes and preservation checks are alongside. Repository command: python3 Tools/CI/repository_checks.py. Signature: codesign --verify --strict <exact Debug bundle>. Git checks: git diff --check; git diff --cached --quiet. The repository checker reported 278 tracked files and 581 history objects, no issue categories.

All36E focused runs (Acceptance, Final, Verified, FinalVerified), full/replays and builds passed. Earlier focused runs preceded the final unconfirmed-dispatch and diagnostic-label refinements; final evidence covers the exact final source. No36E intermittent test failure was observed, suppressed or bypassed. Existing linkd.autoShortcut service and AppIntents metadata warnings remain nonblocking; they are not proof of physical shortcut delivery.

## Safe launch and physical matrix

No older Wesley Flow instance was running at launch. The exact verified Debug app was opened normally (open exit0) without replacing an installed app or terminating any process. Running executable identity is recorded in FinalVerified/safe-launch.json; it is DerivedData/Milestone36E-VerifiedFinal/Build/Products/Debug/Wesley Flow.app/Contents/MacOS/Wesley Flow.36E route/build markers and SHA256s identify the artifact.

The user answered “I’ll test after verification finishes.” No36E physical outcome has yet been reported.

| Physical check | Result |
|---|---|
| User's prior TextEdit visible full sentence | CONFIRMED user observation |
| Prior immediate Option+1 uncertainty/no rewrite | CONFIRMED user observation |
|36E A: plain TextEdit readback, exact span and eligible receipt | UNVERIFIED |
|36E B: Option+1 actual replacement or separate memory rejection | UNVERIFIED |
|36E C: fresh Option+2 finds the same eligible record | UNVERIFIED |
|36E D: edited word safely rejected | UNVERIFIED |
|36E E: nearby unrelated content preserved | UNVERIFIED |
| Rich-text TextEdit capabilities/readback | UNVERIFIED |
| Physical clipboard/focus/no-submission behavior | UNVERIFIED |

Use a blank plain-text TextEdit document and a fresh synthetic dictation. Confirm visible insertion, then immediately press Option+1 without moving the caret or switching apps. Inspect General only afterward: opening it first changes the native focus context and invalidates eligibility. Report only the diagnostic codes/metadata, concise status and whether actual destination text changed, never private content. Use a separate fresh dictation for Option+2, an edited-word rejection, and nearby-content checks. If memory admission blocks generation, preserve text and stop without retrying. No model generation was run by this task; deterministic fixture model outcomes are not live results.

## Remaining limitations and stop status

The exact physical uncertain-insertion root cause remains UNKNOWN pending the36E native trace. Timing/unconfirmed acknowledgements are repaired confirmed mechanisms, not invented physical findings. TextEdit plain/rich AX capabilities, programmatically verified real insertion and actual in-place rewrite remain unverified. Strict IME, writable-range and native-identity gates may withhold eligibility even after insertion verifies. AX mutation is not atomic compare-and-swap; dispatch uncertainty never becomes assumed success or automatic retry. Codex direct replacement remains excluded, Terminal manual-copy only, and accessibility-tree activation remains disabled.

No settings were enabled for the user. Actual model availability/admission/quality remain untested here; the4GiB floor is unchanged. No production-readiness or universal editor support claim is made.

Branch feature/milestone-31-integration; HEAD23caeca630b803fddc2cd007a5159dc9839b71cf unchanged. All prior uncommitted work preserved. No staging, commit, push, rebase, merge, remote mutation or PR#1 state change. This local task did not re-query GitHub; PR#1 was left untouched. Stop after36E implementation/verification; physical acceptance awaits user results.

Final working tree (includes all pre-existing changes):

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
?? Packages/WesleyFlowCore/Sources/Domain/DictationEnhancements.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationVerification.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/DictationSpanVerification.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/FocusedTextResolver.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AudioLevelMailbox.swift
?? Packages/WesleyFlowCore/Tests/WorkspaceTests/FocusedTextResolverTests.swift
```
