# Phase1C.2 — Hold-Fn interaction correction

The user's latest instruction supersedes the earlier click-to-toggle/always-visible pill interaction. This is a correction within1C.2, not a new milestone. No staging, commit, push or AI activation is authorized.

## Delivered behavior

- Hold Fn/Globe in the intended field to start dictation; release to finalize and request insertion into the original captured field.
- The84×32 status pill is hidden at launch/idle and after success/error/cancellation. It appears only during an Fn-originated preparing/recording/finalizing/inserting session; it is not a microphone start/stop button. Right-click cancellation remains.
- The main screen explains hold/release and shows Fn readiness. There is no main microphone capture button or clickable-paste expectation. Menu/settings provide enable/disable; a manual-copy fallback remains in the menu when Accessibility is unavailable.
- Fn intent persists. On launch/activation, monitoring resumes only if already authorized and preferences are valid. No microphone recording starts on launch. Explicit disable survives restart, and quitting does not silently reset an enabled preference. Revoked authorization stops monitoring and cancels capture; reauthorization can restore intended monitoring on activation. Unknown/corrupt preferences remain preserved and do not silently enable monitoring.
- Older version1 preferences decode with the newly requested Fn behavior enabled while preserving history, cleanup, waveform and appearance choices. The waveform visibility preference now means visibility during Fn dictation, never permanent idle visibility.
- Repeated downs/ups are generation fenced, release during preparation cancels, one held gesture creates one session and one finalized insertion. Existing speech engines, Mac language, permission and memory policies remain.

First-time microphone/speech authorization can interrupt a hold gesture. Approve native prompts, then hold Fn again. If macOS assigns Globe to emoji/system Dictation, change Keyboard → Press Globe key to → Do Nothing manually; the app does not modify that system preference.

## Investigated insertion report

The user reported successful transcription in Wesley Flow but an orange warning and no insertion into a Codex question-answer field. Read-only inspection of this app's last stored receipt metadata found UNSUPPORTED_TARGET, reason unsupported, attempted=false. Transcript contents were not printed or exported. This confirms failure during target capture, before any AX write or paste; it does not identify the missing native attribute.

Codex rejected automated inspection of its own app for safety reasons. That restriction was respected: no alternative AX script, browser automation, CLI accessibility dump or keyboard injection was used to inspect/interact with Codex. Accordingly, this refinement does **not** claim that insertion into Codex's question field has been fixed or verified.

Native capture now exposes a sanitized in-memory stage explanation: authorization, secure input, original app/window/focused control, text role, editable interface, readable bounded value, or readable caret/selection. No target text or selection contents appear in that explanation. The coordinator retains the user's transcript for manual copy and shows the actual target failure in the main window; error states no longer leave a permanent orange pill. A speech failure takes precedence over an earlier target warning. History details explain typed insertion reasons, including unsupported clipboard formats, changed targets and uncertain effects.

Original app PID/launch/window/element, selection/text checks, secure-input rejection, editability, bounded clipboard ownership/restoration and observable-change verification remain intact. No blind paste or weakened target validation was introduced to make an unsupported field appear functional. Live support needs a human Fn test in the actual field; the sanitized failure message can identify the remaining native-interface limitation.

## Verification

<!-- RESULTS -->
| Check | Expanded cases / functions | Exit | Evidence stem |
|---|---|---:|---|
| focused | 110 / 89;0failed,0skipped | 0 | `accepted-fn-final-focused` |
| full | 734 / 316;0failed,0skipped | 0 | `accepted-fn-final-full` |
| replay | 734 / 316;0failed,0skipped | 0 | `accepted-fn-final-replay` |
| debug | BUILD SUCCEEDED | 0 | `accepted-fn-final-debug` |
| release | BUILD SUCCEEDED | 0 | `accepted-fn-final-release` |
| optimized-release-tests | TEST BUILD SUCCEEDED | 0 | `accepted-fn-final-optimized-release-tests` |

The six initial Fn-correction runs used identical source hashes and source_unchanged=true; no Swift compiler warning/error remained. These734-case results describe the initial Fn revision and are superseded by the read-only compatibility results below. AppIntents extraction/linkd messages and occasional CoreData temporary-fixture directory messages remain in logs; no test failure accompanied them. Xcode27 beta, Swift6.4, macOS27SDK, macOS26 arm64 deployment, Swift6 strict concurrency. Actual macOS26/Swift6.2.3 compatibility remains unverified.

Exact commands, run from the repository with SDKROOT removed and DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer:

```text
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-FnRefinement -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-fn-final-focused.xcresult test -only-testing:WesleyFlowAppTests
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-FnRefinement -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-fn-final-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-FnRefinement -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-fn-final-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-FnRefinement -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-fn-final-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-FnRefinement -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-fn-final-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-FnRefinement-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-fn-final-optimized-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```

JSON/log/xcresult evidence and actual counts are under ignored Evidence/Phase1C2, with the refinement baseline/final review under FnRefinement. The unchanged package manifest retains the previously verified module dependency graph and no external packages.
<!-- END RESULTS -->

New deterministic tests cover hold/release target capture and exactly-one insertion, duplicate signals, finalization/pill visibility, preparation cancellation/late callbacks, permission-gated restoration without prompts, revocation, explicit disable and quit preference preservation, old-settings migration, unsupported-field explanation, speech-error precedence and no pill for manual capture. Existing683 pre1C.2 cases and the preceding1C.2 tests are preserved. Fixtures do not enable real key monitors, record speech, post keystrokes or write the general clipboard. Hosted-app lifecycle restoration is guarded out of tests.

The first optimized build exposed a weak diagnostic callback attached to a temporary compatibility capture object. Its synchronous nonescaping initializer callback now holds the capture strongly for that call only; it is not stored, so no cycle or new lock is introduced. The warning and intermediate logs are retained; final verification uses the corrected source.

## Live status and boundaries

<!-- LIVE -->
Canonical Run/Wesley Flow.app was replaced only after verifying the previous generated copy still matched its known source. The prior bundle was preserved as ignored Run/.before-fn. The new staged copy matched every source file hash and passed codesign --verify --deep --strict. Only the canonical old running instance was stopped,59 obsolete repository build registrations were removed without deleting those builds, and the updated canonical path was registered last. Evidence: FnRefinement/canonical-update.json.

Native UI opening the exact canonical path confirmed the new “Hold Fn / Globe … release to insert” guidance and the absence of a main microphone capture button. This rebuilt ad-hoc app reports Accessibility needed and microphone/speech Not requested; monitoring correctly does not auto-enable without the new build's native grant. The user was asked to perform setup once, then hold/release Fn inside the actual question field and report the precise new status if insertion fails. No consent was granted by automation. The user subsequently confirmed physical hold-Fn capture and insertion in System Settings/system apps. They reported failure in WhatsApp and browser editors. Wesley Flow's own status showed missing focused-field and missing readable-value failures at different attempts. This is partial native acceptance, not support for every editor. See the compatibility follow-up below; newer builds still require their own live acceptance.
<!-- END LIVE -->

Real global Fn delivery, original-field insertion in Codex, clipboard round trips, permission-triggered Quit/Reopen, cross-app switching and all other native-editor acceptance cases remain UNVERIFIED unless separately confirmed below. Prior passing fixtures do not prove those behaviors. No AI inference, downloads, cloud speech, prompt submission, agents, new phase or unrelated repository changes occurred.

## Git and preservation

All earlier uncommitted work is preserved. Baseline hashes and copies are in ignored Evidence/Phase1C2/FnRefinement/Before and baseline.json. This correction changes only the dictation coordinator/preferences/pill/UI/lifecycle, sanitized capture diagnostic port/native implementation, tests and documentation. The original NativeDictationShortcut monitor and all pre1C.2 speech/task/provider/test code remain unchanged from the preceding checkpoint.

<!-- GIT -->
Branch main; HEAD 0a3e91c731a716945853a6b84bcfaaf6d9e672d3 unchanged. 32 changed/new files remain unstaged/uncommitted. Git diff --check exited0; staged paths empty. Original tests retain their baseline source; the package manifest/dependency graph is unchanged. Current readonly-final-review.json records all source matches, diagnostics and absence of activation code. Run/Evidence/DerivedData remain ignored. No commit, push, remote creation, AI execution or later phase.

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
?? Docs/Phase1C/PHASE1C1-COMPLETION.md
?? Docs/Phase1C/PHASE1C2-FN-REFINEMENT.md
?? Docs/Phase1C/PHASE1C2-GLOBAL-DICTATION.md
?? Packages/WesleyFlowCore/Sources/Domain/Dictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/LocalPromptRewriter.swift
?? Packages/WesleyFlowCore/Sources/Persistence/SwiftDataDictationHistoryStore.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AppleDictationInput.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AppleSpeechConfiguration.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/NativeSpeechCallbacks.swift
```
<!-- END GIT -->

## Read-only third-party compatibility follow-up

The user confirmed Fn and System Settings insertion, while WhatsApp and browser editors remained unsuccessful. Two read-only compatibility paths were implemented independently of any accessibility-tree activation:

1. Read application-scoped focused UI first; if absent, use AXUIElementCreateSystemWide focused UI. AXUIElementGetPid must match the originally captured process before accepting either observation. Missing/foreign/unknown owners fail closed; the app never substitutes whichever unrelated field is now active. The original launch/window/element/selection/value checks remain.
2. Read AXValue first. If absent, use bounded AXNumberOfCharacters plus AXStringForRange through AXUIElementCopyParameterizedAttributeValue. Require the entire reported UTF-16 character count and the existing byte limits; reject partial, unsupported, oversized or inconsistent results. Apply this same full-field reader to verification. Never truncate a larger field to manufacture an expected result. These APIs are present in the installed macOS SDK's AXAttributeConstants.h/AXUIElement.h and compile in the actual builds.

New tests cover valid/absent/foreign focus observations, not redirecting an existing focus observation, direct values, complete range text, Unicode/UTF-16, byte limits, negative/excessive counts, unsupported ranges, partial responses and refusing truncated replacement values. No browser DOM inspection, third-party configuration change, broad key injection or blind paste was added.

A separate proposal to request browser/Electron accessibility-tree activation was rejected by automatic approval review before the edit command executed. It remains NOT IMPLEMENTED pending explicit approval. The read-only alternatives are separate permitted operations; they do not perform that rejected change. See [the exact activation proposal and risks](ACCESSIBILITY-ACTIVATION-PROPOSAL.md). Codex's own-tool inspection prohibition was also respected. No activation attribute identifier exists in executable source.

### Latest compatibility verification

<!-- COMPAT-RESULTS -->
| Check | Result | Exit | Evidence stem |
|---|---|---:|---|
| focused | 112 expanded cases /91 functions;0failed,0skipped | 0 | `accepted-readonly-text-focused` |
| full | 736 expanded cases /318 functions;0failed,0skipped | 0 | `accepted-readonly-text-full` |
| replay | 736 expanded cases /318 functions;0failed,0skipped | 0 | `accepted-readonly-text-replay` |
| debug | Succeeded | 0 | `accepted-readonly-text-debug` |
| release | Succeeded | 0 | `accepted-readonly-text-release` |
| optimized-release-tests | Succeeded | 0 | `accepted-readonly-text-optimized-release-tests` |

All six current runs use identical source hashes and source_unchanged=true. Final sources still match; no Swift warning/error remains. Compiler/platform settings are unchanged. These736/318 results supersede the initial734/316 Fn results above. Earlier735/317 focus-only results are also retained. New coverage adds the bounded string-for-range cases. Exact arguments, timestamps and source hashes are in each JSON record; logs/xcresults are retained.

```text
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-Compatibility -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-readonly-text-focused.xcresult test -only-testing:WesleyFlowAppTests
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-Compatibility -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-readonly-text-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-Compatibility -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-readonly-text-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-Compatibility -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-readonly-text-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-Compatibility -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-readonly-text-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-Compatibility-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-readonly-text-optimized-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```
<!-- END COMPAT-RESULTS -->

### Latest canonical bundle and live acceptance

<!-- COMPAT-LIVE -->
The current canonical Run/Wesley Flow.app now matches the tested read-only compatibility build in DerivedData/Phase1C2-Compatibility. The previous working Fn bundle was preserved as ignored Run/.before-readonly. Every copied file hash matched and codesign --verify --deep --strict exited0. Only the exact old canonical executable was terminated and its exit confirmed before replacement; obsolete repository build registrations were removed and the current bundle registered last. Evidence: FnRefinement/readonly-canonical-update.json.

Native UI opening the exact canonical path confirmed the Fn-only instructions and setup button. This rebuilt development app currently reports Accessibility needed and microphone/speech Not requested, so the user must reauthorize this code-signed revision through native setup before another physical test. No grant or privacy setting was changed by automation. The new read-only fallback remains live-UNVERIFIED in WhatsApp/browser/Codex. The earlier confirmed System Settings/Fn behavior and stored INSERTED receipt are evidence for the previous Fn revision, not a blanket pass for the new compatibility paths.

The pending activation proposal is concrete and separate; automatic review rejected changing other apps' accessibility behavior without explicit authorization for that exact cross-app change. It is absent from executable source, confirmed by the final review. No alternate mechanism performed the rejected activation. The only implemented changes here are standard read-only focus/text observations under existing consent.
<!-- END COMPAT-LIVE -->

Third-party insertion after these read-only changes remains UNVERIFIED until user testing. Existing native System Settings acceptance applies to the previous Fn build. Accessibility activation may still be needed for apps whose accessibility tree remains inactive; it has not been authorized or enabled. No universal browser/WhatsApp/Codex support claim is made.
