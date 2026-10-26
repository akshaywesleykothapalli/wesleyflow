# Repeated ChatGPT insertion diagnosis and recording guard

20 October 2026. Follow-up to PHASE1C2-CHATGPT-PASTE.md. User reported first insertion appeared, repeats failed; after clipboard-review guidance the user again reports no insertion.

## Confirmed evidence and unresolved cause

Wesley Flow's own UI now shows another ChatGPT UNCERTAIN attempt at3:42PM followed by DENIED attempts with “A previous paste needs clipboard review before another paste can be attempted.” This establishes another attempted, unverified paste followed by the pending-clipboard guard. It does not establish whether that attempt visibly inserted text, why ChatGPT failed to acknowledge it, or which AX representation differs. First-attempt success is human reported, not programmatically verified. Do not relabel uncertain history as inserted. No ChatGPT/Codex UI automation, conversation reading, native input simulation or clipboard-payload inspection was performed by the agent.

## Narrow changes

1. SystemOperations/TextInsertionService.swift retains the final bounded paste observation for transient diagnostic classification: unreadable field, original pre-paste text still reported, or different text result with expected/observed UTF-16 lengths. No actual text, substrings or hashes enter diagnostics. Exact full expected-text equality is still required for success. Bounds, original target binding, cancellation, no retry, clipboard ownership and explicit restoration are unchanged.
2. App/SystemWideDictationCoordinator.swift rejects automatic dictation before target capture or microphone startup while a clipboard backup is pending. It preserves the first diagnostic, shows the recovery action, and avoids more recordings/history entries that cannot be pasted. Manual in-app capture and explicitly armed app-opening commands remain independent of clipboard insertion. No clipboard is restored or discarded by the guard.
3. AppTests/GlobalDictationTests.swift adds three parameterized observation cases and one coordinator case: no private text in diagnostics; correct distinction of unreadable/unchanged/different results; exactly one paste, no restoration on uncertainty; no microphone/target/history work while pending; explicit recovery retains the original clipboard.

This is a diagnostic/UX correction, NOT a proven ChatGPT delivery fix. The paste mechanism itself is unchanged. Terminal remains manual-copy only; accessibility-tree activation remains declined. No AI, external dependency, new permission, prompt submission, source migration, commit or push.

## Actual verification

- focused: 178 cases / 128 functions, zero failures/skips, exit0.
- full: 802 cases / 355 functions, zero failures/skips, exit0.
- replay: 802 cases / 355 functions, zero failures/skips, exit0.
- Debug, Release and optimized Release test compilation: exit0.
- Final source SHA256 maps unchanged across all six checks and match the reviewed files. All20 tracked existing test files match HEAD. Nothing staged; git diff --check passed.
- Explicit Xcode-beta/Swift6.4/macOS27SDK, arm64 deployment26; macOS26/Swift6.2.3 runtime compatibility unverified.
- The initial focused attempt exited65 because the new coordinator test omitted its throws declaration. That declaration and a manually miscounted diagnostic expectation were corrected; the corrected focused and complete/replay runs passed. Failed evidence is retained under accepted-observation-focused.*. No existing test was weakened.

Commands below use DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer and SDKROOT unset. Exact timestamps, exits and source hashes are under Evidence/Phase1C2/accepted-observation-final-*.json/log/xcresult. Counts/diff/baselines/status are in Evidence/Phase1C2/Observation.

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-observation-final-focused.xcresult test -only-testing:WesleyFlowAppTests
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-observation-final-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-observation-final-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-observation-final-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-observation-final-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-observation-final-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```

## Running application and next diagnostic

The canonical Run app has NOT been replaced or terminated: it holds the pending clipboard backup in memory. Losing that backup by restarting is not a repair. The new diagnostic build is verified in DerivedData/Phase1C2-ClipboardRepair/Build/Products/Debug/Wesley Flow.app, but it is not promoted or live tested. Test builds may update launch registrations; only the exact canonical Run app path should be used until promotion is safe.

The user was asked for a different diagnostic, not another identical Fn retry: if their clipboard still contains the dictated phrase, manually invoke Edit → Paste in an empty ChatGPT prompt without sending or copying new content. This distinguishes whether manual paste works from whether Wesley Flow's posted shortcut succeeds. No transcript contents were requested. Await that result and safe explicit handling of the retained clipboard before replacing the running app. Automatic ChatGPT insertion remains UNRESOLVED. Do not claim completion or universal compatibility from these fixtures.

The user subsequently reports that the quoted dictated phrase appeared once and the next attempt did not. Their response does not unambiguously distinguish manual Edit → Paste from Fn. It is evidence of intermittent visible delivery, not reliable programmatic acknowledgement or repeated success. The canonical bundle hashes were verified unchanged and its exact path registered last, without terminating it or touching the clipboard.
