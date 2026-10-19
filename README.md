# Wesley Flow

A greenfield native macOS 26+ Apple Silicon application foundation using SwiftUI, AppKit and Swift 6. **Phase 1A remediation is complete on the recorded development host. Stop here pending separately authorized work.** No legacy application source was inspected or reused.

The foundation includes guarded Domain lifecycle values, immutable workflow snapshots, a single-active-task FIFO coordinator, scoped one-use approvals, local SwiftData state/event transactions, interrupted recovery, cancellation/deadlines/quarantine and revision-bound verification ports. Composition requires an explicit store URL and injected executor/verifier. The native window remains a foundation shell; real task workflows and approval controls are not enabled. There are no agents, speech/model integrations, filesystem/process executors or external packages.

Cancellation preserves unknown operation disposition. Result acceptance rechecks monotonic deadlines; stored deadlines never resume across restart. Shutdown closes admission before suspension and bounds status reporting at five seconds. Pending storage remains owned and explicitly uncertain; bounded return does not claim a stuck backend was killed.

## Verification

Open `WesleyFlow.xcodeproj` and use shared scheme `WesleyFlow` on My Mac. Select the full Xcode installation explicitly; do not substitute Command Line Tools. The recorded lane is Xcode 27.0 beta (27A5237l), Swift 6.4, macOS SDK 27.0 and host macOS 27.2. Swift tools 6.2, language mode 6, nonisolated core and deployment target 26.0 remain configured. Actual macOS 26 and Swift 6.2.3 compatibility are unverified. Signing is local ad-hoc, not production distribution.

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Local -configuration Debug build
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Local -configuration Release build
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Local -configuration Debug -resultBundlePath Evidence/local-tests.xcresult test
```

Choose a fresh result path per run. For `test-without-building`, run immediately after `test` or `build-for-testing`; an ordinary app build may remove the hosted test bundle. The shared scheme runs Domain, composition and Phase1A bundles, referencing the package test sources without copying them.

Debug and Release builds passed. The final suite and separate replay each passed 63 functions/258 concrete cases with zero failures or skips. A fresh-process abrupt-exit probe recovered interrupted work without executor replay or restored approval. These results establish the authorized service foundation on this host, not production effect containment or minimum-OS compatibility.

- [Phase 1A remediation and final verification](Docs/PHASE1A-REMEDIATION.md)
- [Phase 1A historical completion and execution evidence](Docs/PHASE1A-COMPLETION.md)
- [Phase 1A implementation decisions and limits](Docs/PHASE1A-IMPLEMENTATION.md)
- [Phase 0B historical completion](Docs/PHASE0B-COMPLETION.md)
- [Preserved approved architecture](Docs/WesleyFlow-Phase0/README.md)
- [Architecture amendment traceability](Docs/PHASE0A-TRACEABILITY.md)
- [Original risk register](Docs/PHASE0A-RISKS.md)

Current command metadata, logs, result bundles, probes and source hashes are in `Evidence/Phase1A-Remediation/`; earlier records remain in `Evidence/Phase1A/` and `Evidence/Phase1A-Audit-2026-10-19/`. Raw evidence/build products are Git-ignored. Verified source and reports are recorded in the local remediation commit.
