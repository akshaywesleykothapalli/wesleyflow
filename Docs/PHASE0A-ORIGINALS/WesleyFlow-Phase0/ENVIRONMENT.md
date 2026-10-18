# Environment inspection

Inspected 18 October 2026. Values below are actual command outputs, not inferred compatibility claims.

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

## Foundation verification configuration after approval

Use an explicit `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` without changing global preferences. Set deployment target macOS 26.0, Swift language mode 6, strict concurrency, arm64. Compile against the selected Xcode SDK. Record exact toolchain, scheme, configuration, commands, exit codes, and test results. Validate Debug and Release builds; run tests through a shared scheme on `platform=macOS`. Verify a launch separately from compilation. Do not combine the Command Line Tools compiler with the Xcode SDK opportunistically.

The beta toolchain is a development limitation. A stable Xcode installation supporting the deployment target should become the release baseline before shipping. SDK discovery does not prove license, signing, launch, UI automation, or all build components work.
