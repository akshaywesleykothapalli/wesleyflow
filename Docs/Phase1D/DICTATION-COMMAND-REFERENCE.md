# Dictation and Command Mode reference refinement

25 October 2026. Original native SwiftUI presentation adapted to the two supplied screenshots. Only `App/GlobalDictationView.swift` changed in this task; all prior uncommitted work preserved.

Dictation now uses monospaced medium-weight localized times, centered transcript/action alignment,44pt row inset,20pt inset hairline separators,46pt minimum row height, larger muted copy/delete symbols and a tracked date heading without a redundant bottom rule. Existing pinned opaque headers, real history/search, full-text review, copy confirmation, lease safeguards and confirmed persistent deletion are unchanged.

Command Mode now uses native serif title/subheading, concise accurate instructions, and one rounded16pt two-column reference container with horizontal separators. Spoken phrases use native monospace; descriptions remain muted system text. Only the six supported app-opening commands are listed, derived from the actual registry. The reference screenshot's quit/switch/mute/sleep/lock/URL/search/Spotify actions were not implemented or advertised. This task is visual refinement, not authorization to expand system automation.

Opened the verified Debug app after normal safety-gated quit and process confirmation, without forced termination or installed/Run bundle replacement. Captured and inspected actual Dark/Light Dictation and Command Mode. Restored original System appearance and left the app on Dictation. No recording, permissions, clipboard writes, deletes, inference or command execution occurred. Screenshots show real existing history. Exact minimum-size/fullscreen and exhaustive physical scrolling remain unverified; existing automated native fit/larger-text checks passed. One stale native menu reference failed, then refreshed references restored System appearance successfully.

## Verification

Full suite: **964 expanded cases /448 declarations**, 0 failures. Full test, Debug and Release commands all exit0. No tests added for style-only changes; none removed or weakened.

`Evidence/Phase1D/reference-full.json` and `.log`

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/reference-full.xcresult test
```

`Evidence/Phase1D/reference-debug.json` and `.log`

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug build
```

`Evidence/Phase1D/reference-release.json` and `.log`

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release build
```

## Actual screenshots

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

## Git

No staging, commit or push. Working tree remains intentionally dirty with prior work. `git diff --check` exit0.

```text
 M .gitignore
 M AGENTS.md
 M App/AppComposition.swift
 M App/FoundationView.swift
 M App/WesleyFlowApp.swift
 M Docs/Phase1B/MODEL-PROVIDER.md
 M Docs/Phase1B/SECURITY-BOUNDARIES.md
 M Packages/WesleyFlowCore/Package.swift
 M Packages/WesleyFlowCore/Sources/ModelProviders/OllamaTransport.swift
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
?? Packages/WesleyFlowCore/Sources/Domain/ApplicationNetworkPolicy.swift
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
