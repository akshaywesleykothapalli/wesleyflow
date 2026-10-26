# Dictation compatibility and app-opening commands

Follow-up: the user reported that WhatsApp insertion still failed. This report records the prior Commands build, not current live acceptance. See [the field-text correction](PHASE1C2-WHATSAPP-TEXT-COMPATIBILITY.md) for the subsequent diagnosis, source and verification.

20 October 2026. User-requested refinement of the outstanding Phase1C dictation implementation. No commit or push authorized. This report supplements, rather than replaces, previous evidence and limitations.

## Implemented behavior

- Dictation contains session status, cancellation, transcript/history review and insertion outcomes. Permission controls, Fn setup, formatting and appearance remain in Settings.
- Commands offers native opening of installed WhatsApp, the default browser, Settings, Finder, Notes and Music. Missing apps and launch failures are reported honestly. Opening a browser launches its application; Wesley Flow sends no URL or document to it. Apps may restore their own prior windows or network activity.
- Voice commands are explicitly one-shot: arm the next Fn gesture in Commands, hold Fn, say an exact supported “open …” phrase, then release. Subsequent gestures return to dictation. Unknown, compound, arbitrary-path, URL and shell-like requests are rejected. Ordinary dictated “open browser” remains text. No AI, message submission, shell, folders, scripts or arbitrary automation was added.
- Command recognition is deterministic and bounded to 128 UTF-8 bytes. Six typed intents are inert Domain values; they are not reusable authorizations. Only explicit button/armed-gesture dispatch reaches the injected native adapter. No command queue/replay or restored command arming exists.
- Native app opening lives in SystemOperations and uses NSWorkspace's asynchronous app-opening API. No process launcher or external dependency was added. The app composes the adapter through an injected MainActor closure. OS launch completion is not evidence that an app's internal UI is ready. Cancellation/quit prevents queued dispatch; it cannot undo an app launch already accepted by macOS. No hard cancellation/deadline guarantee for NSWorkspace completion is claimed.

## Third-party insertion: partial, requires live acceptance

The reported symptom is transcription succeeding while target capture says the focused text field is unavailable. Existing app-level and system-wide focus lookup, PID/launch/window/field identity, secure-field exclusion, full text/selection checks, bounded clipboard handling and observed-insertion verification are preserved.

The new fallback reads only existing focus/role/children metadata under the focused window: at most 64 queued nodes, depth 8, bounded child-array copies and a cooperative 250 ms search deadline with 50 ms per-element AX messaging timeout. It selects only a control that explicitly reports focus and a supported text role. Its owner PID must match the captured app before field contents are read. This is not an atomic OS transaction or a strict wall-clock bound across synchronous AX calls. Unavailable, truncated, changed or ambiguous-to-the-existing checks targets still fail closed; no blind paste was introduced.

Some browser/chat accessibility trees may remain unavailable. Automatic approval review twice rejected the proposed attribute-enabling edit; the user then explicitly declined AXManualAccessibility/AXEnhancedUserInterface activation. Neither command executed, and no activation implementation was added or alternate mechanism used to enable it. The separate Codex computer-use prohibition remains respected. Therefore WhatsApp/browser insertion is NOT verified and universal compatibility is NOT claimed. The user must retry actual Fn speech in an empty intended field; transcripts remain available for copy if the target remains unsupported.

## Source provenance

DailyOps README was read only as a product behavior reference: https://github.com/akshaywesleykothapalli/dailyops . No legacy application source, assets, clone, runtime or implementation was inspected/copied. New code is independent. Existing Apple Speech input and on-device/Mac-language policy are preserved; local AI remains disabled and memory-gated.

Changed in this refinement:
- App/DictationPreferences.swift: Commands destination.
- App/GlobalDictationView.swift: separated Commands and Dictation/Settings.
- App/SystemWideDictationCoordinator.swift: one-shot explicit command routing, injected native app opener, queued-dispatch quit fencing.
- AppTests/GlobalDictationTests.swift: command parsing/routing/failure/cancellation/quit and bounded focused-window regressions; existing sidebar expectation intentionally extended.
- Packages/WesleyFlowCore/Sources/Domain/AppOpeningCommand.swift: new six-intent data contract.
- Packages/WesleyFlowCore/Sources/SystemOperations/NativeAppOpening.swift: new native adapter.
- Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift: read-only focus fallback.
- AGENTS.md and Phase1C documents: current authorization, explicit activation denial and evidence.

NativeDictationShortcut, speech implementation, existing package dependencies/targets and Xcode project configuration were not changed by this refinement. All previous outstanding work is preserved. Generated builds, evidence and canonical Run bundle remain ignored; no staging/commit/remote operation occurs.

## Verification

Final verification is recorded under ignored Evidence/Phase1C2/accepted-commands-final-v2-*.json/log/xcresult, including complete argv, Xcode developer directory, timestamps, exit codes and source SHA-256 maps. Evidence/Phase1C2/Commands contains exact extracted counts, source review and canonical promotion evidence.

A preliminary test of the new fixture reused a previous callback before the second session had installed its callback, leaving the fixture waiting. That run was interrupted (exit75), preserved as accepted-commands-focused-final; it is not a passing result. Separate deterministic sessions and explicit joins corrected synchronization without weakening assertions or introducing sleeps. Earlier intermediate passing results are retained separately; only the final source-hash-matched runs establish acceptance.

A subsequent incremental build after introducing the new Domain source failed to discover AppOpeningCommand (exit65; accepted-commands-final-focused). A fresh, separate DerivedData/Phase1C2-CommandsFinal cache discovered the local package file without a source workaround or deletion. The failure evidence and old cache are preserved.

Final results (all source maps match the current source; zero failed/skipped test cases):

| Verification | Exit | Outcome |
| --- | --- | --- |
| focused | 0 | 136 cases / 102 functions |
| full | 0 | 760 cases / 329 functions |
| replay | 0 | 760 cases / 329 functions |
| debug | 0 | Passed |
| release | 0 | Passed |
| release-tests | 0 | Passed |

Xcode27 beta / Swift6.4 / macOS27 SDK, arm64 deployment26.0. No Swift compiler warnings/errors in final logs. AppIntents metadata extraction reports no framework dependency; the test host also reports existing macOS linkd/autoShortcut connection diagnostics. These are retained, not represented as test failures. Actual macOS26 runtime and Swift6.2.3 compatibility remain unverified.

The canonical Run/Wesley Flow.app matches the final Debug bundle file-for-file and passes codesign --verify --deep --strict. Its previous bundle is retained in Run/.before-commands. Registration cleanup initially encountered an already absent stale entry (-10814); replacement had succeeded. Registration was completed, accepting only that absent-entry condition, and canonical registration/signature checks passed. No generated bundles were deleted. All68 old own-repository app registrations were checked; canonical registered last. Details/exit codes: Evidence/Phase1C2/Commands/promotion.json.

Native UI verification opened the exact canonical path. Dictation visibly has session/history content and no setup/permission controls. Commands and Settings are present. Commands → Open Settings, Open WhatsApp and Open Browser each returned the corresponding “Opened …” completion status through the real native adapter. No messages, documents, URLs or prompts were submitted; target apps' private contents were not inspected. These app-launch checks do not verify text insertion or recognition.

Settings currently reports Accessibility needed and microphone/speech Not requested for the rebuilt ad-hoc app. Permission grants were not automated or bypassed. A human retry was requested through Settings and an empty third-party field. Live Fn/WhatsApp/browser insertion remains NOT TESTED for this new build until that response arrives. Existing history was preserved; no transcript contents were copied into evidence.

All20 tracked pre-existing test files match HEAD. No staging/commit/push/remote operation occurred. The working tree intentionally retains prior outstanding Phase1C work plus this refinement; see final-review.json for exact status. This is a verified Commands/UI implementation and a PARTIAL insertion-compatibility correction, not a claim of universal system-wide dictation acceptance.

Exact final verification commands (run with DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer and SDKROOT removed):

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-commands-final-v2-focused.xcresult test -only-testing:WesleyFlowAppTests
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-commands-final-v2-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-commands-final-v2-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-commands-final-v2-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-commands-final-v2-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-commands-final-v2-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```
