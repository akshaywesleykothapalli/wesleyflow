# Manual Xcode handoff

25 October2026. Final current source (including restored system typography) verified: **964 expanded test cases**, independent replay **964**, Debug build, Release build and local Release archive all passed, exit0. No generated-code, speech or AI execution.

Opened `/Applications/Xcode-beta.app` (27.0 beta5), loaded the exact `WesleyFlow.xcodeproj`, and verified native toolbar scheme **WesleyFlow**, destination **My Mac**. Did not run the app from Xcode; manual testing is left to the user. No component/model downloads or signing changes were requested.

## Manual controls

- ⌘B: Build.
- ⌘U: Run automated tests.
- ⌘R: Build and run.

The existing project uses ad-hoc local signing, macOS26.0 minimum, and native arm64. Microphone/Speech/Accessibility permission state is tied to the actual built app identity and must be granted through macOS by the user when needed. No permission bypass is performed. Existing disabled/unavailable features and AI quality limits remain; build success is not functional acceptance of them.

Archive: `DerivedData/ManualHandoff/WesleyFlow.xcarchive`. This is a verified **local archive**, not an App Store/Developer ID/notarized distribution export; distribution signing/export/notarization was not performed or verified. No installed app replacement.

## Exact evidence

`Evidence/Phase1D/manual-handoff-full.json` / `.log`: exit0.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/manual-handoff-full.xcresult test
```

`Evidence/Phase1D/manual-handoff-replay.json` / `.log`: exit0.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/manual-handoff-replay.xcresult test
```

`Evidence/Phase1D/manual-handoff-debug.json` / `.log`: exit0.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug build
```

`Evidence/Phase1D/manual-handoff-release.json` / `.log`: exit0.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release build
```

`Evidence/Phase1D/manual-handoff-archive.json` / `.log`: exit0.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination generic/platform=macOS -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -archivePath $REPO_ROOT/DerivedData/ManualHandoff/WesleyFlow.xcarchive archive
```

## Git

Existing uncommitted work preserved. No staging, commit, push or remote creation. Diff check exit0.

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
