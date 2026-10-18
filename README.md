# Wesley Flow

A greenfield native macOS foundation, implemented from the approved Phase 0A architecture. Phase 0B is complete on the recorded development host. **Stop here; Phase 1 needs separate authorization.**

## Included

- Minimal SwiftUI window with AppKit application-close lifecycle.
- Local Domain package with Sendable task identifiers, typed states/events/failures, guarded pure transitions and retry linkage.
- MainActor shell composition through one injected status-provider protocol.
- Domain and composition tests in the shared `WesleyFlow` scheme.

There is no task executor, history store, speech, model, agent, automation or subprocess facility in this foundation. No permission prompts or external package dependencies are added. No previous application implementation was inspected or reused; only approved architecture documentation was copied.

## Open and verify

Open `WesleyFlow.xcodeproj` in the selected full Xcode installation. Run the shared `WesleyFlow` scheme on My Mac. Current settings: macOS 26.0 minimum, arm64 app, Swift 6 mode, strict concurrency, nonisolated core/default isolation and explicit MainActor UI. Package tools minimum is 6.2; Swift 6.2.3 compatibility remains unverified.

The recorded development lane is Xcode 27.0 beta build 27A5237l, Swift 6.4 and macOS 27 SDK. Local ad-hoc signing uses no signing team; `local.wesleyflow.WesleyFlow` is a development identifier, not a shipping identity.

From the repository root, use an explicit full-Xcode directory without changing the global selection:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Xcode -configuration Debug build
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Xcode -configuration Release build
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Xcode -configuration Debug -resultBundlePath Evidence/manual-tests.xcresult test
open 'DerivedData/Xcode/Build/Products/Debug/Wesley Flow.app'
```

Use a new result-bundle path for each run; Xcode does not overwrite existing bundles. The shared scheme contains both native test bundles. `DomainTests` compiles the test source in the package's Tests directory without duplicating it. Swift Package Manager can also run that same source with `xcrun swift test --package-path Packages/WesleyFlowCore --scratch-path DerivedData/SwiftPackage`.

## Actual results and documentation

Final Debug and Release builds passed. Both test bundles passed: 15 test functions, 178 concrete cases, zero failures/skips; a separate test-without-building replay also passed. Launch was verified by the actual process and an on-screen window titled “Wesley Flow”. These results establish the foundation on macOS 27.2; they do not prove macOS 26.0 runtime or production release compatibility.

- [Phase 0B implementation notes](Docs/PHASE0B-FOUNDATION.md)
- [Phase 0B completion and gate report](Docs/PHASE0B-COMPLETION.md)
- [Preserved approved architecture](Docs/WesleyFlow-Phase0/README.md)
- [Amendment traceability](Docs/PHASE0A-TRACEABILITY.md)
- [Original risk register](Docs/PHASE0A-RISKS.md)

Actual local logs, command/exit metadata, result bundles, launch observations, source hashes and final Git status are retained in `Evidence/Phase0B/`. Build products and raw evidence are ignored by Git; report summaries are versioned. Do not publish raw evidence without reviewing device identifiers and local paths.
