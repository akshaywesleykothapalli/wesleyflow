# WhatsApp field-text compatibility correction

20 October 2026. Follow-up to the user's failed WhatsApp insertion test of the Commands/refined Dictation build. Native insertion remains a human acceptance gate; fixture success is not live WhatsApp verification.

## Observed failure and confirmed gap

Wesley Flow's own Settings showed microphone/speech/Accessibility allowed and Fn monitoring enabled. Its latest Dictation error was “The field does not expose readable text within the supported size limit.” That means the recorded attempt passed permission, focused-window/field, supported-role and editability checks, then stopped at full text reading. No paste was attempted on this path. No WhatsApp messages or app contents were inspected through automation, and transcript contents were not copied into evidence.

The installed implementation rejected a field when AXValue was absent and AXNumberOfCharacters explicitly returned zero unless an additional zero-length range request returned a string. That is a reproducible compatibility gap: successful zero character metadata already establishes an empty field. The exact zero-count behavior of the user's WhatsApp version has NOT been established; it is a tested hypothesis for this failure, not a proven WhatsApp-specific root cause.

## Narrow correction

Only NativeTextInsertion.swift and additive GlobalDictationTests.swift regressions changed in source/tests:

- An explicit, valid zero character count now yields empty text without requiring a zero-length string-range response. Missing metadata never implies an empty field.
- Full range text can use Apple's CFAttributedString representation when plain AXStringForRange is unavailable. Attributes are not retained; only plain text proceeds through the existing checks.
- Character counts must be actual numeric values convertible to an exact integer. Boolean, fractional, infinite, missing, negative and oversized values cannot establish emptiness.
- Both range paths must return exactly the reported UTF-16 length and remain inside the byte limit. Partial primary results are rejected, not hidden by another fallback. Existing oversized primary values never trigger a truncated substitute.
- Sanitized status now distinguishes missing character count, unavailable range readers, incomplete text and size-limit failures. It contains no field text, contact/message contents or arbitrary provider errors.

Apple's API contract: [kAXAttributedStringForRangeParameterizedAttribute](https://developer.apple.com/documentation/applicationservices/kaxattributedstringforrangeparameterizedattribute). This documents the platform representation, not conformance of an installed WhatsApp version.

No activation attributes, browser flags, plugins, app preferences, TCC database changes, permission bypass or blind paste were introduced. The user's explicit refusal of AXManualAccessibility/AXEnhancedUserInterface activation remains in force. Original app/window/launch/field ownership, secure-input, caret/selection, cancellation, clipboard ownership/restoration and observed-insertion checks remain. Neither settings, Commands, speech engines, history policy, AI gates, module dependencies nor existing tests were removed or weakened.

## Verification and acceptance

Final source-matched runs: Evidence/Phase1C2/accepted-whatsapp-final-*.json/log/xcresult. Exact argv, developer directory, timestamps, exit codes and SHA-256 source maps are recorded there. Before files/canonical hashes, reviewed diff, test summaries, final checks and promotion evidence are under Evidence/Phase1C2/WhatsAppText (ignored).

Final results, all exit0 and source-hash matched:

| Verification | Result |
| --- | --- |
| Focused app tests | 143 cases / 107 functions passed |
| Full suite | 767 cases / 334 functions passed |
| Independent replay | 767 cases / 334 functions passed |
| Debug build | Passed |
| Release build | Passed |
| Optimized Release test compilation | Passed |

No failed/skipped cases or Swift compiler warnings/errors. Existing AppIntents metadata-skip and macOS linkd connection messages remain in logs. All20 tracked pre-existing test files match HEAD. Existing Commands and prior tests remain intact. Toolchain: explicit Xcode-beta developer directory, Swift6.4, macOS27SDK and arm64 deployment26. Actual macOS26 runtime/Swift6.2.3 remain unverified.

The canonical Run/Wesley Flow.app was updated only after verification, matches the final Debug bundle and passes deep/strict code-sign verification. Previous bundle preserved in Run/.before-whatsapp-text. Stale own-app registrations were removed and canonical registered last, accepting only known absent-entry -10814 responses during cleanup. No generated bundles or user history were deleted. Native UI confirmed the new app launched and retained the sidebar/history. macOS marks this changed ad-hoc development build as requiring native permission again; the agent did not grant or bypass it. The app was left on Settings and a human WhatsApp retry was requested. Test/promotion commands, outcomes and hashes are in the ignored evidence directory.

The Git working tree retains previous work and this two-source-file correction plus documentation. Nothing is staged or committed. Exact status is captured in final-review.json.

Exact final verification commands (DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer, SDKROOT removed):

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-whatsapp-final-focused.xcresult test -only-testing:WesleyFlowAppTests
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-whatsapp-final-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-whatsapp-final-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-whatsapp-final-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-whatsapp-final-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-whatsapp-final-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```

 User acceptance update: the user explicitly confirmed insertion works in WhatsApp and the browser after this correction. This is human-reported acceptance, not automated native evidence. ChatGPT and terminal failures are tracked separately in [the editor-capability report](PHASE1C2-EDITOR-CAPABILITY.md).

No staging, commit, push, remote creation, model execution or later-phase work is authorized or performed.
