# Environment inspection

Original packet inspection dated 18 October 2026. The following are previously reported outputs, preserved verbatim in substance; this amendment task did not reproduce them. They are unverified observations, not current compatibility claims. The host/build and default target triples are unusual and require recapture during separately authorized implementation.

| Check | Observed result |
|---|---|
| Host | `sw_vers`: macOS 27.2, build 26B5091g |
| Architecture | `uname -m`: arm64 |
| Global developer directory | `/Library/Developer/CommandLineTools` |
| Default Xcode invocation | `xcodebuild -version` and `-showsdks` fail because selected tools are Command Line Tools |
| Installed Xcode | `/Applications/Xcode-beta.app`; explicit `DEVELOPER_DIR` reports Xcode 27.0, build 27A5237l |
| Xcode Swift | Apple Swift 6.4, target arm64-apple-macosx27.2.0 |
| Xcode macOS SDK | 27.0, confirmed by `-showsdks` and `xcrun --show-sdk-version` |
| Xcode XCTest | Runner found at `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xctest` |
| Default Swift | Apple Swift 6.2.3, target arm64-apple-macosx28.0 |
| Default SDK | macOS 26.2 at `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` |
| Swift Package Manager | Swift Package Manager – Swift 6.2.3 |
| C/C++ compiler | Apple Clang 17.0.0, available through command-line tools |
| Other tools | Git 2.50.1, make, xcrun, codesign, security found |
| RAM | `sysctl -n hw.memsize` denied; 16 GB is a user-specified target, not a verified host measurement |
| Initial workspace | Empty except `work/` and `outputs/`; no local Git repository detected |

Xcode emitted file-event-stream and cache-directory warnings under current restrictions, but version/SDK discovery completed. Discovering the runner is not a test execution. `swift-testing` is not a standalone executable; its failed lookup does not establish whether the Swift Testing library is available.

## Compatibility contract

| Dimension | Required design choice |
|---|---|
| Primary development compiler | Explicitly selected Xcode 27 beta / Apple Swift 6.4 as originally observed; recapture exact build/path before use; beta development is not a release qualification |
| Language mode | Explicit Swift 6 in every app/package/test target; strict concurrency |
| Package tools minimum | 6.2; source features must compile with Swift 6.2.3 unless a later ADR raises the floor |
| Default isolation | Nonisolated shared/core targets, explicit MainActor UI and actor-owned mutable services; record effective per-target settings |
| Upcoming features | No additional opt-in flags initially; record effective compiler defaults/flags per lane and target; changes require compatibility evidence |
| Primary compile SDK | Coherent macOS 27 SDK bundled with selected Xcode 27; never opportunistically substitute CLT compiler/SDK |
| Minimum deployment | macOS 26.0 in app, package and test configuration; arm64 |
| Compatibility compile lane | Full Xcode 26.3 / Swift 6.2.3 / macOS 26.2 SDK on an Apple-supported macOS 26.x host; separate artifacts/caches |
| Runtime floor | Actual macOS 26.0 arm64 device/VM capable of relevant features; newer host tests do not establish it |
| Release baseline | Stable full Xcode on a supported host, pinned exact version/build in release record; signing/notarization separately verified |

A compiler default target triple is not the app's configured deployment target. Compiler, language mode, package tools minimum, compile SDK and runtime OS are independent dimensions. Swift 6 mode alone does not prove 6.2.3 source compatibility. Use supported source/manifest features at the 6.2 floor and explicit mode selection. [Swift data-race safety guidance](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/enabledataracesafety/).

Apple lists Xcode 27 with Swift 6.4/macOS 27 SDK and deployment ranges including macOS 26; Xcode 26.3 pairs Swift 6.2.3 with macOS 26.2 SDK and a supported host range ending in macOS 26.x. Therefore the recorded macOS 27 host cannot qualify the older full-Xcode lane. CLT discovery is insufficient for app/XCTest verification. This table does not assert the installed beta is currently supported or select a different installation silently. [Apple Xcode requirements](https://developer.apple.com/xcode/system-requirements) (checked 18 October 2026).

Foundation APIs must exist on macOS 26.0. Any later API needs a runtime availability guard and tested macOS 26 path; SDK/compiler guards or exclusion are additionally required when the 26.2 SDK lacks the declaration. Raising the minimum OS/compiler requires an ADR and explicit scope change. Do not assume newer standard-library/compiler features back-deploy. Rebuild dependencies for each compiler; no shared compiler-specific binary modules/build cache.

## Reproducible verification record

After separate implementation authorization, recapture developer path, Xcode build, compiler version, SDK path/version, host OS/build, architecture and physical memory. Select developer directory explicitly without changing global preferences. Record source revision/dirty status, dependency pins, package tools/mode, deployment/isolation/upcoming-feature settings per target, scheme, destination, configuration, environment allowlist, exact commands, timestamps, exit codes, test counts and result bundle paths. Keep sensitive environment values out of reports. Debug/Release and tests use the same coherent selected toolchain per lane; launch is separate evidence.

G0 and GC in TESTING define pass criteria. A missing supported host/OS lane remains an explicit compatibility blocker, not an inferred pass. It does not block creating a separately authorized minimal shell on the available lane, but blocks GC completion and macOS 26/6.2.3 compatibility claims. Stable release, permissions and signing evidence remain separate release gates. Do not install toolchains or change the system selection during this documentation task.
