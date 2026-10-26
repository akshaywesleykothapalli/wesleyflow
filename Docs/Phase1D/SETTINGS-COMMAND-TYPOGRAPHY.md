# Phase 1D — Settings, Commands and Typography

25 October 2026. **Settings restructuring and supported functional controls implemented and verified; the broader requested feature set remains PARTIAL.** Prompt Engineering generation and Option+1/Option+2 global registration are NOT IMPLEMENTED and visibly unavailable. Native login registration is wired but the development bundle reports service not found. Smart Polish remains opt-in OFF, preview-only, with unchanged memory and preservation gates; new tone quality is not established. No live AI, recording, downloads, automatic insertion, agent execution, commit or push occurred.

## 1. Source-based inventory before implementation

| Classification | Actual initial state |
|---|---|
| WORKING | Installed Apple speech selection/fallback; Fn/right Option/right Command gesture choices; protected local formatting and exact dictionary expansions; optional NSSpellChecker; history/copy/delete; permission status; six app-opening intents |
| PARTIALLY IMPLEMENTED | Speech configuration inspected installed assets, with no manual engine selection or download controls. Existing modifier-only hotkeys did not reserve character chords |
| PREVIEW ONLY | Apple SystemLanguageModel transcript copyediting, default OFF, bounded/cancellable, explicit copy and deterministic fallback; useful accepted rewording not demonstrated |
| NOT IMPLEMENTED | Central network policy/counters, native login controls, tone selection, explicit self-correction setting, spoken smart typography, structured Prompt Engineering preview, Option+1/Option+2 |

Read AGENTS, current source/transport boundaries and latest Phase1C/1D reports. The user authorizes the current settings scope despite historical stops. Existing work was uncommitted and preserved.

## 2. Privacy and complete app-network inventory

Inventory of application sources found one real HTTP backend: `LocalOllamaHTTPTransport`, used by metadata discovery and legacy/proposal-only provider composition. Its endpoint already rejects remote hosts, credentials, paths, queries and redirects, permitting only explicit127.0.0.1 HTTP endpoints. The CodingAgents HTTP client has fixture transports only, no URLSession/network backend or executable runtime. No app-owned remote model downloader, remote provider client, browser automation or general URL client exists. ModelLab Python acquisition/evaluation tools are separate research programs, not launched by the app or controlled by this toggle. `NativeAppOpening` uses an example.invalid URL to look up a default browser, not to load that address; opening another app or System Settings is not traffic owned by Wesley Flow.

Apple Speech/AssetInventory, FoundationModels, NSSpellChecker, ServiceManagement and system services are opaque framework paths. Their internal traffic cannot be measured or firewalled by this app. The page explicitly states this; a normal toggle is not a system firewall, VPN, packet monitor, containment guarantee or proof of zero OS-managed network traffic.

New `ApplicationNetworkPolicy` is a process-local, Sendable admission boundary with synchronous Mutex-protected state. All real app-owned HTTP requests pass through it. Atomic session registration prevents a request from racing past a block change; switching ON denies new HTTP/HTTPS requests and cancels every retained session via URLSession invalidation outside the lock. Finished requests relinquish leases. Cancellation requests do not claim immediate disappearance of in-flight packets. Existing redirect/authentication/cookie/proxy/size/deadline guards remain. No request retry added.

**Loopback is explicitly network traffic and is blocked too.** Pure local operations, dictation formatting and existing on-device preview logic are not blocked. Existing remote endpoint rejection remains even when the switch is OFF. Remote download/connection attempts submitted to this policy are denied when ON, but there is no active downloader or remote-provider feature to test. Any future network backend must explicitly adopt this boundary; it does not intercept arbitrary third-party code.

The switch persists as `blockNetworkRequests`, default false to preserve prior behavior. Policy is applied synchronously at coordinator creation and preference changes. Counters reset per process and store attempts, allowed admission, denied admission, last Date and only “Loopback service” / “External destination.” No URL, hostname, query, transcript, body, token or credential is retained. Allowed is not a successful-response count; an allowed request subsequently cancelled by policy remains an allowed admission. Dashboard labels state this. Counters refresh with the existing UI permission timer; they are not packet telemetry.

Privacy now contains speech processing, network policy/session counts, restrained red PRIVACY DASHBOARD heading and concise warnings. No observed engine is claimed before use; current development bundle showed speech not requested and on-device availability not yet inspected. History retention controls moved to General with the plaintext/backups warning retained in Privacy.

## 3. General and native login control

General groups real mode-for-next-gesture, login, appearance/pill settings; speech/asset inspection; actual TCC states with corresponding Settings links; existing modifier shortcut configuration; and history retention/confirmed deletion. No speech engine was rewritten, no download/key system invented, and no model labelled Ready from metadata. The only supported recognition configuration is the existing automatic installed SpeechTranscriber → installed DictationTranscriber → legacy requiresOnDeviceRecognition chain. It is shown read-only rather than offering a fake provider picker. Installed asset statuses populate only after explicit Inspect; model metadata remains a gated loopback-only inspection.

The mode picker controls the existing one-shot command arm/disarm state and is disabled while busy or hold-to-talk is unavailable. It is intentionally labelled “Mode for next gesture,” not a fabricated persisted default mode; command authorization must not silently persist across later gestures. Existing preference keys/defaults and store version remain. New tone and policy keys decode absent values to their defaults; existing required formatting fields remain required, so unreadable/unknown preferences are preserved rather than silently repaired.

`LoginItemControl` uses [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice), registration/unregistration only on explicit switch action, actual native status on appear/reactivation, in-progress disabling and sanitized errors. No launch plist, daemon, sudo or synthetic preference success state. [requiresApproval](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval?language=objc) is visibly pending approval, not asserted eligible to run. The current DerivedData app returned **notFound / App service not found**; its switch is accurately disabled. Registration, consent and actual subsequent-login launch are **UNVERIFIED**, not passed. No login registration was performed during QA; a stable installed/signed bundle and separate native verification remain necessary.

## 4. Shortcut investigation and command inventory

The existing `NativeDictationShortcut` handles modifier flags for Fn/Globe, right Option and right Command. It is listen-only/pass-through, with generation fencing, repeat/chord cancellation and native consent. It does not own reliable character-chord registration or provide a conflict/keyboard-layout/secure-input reservation contract. Option+1/Option+2 can be character input on keyboard layouts and cannot be silently stolen by this monitor. Both remain **UNREGISTERED**, displayed with the reason; no system-wide shortcut claim or key injection test was made. Preview buttons are the compatible explicit alternative for Smart Polish. Hold-to-talk configuration, persistence, disable behavior and prior decoder tests remain; physical global keyboard-layout/secure-input/focus testing is UNVERIFIED for this milestone. No new arbitrary shortcut recorder is advertised.

Command Mode is a flat two-column reference populated from `AppOpeningCommand.allCases`, with subtle horizontal separators and no title divider/cards/vertical grid. All six displayed commands round-trip through the actual parser:

| Say | Existing effect |
|---|---|
| Open WhatsApp / Whats App | Open installed WhatsApp |
| Open Browser / default browser | Open default browser application |
| Open Settings / system settings | Open System Settings |
| Open Finder | Open Finder |
| Open Notes | Open Notes |
| Open Music | Open Music |

The existing one-gesture Arm/Cancel remains permission/busy guarded. Merely viewing reference rows never opens anything. No imaginary navigation, clipboard, delete-history, generic arbitrary-app, shell or coding actions are listed. Parser/action behavior is preserved; no app-opening command was physically dispatched during QA.

## 5. Smart Formatting and cleaner behavior

Four shared inset-grouped sections use native switches/pickers, real bindings, one container per group, trailing controls and dividers only between rows.

**Smart Formatting & Spelling:** existing whitespace normalization, optional NSSpellChecker and its vocabulary/programming protection, spoken punctuation and capitalization preserved. New Smart Typography is explicit spoken “open quote” → “, “close quote” → ”, “em dash” → — in unprotected spans only. It does not rewrite existing literal quotes, `--`, technical paths or explicit punctuation. It is not a general curly-punctuation rewriter; current conservative output can retain spaces inside spoken quotation marks. No unsupported typography dropdown options are advertised. Spelling is labelled fallible, not guaranteed accurate.

**Speech Cleaner:** existing isolated um/uh/erm removal and repeated-filler collapsing. Repeated-filler toggle is disabled when remove-all-fillers supersedes it, without changing the saved preference. Ordinary repeated content/emphasis remains intact. New optional explicit self correction accepts only a whole current unprotected utterance with the form “Red. Scratch that. Blue.” and retains “Blue.”; bounded prefix≤256 characters, explicit sentence punctuation around the restart, nonempty replacement and **no protected spans**. “Scratch that” alone, vague “No, I mean…,” “Actually…,” non-explicit restarts, technical/vocabulary spans and unrelated previous dictations are preserved. This never edits target documents or previous history. Both new options default OFF. No indiscriminate ordinary-word deduplication or broad self-correction intent engine was added.

**Smart Polish:** existing `offlineAIRewriting` key/default OFF and explicit latest-final-session preview/cancel/copy lifecycle preserved. Native tone picker persists Natural/Professional/Concise/Friendly/Direct. Tone travels in the Domain request through the provider to a fixed instruction chosen from the enum; test confirms propagation. The actual Apple generator incorporates it. The original lexical/protected-span gate is byte-identical: only punctuation/capitalization and hesitation edits can pass; arbitrary rewording, invented constraints or expressive content are rejected. Tone is therefore narrowly supported and cannot guarantee a stylistic rewrite. UI says this and shows Original/Suggested text separately. Memory policy, concurrency/cancellation, model/language availability and deterministic fallback remain. No new live model evaluation occurred; previous weak-quality evidence is not reclassified as success. Automatic insertion remains disabled.

**Prompt Engineering:** **NOT IMPLEMENTED**, native toggle disabled OFF with a concrete reason: the existing conservative copyeditor cannot provide a validated structured-prompt transformation. No no-op enable action, fake prompt, template labelled AI, missing-project fabrication, storage, execution or submission was introduced. Option+2 remains unavailable. This is an honest unavailable feature, not completion of the requested new generator.

## 6. Typography and accessibility

Small shared native tokens: scaled26pt page heading, scaled13pt body, scaled14pt sidebar,12pt semibold section labels, native scalable body-medium setting names and caption descriptions. Existing SF/system fonts only. Shared row names now use a consistent medium weight, setting controls retain native focus/labels, command rows use body typography and Insights numbers gain tabular digits. Dictation, Dictionary and Insights layouts/aggregation remain intact. No global shrinking, external font or UI dependency. Seven-item permanent230pt sidebar, titlebar, window defaults/minimum, Reduce Motion logic and microphone pill are preserved. Native frame/alignment, larger-text and target-size tests passed; exhaustive physical VoiceOver reading and keyboard scrolling are not proven by those tests.

## 7. Actual interaction and screenshots

Normal Quit went through the existing busy/pending-clipboard termination gate; no force quit or clipboard action. Process metadata confirmed no old normal app before final launch. Opened the exact Debug build under `DerivedData/Phase1DSettings`, not the canonical Run/installed bundle. Actual source guards for speech, target capture, clipboard, hotkey, persistence and proposal validation are unchanged.

Real final-process test: Privacy counters began0/0/0 after restart. Enabled Block Network Requests, used General → Inspect metadata once, returned to Privacy, and observed **1 attempt, 0 allowed, 1 blocked; Loopback service**. No request passed admission or model started. Saved safe AX evidence and screenshot. Returned policy to original OFF; session attempt counters correctly remain1. Also confirmed native login notFound/disabled, actual TCC states (not requested/Accessibility needed in this development identity), six command rows and Smart Polish/Prompt Engineering OFF/disabled states. Changed appearance only for requested Light/Dark checks and restored original System appearance. No permissions granted, asset downloads, live AI, recording, source transcript disclosure, copy, deletion or command execution.

Actual screenshots below cover each of four pages in both appearances. Some lower controls extend below the viewport and were inspected via AX rather than physically scrolled. A capture initially failed with ScreenCaptureKit−3811; subsequent final captures succeeded. Scroll attempts still hit the computer-use bridge `noWindowsAvailable` error. Exact960×620 and800×520 physical sizing, fullscreen, physical mouse/trackpad/keyboard scrolling and full lower-page visual inspection remain **UNVERIFIED**. Existing native automated bitmap/fit/larger-text tests still pass, but are not substituted for physical acceptance. Launch-at-login, new tone output quality and system-wide Option shortcuts are not claimed working.

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

## 8. Commands, tests and builds

- settings-baseline: exit0, 953 expanded cases /437 declarations, 0 failures, 0 skipped. Evidence: `Evidence/Phase1D/settings-baseline.json`, `.log` and `.xcresult`.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/settings-baseline.xcresult test
```

- settings-complete-focused: exit0, 618 expanded cases /340 declarations, 0 failures, 0 skipped. Evidence: `Evidence/Phase1D/settings-complete-focused.json`, `.log` and `.xcresult`.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/settings-complete-focused.xcresult test -only-testing:WorkspaceTests -only-testing:WesleyFlowAppTests
```

- settings-complete-full: exit0, 964 expanded cases /448 declarations, 0 failures, 0 skipped. Evidence: `Evidence/Phase1D/settings-complete-full.json`, `.log` and `.xcresult`.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/settings-complete-full.xcresult test
```

- settings-complete-replay: exit0, 964 expanded cases /448 declarations, 0 failures, 0 skipped. Evidence: `Evidence/Phase1D/settings-complete-replay.json`, `.log` and `.xcresult`.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/settings-complete-replay.xcresult test
```

- settings-complete-debug: exit0. Evidence: `Evidence/Phase1D/settings-complete-debug.json`, `.log`.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug build
```

- settings-complete-release: exit0. Evidence: `Evidence/Phase1D/settings-complete-release.json`, `.log`.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DSettings -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release build
```

Eleven added test declarations/cases cover coarse/sensitive-safe denial, local/remote classification, active-lease revocation/idempotency/reset, blocked real transport before exchange,100 concurrent admissions versus block, tone propagation/unchanged gate, protected spoken typography/explicit correction, strict legacy decoding, new preference persistence/default migration, exact command registry coverage and read-only native login status. Existing speech/hotkey/copy/delete/Insights/proposal tests are preserved byte-for-byte as prefixes and rerun. No tests deleted/weakened; no real model was used in tests.

Initial incremental build failed exit65 because stale Domain.framework products in prior DerivedData masked new Domain types. A fresh `DerivedData/Phase1DSettings` resolved this without source workarounds or deleting prior evidence. Final explicit Xcode Debug/Release builds and Swift6 checks passed. Standard AppIntents metadata warnings / system linkd test-host connection messages were observed; no Swift concurrency diagnostics or test failures in final runs. A preservation audit initially attempted to read a nonexistent temporary ProviderTests backup; the final audit instead verifies its task-start SHA256 prefix correctly.

## 9. Scope, remaining work and Git

Changed existing Swift files:

- `App/GlobalDictationView.swift`
- `App/SystemWideDictationCoordinator.swift`
- `App/DictationPreferences.swift`
- `AppTests/GlobalDictationTests.swift`
- `Packages/WesleyFlowCore/Sources/ModelProviders/AppleTranscriptRewriter.swift`
- `Packages/WesleyFlowCore/Sources/ModelProviders/OllamaTransport.swift`
- `Packages/WesleyFlowCore/Sources/Domain/DictationFormatting.swift`
- `Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift`
- `Packages/WesleyFlowCore/Tests/WorkspaceTests/ProviderTests.swift`

New source: `Packages/WesleyFlowCore/Sources/Domain/ApplicationNetworkPolicy.swift`. No package/project target/dependency/entitlement changes. New documentation/screenshots and ignored verification evidence accompany the implementation. All previous work remains. Protected rewrite validation and provider safety-method suffix match task-start bytes; core SystemOperations/VoiceInput/Workspace files are unchanged; existing activity/Insights aggregation content is unchanged. The coordinator change is limited to policy snapshot/application, tone request and accurate command wording, with original speech/clipboard/insertion flow preserved.

Remaining requested capabilities are not silently considered complete: structured Prompt Engineering generator; reliable global character-shortcut registration/conflict/layout/secure-input contract and physical tests; native login service availability and real subsequent-login test; optional manual speech selection/download support; broader safe repeated-word/self-correction semantics; useful accepted tonal rewriting and physical final-utterance preview acceptance; exact-size/fullscreen/scroll/VoiceOver checks. No future phase started.

`git diff --check` exit0. No files staged, no commit, no push or remote creation. Current working tree includes all prior uncommitted work:

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
