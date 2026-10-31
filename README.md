# Wesley Flow

A native, local-first voice dictation and personal-agent app for Apple Silicon Macs, built with SwiftUI, AppKit and Swift 6.

## Current capabilities

- Global hold-to-talk dictation using a configured Fn/Globe or supported right-modifier key, with a small floating recording pill.
- Installed Apple on-device Speech/Dictation engines; no configured cloud transcription fallback or automatic speech-asset downloads.
- Dictionary, protected vocabulary, phrase replacements and deterministic formatting options.
- Local dictation history, copy/delete controls, activity Insights and calendar heatmap.
- Permission-aware insertion into supported editable fields, with original-target validation, observed-result verification and clipboard recovery safeguards.
- Optional Smart Polish and structured-prompt organization using Apple's on-device FoundationModels provider. Explicit manual previews support review and Copy. Separately enabled in-place shortcuts require a fresh verified dictation receipt, unchanged exact context and a supported editor; nothing is submitted.

## Agent commands — build 45.0.4

A separate configurable hold-to-talk Agent shortcut routes spoken requests directly to a closed native planner/executor. Fn dictation remains independent. Agent commands do not paste their transcripts or submit conversations.

The 100-command expansion adds window tiling, scoped file operations, Notes edits/export, reminder and calendar management, browser/media controls, reviewed email, contact/chat lookup, local scheduled drafts and saved routines. Native availability and permissions apply. Existing private-item changes and communications require exact review. Spotify album search and Safari bookmarking require native selection/confirmation; scheduled messages require fresh review when due. Unsupported requests fail transparently; this is not unrestricted computer control.

- [Normal quit verification and result-pill correction](Docs/Agents/MILESTONE45A-R3-QUIT-VERIFICATION.md)
- [Natural local website/app requests](Docs/Agents/MILESTONE45A-R2-NATURAL-NAVIGATION.md)
- [Website routing correction](Docs/Agents/MILESTONE45A-R1-WEBSITE-ROUTING.md)
- [100-command implementation and acceptance](Docs/Agents/MILESTONE45A-100-COMMANDS.md)
- [All 100 commands and actual limits](Docs/Agents/COMMAND-GUIDE-100.md)
- [Previous Mac/app controls and examples](Docs/Agents/MILESTONE44A-MAC-APP-CONTROLS.md)
- [Folder and browser search commands](Docs/Agents/MILESTONE43A-FOLDERS-BROWSERS-COMMANDS.md)
- [Original 100-command roadmap](Docs/Agents/COMMAND-ROADMAP-100.md) — retained requirements; current scope is in the guide
- [Current source publication checkpoint](Docs/Agents/BUILD45-PUBLICATION-CHECKPOINT.md)

## Important limits

A dispatched native insertion is not proof that text appeared. Current supported native dictation uses verified direct editing or bounded clipboard-free Unicode events; an unreadable target remains unverified, and unsupported text is retained for manual copy. Legacy clipboard routes retain ownership-bound recovery safeguards; an existing backup is never discarded to quit or update. Changed or unsafe targets fail closed. The user has reported the later app/dictation/Agent builds working, while the newly added 45A command paths still require physical acceptance. Apple Terminal remains manual-copy only. No accessibility-tree activation is enabled.

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
