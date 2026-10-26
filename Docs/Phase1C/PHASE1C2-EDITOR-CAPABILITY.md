# Editor capability correction and Terminal boundary

Subsequent clipboard-dependent regression: see [the clipboard repair](PHASE1C2-CLIPBOARD-REPAIR.md). The prior capability build/tests below are historical evidence; live ChatGPT acceptance was not established.

20 October 2026. Follow-up to the user's confirmation that Fn insertion now works in WhatsApp and the browser, but fails in ChatGPT and a terminal. The user subsequently identified ChatGPT Mac app and Apple Terminal, and explicitly declined Terminal draft typing. Apple Terminal remains manual-copy only. No inspection of ChatGPT conversations, terminal contents or prohibited Codex UI was attempted.

## Observed stage

Wesley Flow's own latest diagnostic says the field lacks an editable interface. The latest record is not proof of which of the two reported apps produced it. It does establish an editor-capability rejection in that recorded attempt, before paste. The previous WhatsApp text-reading correction is human-confirmed for WhatsApp and browser only; it does not establish universal input support.

## Implemented correction

The native gate previously required either AXEditable=true or a writable AXSelectedText/AXValue. This unnecessarily conflates AX text mutation with clipboard-paste capability. An enabled, focused editor can expose a writable selected-text range while not exposing direct text updates.

NativeEditorCapability now also accepts a writable selected-text range when AXEditable is absent and neither text property can be written. Explicit disabled/read-only markers still reject. The additional path does not apply to known Apple Terminal/iTerm console identities: selecting scrollback is not authority to alter a shell input cursor. Previously accepted explicit editable/text-write interfaces retain their behavior.

No new dispatch mechanism is introduced: native target capture still requires the same allowed role, full bounded text, valid UTF-16 caret/selection, process/launch/window/element identity and existing Accessibility consent. Revalidation applies the same capability rule. Only the existing bounded, ownership-checked paste path runs; INSERTED still requires the observed complete expected text. Neither selection nor text is written during capability inspection. This remains application-level validation, not an atomic OS transaction or a guarantee against a malicious accessibility provider.

New regressions exercise selection-only editor acceptance and real service-level verified paste with a fake target/clipboard, explicit read-only/disabled rejection, missing capabilities and console-selection exclusion. Existing speech, history, Commands, dependencies, package/Xcode configuration and actual key dispatch are unchanged.

## Terminal is a separate policy decision

The user wants dictation wherever typing is possible. Universal availability cannot be promised: secure fields and unidentified/unverifiable targets remain excluded. A terminal's screen selection may describe read-only output instead of the program's input caret. Removing that distinction would fabricate editor verification.

[Terminal draft typing](TERMINAL-DRAFT-TYPING-PROPOSAL.md) is a concrete, unimplemented optional route. It requires an explicit user choice because the adopted insertion contract says unsupported/ambiguous editors remain manual-copy cases. It would start disabled, bind one named app/window per Fn gesture, reject control characters and line breaks, send no Return and report attempted/unverified delivery. Ordinary printable text can still act as terminal-program commands; this risk is disclosed. No implementation or enablement is inferred from elapsed time or a general “make it work” request.

The prior explicit refusal of AXManualAccessibility/AXEnhancedUserInterface activation remains in effect. No activation code, browser changes, AI, shell executor, command submission, automatic native permission grants, staging, commit or push is added.

## Verification

Source-matched commands/outcomes/hashes: Evidence/Phase1C2/accepted-editor-capability-*.json/log/xcresult. Before files, old canonical hashes, new summaries, diff and deployment evidence: Evidence/Phase1C2/EditorCapability (ignored).

Final results, all exit0 and source-hash matched:

| Verification | Result |
| --- | --- |
| Focused app tests | 147 cases / 110 functions passed |
| Full suite | 771 cases / 337 functions passed |
| Independent replay | 771 cases / 337 functions passed |
| Debug and Release builds | Passed |
| Optimized Release test compilation | Passed |

Zero failed/skipped cases; no Swift compiler warnings/errors. Existing AppIntents metadata-skip and test-host macOS linkd connection diagnostics are preserved in logs. All20 tracked pre-existing test files match HEAD. Package targets/dependencies and Xcode project configuration were not changed by this correction. Toolchain remains explicitly selected Xcode-beta/Swift6.4/macOS27SDK with arm64 deployment26; actual macOS26/Swift6.2.3 are unverified.

Canonical Run/Wesley Flow.app matches the final Debug bundle and passes deep/strict code-sign verification. The previously human-confirmed WhatsApp/browser bundle is preserved at Run/.before-editor-capability. Stale own-app registrations were removed and canonical registered last; absent-entry -10814 cleanup responses are recorded. Native UI confirmed the correct app/sidebar/history launched, then left Settings open. This changed ad-hoc build requires native permission again (Fn off, Accessibility needed); no grants were automated or bypassed. No actual ChatGPT/terminal input was posted by verification tools. See EditorCapability/promotion.json and final-review.json for hashes, commands and actual results.

The working tree preserves previous work and the narrow correction/docs; exact status is recorded, with no staged files, commit, push or remote change. No Terminal draft-typing implementation exists; the user subsequently declined that proposal.

Exact verification commands (DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer, SDKROOT removed):

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-editor-capability-focused.xcresult test -only-testing:WesleyFlowAppTests
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-editor-capability-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-editor-capability-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-editor-capability-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-editor-capability-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-CommandsFinal-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-editor-capability-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```

 Native ChatGPT insertion remains UNVERIFIED; the writable-caret distinction is a tested implementation gap, not yet a proven explanation of the user's ChatGPT failure. Terminal draft typing is DECLINED / NOT IMPLEMENTED; the user selected manual-copy only for Apple Terminal.

## Latest manual-check state

The canonical app was inspected after the user identified the apps. Its Settings show Fn disabled and Accessibility needed for this changed development build; microphone/speech have not been requested in this build. No further source rebuild or permission automation was performed. A human retry in an empty ChatGPT Mac prompt was requested, without sending. ChatGPT acceptance remains pending; the prior771-case verification remains evidence for the unchanged binary, not live ChatGPT success.
