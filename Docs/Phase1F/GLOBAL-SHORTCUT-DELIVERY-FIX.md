# Milestone 34 — Global AI shortcut delivery diagnosis

27 October 2026. **Confirmed deployment/configuration blockers found. Physical delivery of the prepared build remains UNVERIFIED pending user testing.** No hotkey-system replacement or AI/provider change was justified.

## Actual root cause and identity

The running process was PID 76569, executable under `DerivedData/Phase1DFunctional/Build/Products/Debug/Wesley Flow.app/Contents/MacOS/Wesley Flow`. Its debug library has no `ShortcutPreviewPanel` or `invokeShortcutPreview` symbols. The Milestone31 build contains them. The canonical `Run/Wesley Flow.app` also lacks the panel. Thus the reported physical failures were not acceptance tests of the latest implementation: the running older build could register shortcuts but could not present the later preview panel. No physical Carbon-event receipt was observed in this task; this diagnosis does not rule out further delivery issues in the new build.

Saved allowlisted preferences: previewShortcutsEnabled=false; offlineAIRewriting=true; promptEngineeringEnabled=true; holdFnEnabled=true; activationKey=fn. This means persisted shortcut opt-in was disabled despite enabled feature preferences. Current in-memory settings were not read; persisted values alone cannot prove the exact state at each earlier keypress. No preference was changed on the user's behalf.

All three bundles report version 0.1.0, build 1, so those labels do not distinguish implementations. Identity evidence in ignored `Evidence/Milestone34/identity.json` records bundle-relative paths and full SHA256 hashes. Debug-library hashes:

- Running Phase1DFunctional: ba57ca069b3de6d5b678dc691f51ec209cfd46c681bea0478ccfe8f6cafd56ce
- Prior Milestone31: 9cb13501c7f5bc65cb304f9e3fb23999cf20f2e09fa70ed6da70d3176ce906e5
- Run bundle: 6da4d039ad6a051931e45e271fd0eb4a339358b50640b5c3a23e8ac4a045ca61

No /Applications/Wesley Flow.app was present. Running bundle timestamp was 26 October; Run executable was 22 October. Exact executable identity, not Finder name/version alone, must be checked for manual acceptance.

## End-to-end source review

Read AGENTS.md, milestones29/31/32/33 reports, Carbon registrar, preferences, coordinator, panel and relevant tests. Branch remains feature/milestone-31-integration at 23caeca630b803fddc2cd007a5159dc9839b71cf; two previous local reports preserved.

Option+1 uses virtual key18, Carbon optionKey and signature WFPR/id1; Option+2 key19/id2. Numeric Unicode translation is only a keyboard-layout admission check, not physical key identity. InstallEventHandler and RegisterEventHotKey return values are checked; registration errors/conflicts are reported. Both use GetApplicationEventTarget. This is Carbon hotkey delivery, not an NSEvent global-only monitor, so no separate local-monitor workaround was justified.

Callbacks validate signature/id and enqueue bounded metadata. Actor delivery checks secure input, modifiers, event age, foreground process and activation epoch. Valid press/release dispatches invokeFrom to the same preview coordinator; repeats, stale releases, focus switches and sleep/wake are fenced. Both opt-ins must be enabled before registration. No actual physical callback or registration state of the stale process was inspected or inferred from source.

The coordinator sets previewPresented before requesting inference. Empty input or unavailable/blocked model still yields a panel and status. Combine schedules panel refresh on MainActor; the panel calls orderFrontRegardless and cannot become key/main. A fresh invocation republishes presentation even if already true. Existing cancellation and session ownership remain. No confirmed current-source hidden-panel defect was reproduced; actual shown-panel recovery remains a manual gate.

## Minimal changes

No dictation, provider, memory admission, permission policy, clipboard, focus-target, hotkey registration or preference-default behavior changed. The operational repair is a safe switch to the verified current build and explicit user opt-in; deployment is pending the user, not claimed completed.

Added Debug-only bounded development diagnostics to the coordinator and panel: disabled, registration requested/succeeded/failed, activation, preview request, presented/hidden. A maximum32 enum entries is retained in memory; no disk, console or telemetry output. No text, clipboard, transcript, prompts, passwords, app identities or personal conversation data retained. Release recording is a no-op. Existing status already exposes native registration failures. Diagnostics distinguish downstream activation and panel visibility, but do not claim receipt of a physical event before the actor delivery gate.

Added two regression methods (three expanded cases): disabled opt-in/error reporting; local/external origin fixture dispatch and bounded diagnostics. Existing tests cover feature persistence, conflicts, secure input, cancellation, stale output, rapid repeats, focus changes, sleep/wake notifications and non-key panel construction. Fixtures cannot prove local/global OS key delivery, shown-window recovery, actual focus or clipboard preservation. No synthetic global keys were sent.

## Safe manual handoff

The user agreed to test after verification finishes. Do not start a second instance alongside the older process. No running app was force-quit, replaced or launched in this milestone. Active session and clipboard-lease safety has not been established externally; consequently automated replacement was not attempted. Quit the older app normally only when idle. Stop if its termination safeguard warns about dictation or clipboard recovery; do not force quit or discard recovery.

Open `DerivedData/Milestone34/Build/Products/Debug/Wesley Flow.app` after the old instance safely exits. Enable both preview features in Smart Formatting and Preview shortcuts in General. Check Registration shows Option+1 and Option+2. Leave preview input empty to avoid inference.

In each app below, press/release Option+1 then Option+2; close and repeat three times. Confirm the correct empty-input preview, original focus, unchanged clipboard, no automatic insertion/submission and no duplicate windows. Do not press Copy/Return or submit anything. No foreground application text is needed. Restore prior settings afterward.

| Application | Option+1 | Option+2 | Focus/clipboard | No insertion/duplicates |
|---|---|---|---|---|
| Wesley Flow | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| TextEdit | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| ChatGPT macOS | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| Codex Desktop | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| VS Code | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |

User reported no visible response in all five apps before diagnosis. Those are recorded failures of the previously running configuration, not passes or fails for Milestone34. No model was invoked here. Keep the4GiB floor; a later blocked generation must preserve source and stop without retries. Automatic AI insertion stays disabled.

## Verification

Results appended after completed runs below. Full argv, timestamps, exits, logs and result bundles are local ignored evidence in Evidence/Milestone34. Initial sandbox-only process listing was denied; native escalation was used for identity-only inspection. Initial sandbox-only xcresult extraction required write access for its database and failed; extraction was rerun with native approval. Neither was treated as a test failure or bypassed.

| Check | Result | Exit |
|---|---|---|
| focused | 19 cases / 12 declarations; zero failed/skipped | 0 |
| full | 1028 cases / 479 declarations; zero failed/skipped | 0 |
| replay | 1028 cases / 479 declarations; zero failed/skipped | 0 |
| debug | — | 0 |
| release | — | 0 |
| concurrency | — | 0 |

Commands: `/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone34 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2`, with explicit DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer. Tests use Debug, parallel testing NO, separate focused/full/replay result bundles. Focused selection: ShortcutDeliveryDiagnosisTests, GlobalAIShortcutWorkflowTests, ExplicitPreviewAppTests and GlobalPreviewDeliveryTests. Debug/Release use build; concurrency adds SWIFT_STRICT_CONCURRENCY=complete to Release. Counts extracted using xcresulttool test-results summary, not test-source counting. Independent replay is a separate test invocation/result bundle, not independent human acceptance.

Baseline1,025 expanded cases retained;3 new diagnostic/dispatch cases yield1,028. No tests removed or weakened. Existing focused lifecycle cases remain. Physical key-code delivery and hidden-panel recovery were source-reviewed, not OS-injected or physically verified. No inference, clipboard observation or cross-app text access occurred. All relevant source changes are development-only metadata recording; the production delivery mechanism was preserved.

Prepared Milestone34 debug-library SHA256: `78be33c390db3b40db3b143c8812daaa73ba730ea37ff6ec392471051d004145`. This build contains the preview panel; use its exact bundle path above. It is not installed over the running app.

## Final state

Three tracked files changed: App/SystemWideDictationCoordinator.swift, App/WesleyFlowApp.swift, AppTests/GlobalDictationTests.swift. New local report: this file. Prior untracked Milestone32/33 reports preserved. Git diff whitespace check passed. No commit, push, merge, visibility, provider, speech, dictation, clipboard or memory-floor change. HEAD remains23caeca630b803fddc2cd007a5159dc9839b71cf; local main remainsb90976c305cb0eb5a32a1658cbe0408f3d8fe2b8. Hosted CI results for the published checkpoint are historical and do not verify this uncommitted diagnostic patch.

**Prepared build: VERIFIED by tests/builds. Safe running-app handoff: PENDING USER. Physical shortcuts: UNVERIFIED.** User agreed to test after verification; no outcome supplied yet. Report each app separately; if a shortcut still fails on the correct enabled build, inspect actual status/Debug metadata rather than replacing the hotkey layer speculatively.
