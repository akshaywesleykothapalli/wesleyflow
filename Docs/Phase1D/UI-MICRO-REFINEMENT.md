# UI Micro-Refinement

25 October 2026. Focused presentation changes implemented. No provider, speech, clipboard, insertion, storage, preference default or permission behavior changed. No inference was invoked.

## Layout

Removed the outer FlowSection around Offline AI Rewriting. It now uses the existing FlowSettingsGroup and FlowSettingsRow, with one rounded background/border, no single-row divider, native trailing switch, title “Enable offline AI preview” and subtitle “On-device preview only. Automatic insertion stays off.” Preview controls remain outside the settings container and appear only when enabled. An empty OFF-state preview container was removed to avoid extra spacing. Preference key, default OFF, bindings, persistence and all provider guards remain unchanged.

The shared page header minimum height is 56pt (previously62); its existing scaled26pt native title and22pt horizontal inset remain. Sidebar width stays230pt. Masthead symbol21→19pt, text16→15pt, height56→52pt, icon gap9→8pt. Navigation rows44→42pt, row gap2→3pt, label gap10→11pt, leading inset18→16pt. Seven destinations, native titlebar, selected outline weight, blue indicator, focus and reduced-motion-aware hover/selection remain. The smaller sidebar branding still coexists with the standard native window title; no custom titlebar was introduced.

## Scroll indicators

Native `.scrollIndicators(.hidden)` applied to the shared FlowPage (all ordinary main pages), pinned history ScrollView, detail TextEditor and raw comparison ScrollView. Sidebar already used it. No scroll disabling, hit-test masks, clipping changes, custom NSScrollView, or scrolling algorithm changes. Existing LazyVStack pinned section headers and stable identities remain intact.

## Actual UI observations

Opened the final Debug build from DerivedData/Phase1DComplete; canonical Run app was not replaced. Previous app quit normally through its existing busy/pending-clipboard termination gate; process metadata confirmed termination before reopening. No forced quit, capture, cross-app typing, copy, deletion or clipboard read/write was performed.

Inspected Smart Formatting OFF and ON, Dictionary, Dictation, General, Light and Dark appearances. ON was a visual-only preference check: Preview remained disabled without a current reliable utterance; no model request. Restored AI OFF and original System appearance. Native labels and disabled state were exposed in Accessibility. Right-aligned controls, one AI border, readable subtitle and consistent compact header were visible. Standard native window title remains unchanged. A screen-sharing badge appears in screenshots because verification uses native UI capture.

Scrolled real history: rows moved and20th October pinned beneath the page title without overlap or a visible scrollbar. Captured top and scrolled states. Short Dictionary content remained readable. Existing native grouped controls rendered correctly in both appearances. This is a spot check, not proof of every scroll transition.

Unverified: exact800×520 minimum-size overflow, physical trackpad/mouse/keyboard/VoiceOver scrolling matrix, every next-header push-off transition, Reduce Motion on a device, and native fullscreen transition. The fullscreen key attempt did not yield a reliably observable geometry change, so no fullscreen claim is made. No production history was fabricated for visual testing. Screenshot history contains existing local transcripts; screenshots remain local.

## Screenshots

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

## Tests and builds

All final-source runs used explicit `/Applications/Xcode-beta.app/Contents/Developer`, arm64 macOS destination, Swift6 toolchain and the existing scheme. No tests were removed, weakened or added for constant/style-only edits; existing native frame-alignment, separators, preference persistence, navigation, calendar/history/metrics and provider lifecycle tests were rerun. Automated tests do not establish physical sticky-scrolling/accessibility behavior.

- focused: exit0, 599 expanded cases. Evidence: `Evidence/Phase1D/micro-final-focused.json` and `.log`.

```text
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/micro-final-focused.xcresult test -only-testing:WorkspaceTests -only-testing:WesleyFlowAppTests
```

- full: exit0, 945 expanded cases. Evidence: `Evidence/Phase1D/micro-final-full.json` and `.log`.

```text
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/micro-final-full.xcresult test
```

- replay: exit0, 945 expanded cases. Evidence: `Evidence/Phase1D/micro-final-replay.json` and `.log`.

```text
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/micro-final-replay.xcresult test
```

- debug: exit0. Evidence: `Evidence/Phase1D/micro-final-debug.json` and `.log`.

```text
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug build
```

- release: exit0. Evidence: `Evidence/Phase1D/micro-final-release.json` and `.log`.

```text
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release build
```

Full and replay each passed945 expanded cases /431 declarations, matching the prior baseline. No failures/skips. Final Debug and Release builds passed. Initial default-sandbox result-summary access failed because xcresulttool mutates its bundle; native escalation succeeded. One UI scroll attempt used a stale element ID and failed without an action; refreshed references and the subsequent real scroll succeeded. All limitations are retained rather than inferred from unit tests.

## Preservation and Git review

A task-start hash snapshot confirms only `App/GlobalDictationView.swift` changed among pre-existing Swift source/test files. Provider, coordinator, preferences, speech, pill, clipboard, persistence, validator and model files are byte-identical to task start. Prior uncommitted work remains. No dependencies/targets/entitlements added. `git diff --check` exit0, index empty, no commit/push. New milestone documentation/screenshots and ignored build/test evidence accompany the visual file. Working tree is intentionally dirty:

```text
 M .gitignore
 M AGENTS.md
 M App/AppComposition.swift
 M App/FoundationView.swift
 M App/WesleyFlowApp.swift
 M Docs/Phase1B/MODEL-PROVIDER.md
 M Docs/Phase1B/SECURITY-BOUNDARIES.md
 M Packages/WesleyFlowCore/Package.swift
 M Packages/WesleyFlowCore/Tests/WorkspaceTests/ProviderTests.swift
 M Packages/WesleyFlowCore/Tools/OllamaEvaluation/EvaluationMain.swift
 M WesleyFlow.xcodeproj/project.pbxproj
?? App/ClickableDictationPill.swift
?? App/DictationModel.swift
?? App/DictationPreferences.swift
?? App/GlobalDictationView.swift
?? App/SystemWideDictationCoordinator.swift
?? AppTests/DictationTests.swift
?? AppTests/GlobalDictationTests.swift
?? Docs/ModelLab/
?? Docs/Phase1C/
?? Docs/Phase1D/
?? ModelLab/
?? Packages/WesleyFlowCore/Sources/Domain/AppOpeningCommand.swift
?? Packages/WesleyFlowCore/Sources/Domain/Dictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/AppleTranscriptRewriter.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/LocalPromptRewriter.swift
?? Packages/WesleyFlowCore/Sources/Persistence/SwiftDataDictationHistoryStore.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeAppOpening.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/
```
