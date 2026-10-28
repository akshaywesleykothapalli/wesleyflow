# Wesley Flow

A native, local-first voice dictation app for Apple Silicon Macs, built with SwiftUI, AppKit and Swift 6.

## Current capabilities

- Global hold-to-talk dictation using a configured Fn/Globe or supported right-modifier key, with a small floating recording pill.
- Installed Apple on-device Speech/Dictation engines; no configured cloud transcription fallback or automatic speech-asset downloads.
- Dictionary, protected vocabulary, phrase replacements and deterministic formatting options.
- Local dictation history, copy/delete controls, activity Insights and calendar heatmap.
- Permission-aware insertion into supported editable fields, with original-target validation, observed-result verification and clipboard recovery safeguards.
- Optional Smart Polish and structured-prompt organization using Apple's on-device FoundationModels provider. Explicit manual previews support review and Copy. Separately enabled in-place shortcuts require a fresh verified dictation receipt, unchanged exact context and a supported editor; nothing is submitted.

## Important limits

A dispatched paste is not proof that text appeared. An identity-bound editable field can receive one ordinary paste without exact readback; its outcome stays uncertain, its clipboard backup remains pending, and it grants no AI replacement authority. Changed or unsafe targets fail closed. On 28 October 2026 the user confirmed **3/3 physical ChatGPT dictations passed on 37R2**. This does not verify other editors, clipboard/focus edge cases or AI replacement. Apple Terminal remains manual-copy only. No accessibility-tree activation is enabled.

Option+1/Option+2 request in-place Smart Polish/Prompt Engineering and show only pill status; they never open a preview editor. Physical AI shortcut delivery and replacement remain unverified. Automatic replacement in the affected ChatGPT/WhatsApp editors remains unsupported; use the explicit manual preview and Copy workflow. Distinct tone quality and real structured-prompt output remain unverified after the latest native generation was blocked by the unchanged 4 GiB host-memory floor. The preservation gate permits only conservative copyediting; Prompt Engineering organizes supplied lines without inventing requirements. No cloud AI fallback, coding-agent execution, automatic source modification or custom model training is enabled.

## Requirements and permissions

- Apple Silicon; deployment target macOS 26.0 or later.
- Recorded verification host: M4 MacBook Air, 16 GiB unified memory, macOS 27.2.
- Recorded build lane: Xcode 27.0 beta (27A5237l), Swift 6.4, macOS 27 SDK; Swift language mode 6, package tools 6.2. Actual macOS 26 runtime and Command Line Tools Swift 6.2.3 compatibility remain unverified.
- Microphone and Speech access are requested for user-initiated dictation. Global input/insertion requires the relevant native Accessibility/Input Monitoring access. Secure fields are excluded.
- History is stored locally when enabled. The app does not save audio recordings. Apple system services and third-party clipboard managers have their own retention behavior.

Use the General/Privacy controls to review permissions and preferences. The app-owned network-blocking option covers its HTTP paths, including loopback; it is not a system firewall and does not control Apple's system services.

## Build and test

Open `WesleyFlow.xcodeproj`, select the shared **WesleyFlow** scheme and **My Mac**. Choose a full compatible Xcode installation explicitly. Local builds use ad-hoc signing; no signing certificates, provisioning profiles or notarized distribution are supplied. The development app is not App Sandboxed; its approval and clipboard safeguards are application-level controls, not OS containment.

From a clean checkout:

```sh
# Change this to your full Xcode installation if necessary.
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
mkdir -p Evidence
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Local -configuration Debug build
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Local -configuration Release build
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Local -configuration Debug -resultBundlePath Evidence/local-tests.xcresult test
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Local -configuration Release SWIFT_STRICT_CONCURRENCY=complete build
```

Choose a fresh result-bundle path per test run. For `test-without-building`, run immediately after `test` or `build-for-testing`; an ordinary app build may remove the hosted test bundle. Tests use disposable fixtures; they do not record microphone audio, post native insertion keys, run coding agents or infer real-app delivery success.

The native application has no third-party Swift package dependency. Xcode references the local package under `Packages/WesleyFlowCore`; keep that directory and its fixtures in the checkout. Optional [Model Lab](ModelLab/README.md) Python dependencies are separate and are not required to build the app. Model weights, virtual environments, private screenshots, raw evidence and generated artifacts are deliberately excluded. The synthetic datasets and pinned provenance/licensing are retained; preparation is not proof of training or inference feasibility.

## Continuous integration

See the [CI baseline and contribution guide](Docs/Engineering/CI-BASELINE.md) for local checks, hosted test selection, manual verification gates and safe branch/review practices. Milestone 32 hosted push and PR runs passed at the earlier checkpoint; see [hosted evidence](Docs/Engineering/MILESTONE32-HOSTED-CI.md). The [37R2 publication review](Docs/Engineering/MILESTONE37-PUBLICATION-REVIEW.md) records fresh local verification and remaining physical gates. Hosted results must be checked for the exact proposed revision.

## Engineering records

- [Core voice reliability and user-operated acceptance checklist](Docs/Phase1E/CORE-VOICE-RELIABILITY.md)
- [Preview functionality and live resource limitations](Docs/Phase1D/FUNCTIONAL-COMPLETION.md)
- [Proposal-only architecture](Docs/Phase1B/ARCHITECTURE.md)
- [Security boundaries](Docs/Phase1B/SECURITY-BOUNDARIES.md)
- [Original architecture packet](Docs/WesleyFlow-Phase0/README.md)

Phase reports are historical snapshots, not statements that every planned feature is active. Current documentation has been sanitized for publication; original machine-local evidence and captures are not published. Historical Git commits are preserved, including their original author metadata and development paths. Consult the current source and latest report for present behavior.

## License

Original Wesley Flow code and documentation: [MIT](LICENSE), copyright 2026 KOTHAPALLI AKSHAY WESLEY. Separately licensed upstream contracts, research source snapshots and model metadata retain their original notices; see [Third-party notices](THIRD_PARTY_NOTICES.md). Mentioning a supported application or development tool does not assign ownership or imply endorsement.
