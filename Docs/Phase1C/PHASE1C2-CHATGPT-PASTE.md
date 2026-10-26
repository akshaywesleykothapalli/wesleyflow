# ChatGPT insertion compatibility follow-up

20 October 2026. User acceptance of the preceding clipboard repair: WhatsApp works; ChatGPT Mac app fails. Terminal remains manual-copy only; foreground accessibility-tree activation remains explicitly declined.

## Evidence and diagnosis limits

Wesley Flow's own receipt metadata reports ChatGPT UNCERTAIN / verificationUnavailable / attempted=true / clipboardPending=false. This establishes an attempted, unverified insertion, not which delivery method was used. No target-field contents, ChatGPT conversations or clipboard payloads were inspected. Static installed /Applications/ChatGPT.app/Contents/Info.plist reports executable ChatGPT, bundle identifier com.openai.codex, version26.1013.40934. No ChatGPT/Codex UI automation was used. Bundle metadata is identity evidence, not evidence of editor behavior.

The prior direct AX route may report writability without confirming a useful change. That is a hypothesis, not a reproduced native ChatGPT defect. For this installed app identity, choose the existing normal paste path before attempting direct text replacement. Unsupported clipboard backup may still select the existing bounded Unicode path, only with the existing validated readable field. Every method retains original process/window/field binding, secure-field rejection, full expected-text observation and uncertainty. A failed or uncertain attempt never triggers an automatic second method. Other app identities retain the previous route selection.

Transient failure messages now distinguish direct text update, paste and clipboard-free typing. They contain capability information, never target contents. Existing cancellation fallback messages remain. No persistent schema change, new target, dependency, entitlement, credential, provider, shell executor, prompt submission or permission bypass was introduced. Apple Terminal remains rejected for automatic insertion. No AXManualAccessibility or AXEnhancedUserInterface writes are enabled.

## Changes reviewed

- Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift: pure initial-method policy and native adapter guard for the verified installed app identity.
- Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift: route-specific uncertainty explanations; no retry or verification relaxation.
- App/SystemWideDictationCoordinator.swift: display uncertainty explanations.
- AppTests/GlobalDictationTests.swift: three deterministic regressions covering initial paste selection/clipboard restoration, unacknowledged paste without method retry, and uncertain direct-update diagnostics without retry. Fixtures never post input to real applications.
- This report and the historical report's follow-up pointer. All pre-existing uncommitted work is preserved.

## Verification

All six checks exited0; source SHA256 maps remained unchanged and match the reviewed source. Focused:174 cases /126 functions. Complete suite:798 cases /353 functions. Independent replay:798 cases /353 functions. Zero failed/skipped. Debug build, Release build and optimized Release test compilation passed. No Swift compiler warning/error was found; existing AppIntents metadata-skip and test-host linkd connection diagnostics remain. All20 tracked pre-existing test files match HEAD; nothing staged; git diff --check passed. Xcode-beta/Swift6.4/macOS27SDK, arm64 deployment26. No actual macOS26 or Swift6.2.3 runtime validation is claimed.

Exact command/exit/timestamp/source-hash records: Evidence/Phase1C2/accepted-chatgpt-paste-*.json with logs/xcresult. Expanded counts, narrow before/after diff and final status: Evidence/Phase1C2/ChatGPTPaste. These generated artifacts remain ignored.

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-chatgpt-paste-focused.xcresult test -only-testing:WesleyFlowAppTests
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-chatgpt-paste-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-chatgpt-paste-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-chatgpt-paste-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-chatgpt-paste-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-chatgpt-paste-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```

Commands use DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer with SDKROOT removed.

## Deployment and remaining acceptance

After all checks, the generated Run/Wesley Flow.app was compared file-for-file with the verified Debug app and deep/strict signature-verified. Previous canonical bundle is preserved as Run/.before-chatgpt-paste. Only own app launch registrations were refreshed; canonical registered last. Promotion command exits/hashes are in ChatGPTPaste/promotion.json. Native launch of the exact canonical path showed the Dictation/History/Commands sidebar, then Settings. Fn is disabled and native permissions need approval for the new ad-hoc build; no permission was granted automatically.

Live ChatGPT insertion is PENDING human acceptance. Passing fixtures does not prove it works in ChatGPT. WhatsApp was accepted on the previous build; its selection policy is unchanged but live acceptance of this new binary is pending. Browser acceptance and universal editor compatibility are not claimed. Unreadable/secure fields remain unsupported; Terminal remains manual-copy only. Clipboard restoration after an unacknowledged paste remains explicit and ownership checked. Synchronous AX and input/focus races retain their previously documented limitations.

No commit, staging, push, remote, AI execution or accessibility-tree activation occurred. Work stops at this compatibility correction pending the requested human test.

## Subsequent human feedback: first insertion succeeds, repeats blocked

The user reports the first attempt inserted into the ChatGPT answer field, then subsequent attempts did not. Inspection of Wesley Flow's own UI showed the first attempt saved as UNCERTAIN and later attempts as DENIED with the exact status: “A previous paste needs clipboard review before another paste can be attempted.” The clipboard-review control was visible. This confirms the repeated-attempt blocker is the retained pending clipboard lease after unacknowledged delivery. The first delivered paste is human-confirmed, not programmatically verified; successful repeated insertion is not established.

No code or binary was changed in response to this feedback. Do not automatically clear the pending lease, restore its clipboard or retry the uncertain text. The existing explicit recovery control was left visible and the user was asked to confirm the paste completed, restore the saved clipboard through that control, and retry once without sending. The original verification evidence remains applicable to the unchanged source. Reliable unattended ChatGPT insertion remains unresolved; no universal compatibility claim is made.

See [Repeated insertion follow-up](PHASE1C2-REPEATED-INSERTION.md) for the subsequent failed recovery, diagnostic/recording-guard change, actual verification and unpromoted build status.
