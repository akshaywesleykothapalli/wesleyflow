# Phase 1C.2 — System-wide dictation and native interface

> Current interaction update: the user subsequently requested hold-Fn/release-to-insert with a transient status pill. The click-based behavior described below is historical. See [the Fn correction report](PHASE1C2-FN-REFINEMENT.md) for current behavior, verification and the still-unverified Codex question-field insertion.

Status: implementation delivered; live cross-application acceptance remains UNVERIFIED. No claim of production insertion readiness or safe live incremental typing is made.

## Baseline and preservation

Repository `WesleyFlow`, branch `main`, starting HEAD `0a3e91c731a716945853a6b84bcfaaf6d9e672d3`. Before editing, `Evidence/Phase1C2/BASELINE.json`, `before.diff` and `Before/` preserved the 18 outstanding Phase1C.1 files, hashes and Git status. The recorded Phase1C.1 full/replay/Debug/Release exit codes were0 and all recorded source hashes matched the starting files. This is validation of the existing683-case evidence, not a newly executed baseline run. The final full suite reruns the retained tests.

Inspected AGENTS.md, Phase0 and Phase1B architecture/security/persistence boundaries, Phase1C.1 completion evidence, all outstanding source/configuration changes, current speech/audio callbacks, Fn monitor, HUD, root/composition, permission contracts, persistence and tests. No DailyOps repository, source or assets were accessed for this milestone. The existing Apple speech engine, audio/concurrency fixes, whitespace cleanup, task coordinator, proposal/context and guarded provider implementations remain. Historical1C.1 report and original tests remain unchanged.

## Components and dependency direction

- Domain: `GlobalDictation.swift` defines Sendable target/selection/clipboard values, typed outcomes, insertion/history ports and history queries. Foundation only; no AppKit or speech dependency.
- SystemOperations: `NativeTextInsertion.swift` captures native AX targets and clipboard representations; `TextInsertionService.swift` coordinates bounded insertion, verification, cancellation and restoration. Depends on Domain only.
- Persistence: `SwiftDataDictationHistoryStore.swift` owns a separate actor-isolated, versioned SwiftData transcript store. The task/event store schema is untouched. Depends on Domain only.
- VoiceInput: read-only `AppleSpeechConfiguration.swift` observes installed assets and permission state; existing `AppleDictationInput` and callback/audio implementation are reused unchanged. Depends on Domain only.
- App: `SystemWideDictationCoordinator`, `ClickableDictationPill`, `DictationPreferences` and `GlobalDictationView` compose these ports. Root/app delegate/composition/project references integrate the new production path. No new package target, third-party package, entitlement, launcher or task executor was introduced.
- Tests: `AppTests/GlobalDictationTests.swift` adds deterministic insertion/coordinator/history cases and native page-instantiation checks. No original test was removed or weakened.

The previous DictationModel, prompt-rewriter service and their tests remain available as tested services. The old raw/clean/prompt root dashboard was replaced as requested. Production root composition has a metadata-inspection closure only and no inference method. Legacy Fn destination compatibility now uses the same captured AX identity and verified selected-text write; unsafe dispatch-only legacy paste was removed. New Fn gestures use the global coordinator and insertion service.

## Capture and session lifecycle

The84×32 borderless NSPanel is nonactivating, never key/main, visible across Spaces and fullscreen, and stays at its initial bottom-center position. No permanent text appears inside it. Idle/preparing/recording/finalizing/inserting/success/error use compact native symbols, progress or waveform animation; reduced motion uses static bars. Left click starts/stops; right-click Cancel and the app/menu Cancel stop owned work. Double clicks are ignored, busy phases reject overlapping sessions, and all speech callbacks are session-generation fenced.

A mouse-down handler captures synchronously before starting asynchronous speech. It binds process ID plus launch date, actual focused AX window/element references, editable capability, original field value and UTF-16 selection, source application name and session UUID. Native validation requires the same foreground process launch, same window/element via CFEqual, unchanged field/selection, consent, nonsecure input, editable capability and age under120seconds. Opaque persisted-independent identity labels do not substitute for AX reference validation. Invalid/disappeared/changed targets never redirect to a newly focused application.

Speech uses the Mac preferred language, installed SpeechTranscriber/DictationTranscriber resources or supported on-device SFSpeechRecognizer fallback. No resource installation or cloud fallback is introduced. Recording is capped at60seconds, finalization at8seconds through an injected clock. Permission-wait cancellation fences late results; partial cancelled/failed/timed-out text is never inserted. During insertion, cancellation reports the actual effect/uncertainty rather than claiming an undo. Clock arithmetic is overflow guarded. Speech startup callbacks, audio conversion and bounded buffering remain the tested1C.1 implementation.

## Insertion and clipboard safeguards

Outcomes are INSERTED, DENIED, UNSUPPORTED_TARGET, TARGET_CHANGED, CANCELLED, TIMED_OUT and UNCERTAIN, with reason, attempted and pending-clipboard fields.

1. Reject foreign generations, invalid UTF-16 caret/selection boundaries, empty/oversized transcripts, stale/secure/noneditable/unsupported targets, revoked consent and pre-effect cancellation/deadline.
2. Prefer AXSelectedText when writable. Never set the entire AXValue. A failed write is uncertain and never retried by paste, avoiding duplication.
3. Fallback requires a captured readable value/selection and evidence of editability. Snapshot supported clipboard formats, check changeCount, publish plain text plus an ownership marker, revalidate the original target and clipboard ownership, then send Command-V down/up to the bound PID. No Return/Enter, automatic submission, shell or AppleScript exists.
4. INSERTED requires observing exactly the expected original-value-plus-selection-replacement result. Posted events alone never prove insertion. Observation is bounded by1500milliseconds/32polls, with injected-clock scheduling. No fixed delay acts as an acknowledgement.
5. Restore supported previous clipboard representations only while ownership/count still match. Newer copies are preserved. Native failed-publication and failed-restoration paths retain a known empty revision lease where possible so restoration can be retried without claiming ownership of an external update.
6. After an unacknowledged posted paste, do not automatically restore: the paste may still be queued. Return UNCERTAIN, retain one bounded backup in RAM and block another clipboard fallback. Explicit user confirmation of paste completion permits an ownership-checked restoration attempt. Direct AX insertion may still work while a backup is pending.

Supported clipboard representations: plain UTF-8/UTF-16, HTML, RTF, PNG, TIFF, JPEG and URL/fileURL; at most16items,16representations per item and1MiB copied data. Unknown/promised/custom types fail before clearing. Backups are never persisted. Clipboard managers and the target app may retain copied transcripts.

Limitations: NSPasteboard offers no atomic compare-and-swap with external clients. Checks immediately precede writes, but same-user concurrent clipboard races cannot be eliminated. AX validation and asynchronous event processing are also not an atomic OS transaction; another app can change focus/state after validation. Observable expected text is evidence of field change, not a causal OS paste acknowledgement. AX SDK calls are synchronous with0.2second messaging timeouts; cancellation cannot forcibly interrupt a blocked framework call, and1500ms is a cooperative budget. Large AX/pasteboard values may be allocated by the SDK before application size checks. Unsupported/ambiguous editors must remain manual-copy cases. None of this establishes OS containment of arbitrary code.

## Native navigation and settings

NavigationSplitView with220–300point sidebar (ideal240), Dictation/History/Insights/Dictionary and Settings footer. The app defaults to1000×720 with840×570 minimum. Dictation shows status, short instructions, permission states, recent real entries and a manual-copy capture path. Entry details provide editable draft/copy and optional raw comparison; no permanent stacked transcript/prompt panes remain.

History is newest first, grouped by local date, searchable across raw/clean/source, with entry details, copy, delete-one and clear-all confirmation. Insights counts only actual saved entries: words, duration, verified and uncertain outcomes. Dictionary truthfully states custom vocabulary is unavailable. No mock history, productivity claims or fake rewrites exist.

Settings contains speech/models, smart formatting, shortcuts, privacy and general. Speech inspection reports actual asset/support state and the last engine. Optional installed Ollama metadata inspection calls discover only; it does not start the daemon, load/unload/generate a model, change thresholds or activate OpenCode. Speech assets, optional rewriting and coding models are distinguished; installed models are not Ready. Only real whitespace cleanup is exposed; no filler/spelling/punctuation/deduplication switches are fabricated. Light/dark/system appearance, pill visibility and history preference persist through a bounded versioned UserDefaults record; incompatible preferences are preserved and not overwritten.

Microphone/speech consent is user-initiated. Accessibility onboarding uses the native macOS prompt; denied access still permits in-app dictation/manual copy. Pill clicks require no keyboard monitor. Fn is optional and explicitly enabled; the existing monitor/consent behavior remains. No permissions are granted by tests or scripts, no system preferences are changed and no broad file entitlement was added.

## Local history and privacy

Store: Application Support/WesleyFlow/Dictation/dictations.store, separate from task storage. Versioned schema1 and conservative marker/header validation, single-owner file lock, explicit actor-owned saves/rollback, account-only file modes, no CloudKit. Unknown/corrupt schema is preserved, not reset. Reopen, deletion, clear, duplicate identity and capacity failures are tested. Fetches are bounded to2001 rows before validation. Each entry validates UUID, date, raw/clean16KiB limits, source256bytes, duration≤120seconds and truthful insertion evidence.

History recording is on by default for the user-requested history feature and can be disabled in Privacy. Disabling does not erase existing history; consent is checked both at capture start and save. Default retention is until explicit deletion, capped at2000entries and a cooperative100MiB SQLite/WAL/SHM admission check. This is a separate dictation-retention policy, not a claim that the historical30-day coding-evidence policy is implemented here or that all app storage shares a hard OS quota. A full store rejects new saves and preserves the latest transcript for manual copy. Disk/framework stalls cannot be forcibly killed; a save can delay completion. A crash during live capture or before a completed save can lose that entry; no automatic audio/replay recovery is implemented.

Saved data: timestamp, raw/cleaned text, source application name when captured, duration and insertion receipt. Word/character counts derive from text. No audio, target original contents, AX references, clipboard backups or credentials are saved. Target text is transient RAM used to verify selection replacement. History is local plaintext protected by the account, not application encryption; backups, SSD journaling and clipboard managers may retain data. Deletion is logical, not guaranteed forensic erasure. Failed persistence reports an error and retains current text for manual copy.

## Automated verification

<!-- RESULTS -->
| Check | Evidence stem | Exit | Result |
|---|---|---:|---|
| Focused insertion/coordinator/history/UI-construction tests | `accepted-verification-focused` | 0 | 102 expanded cases /81 functions |
| Full retained suite | `accepted-verification-full` | 0 | 726 expanded cases /308 functions |
| Independent replay (separate test-without-building invocation) | `accepted-verification-replay` | 0 | 726 expanded cases /308 functions |
| Debug build | `accepted-verification-debug` | 0 | BUILD SUCCEEDED |
| Release build | `accepted-verification-release` | 0 | BUILD SUCCEEDED |
| Optimized Release QA compilation, ENABLE_TESTABILITY=YES | `accepted-verification-final-release-tests` | 0 | TEST BUILD SUCCEEDED |

All test runs have0failures and0skips. The complete suite adds43expanded cases/36functions to the retained683/272 baseline. Every final run used identical source hashes and reported source_unchanged=true; final review confirms current sources still match. No Swift concurrency diagnostic remains in final verification. Existing AppIntents extraction warnings and linkd.autoShortcut connection messages remain.

Intermediate failures are retained: stale incremental Domain-module resolution; missing throwing declarations and a SwiftUI/Domain TextSelection name collision in new tests; a mutable fixture capture warning; and an initial optimized QA invocation without ENABLE_TESTABILITY=YES. These were corrected without weakening tests or changing Release product flags. The corrected optimized test build passed with testability enabled explicitly for QA.

Exact accepted commands (run from the repository; SDKROOT removed and DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer for each):

```text
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-Final -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-verification-focused.xcresult test -only-testing:WesleyFlowAppTests
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-Final -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-verification-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-Final -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-verification-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-Final -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-verification-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-Final -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-verification-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-Final-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-verification-final-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```

`xcrun swift package dump-package --package-path Packages/WesleyFlowCore` exited0 with no external dependencies. The reviewed graph keeps Domain dependency-free and core production modules depending on Domain only; App composes them. `git diff --check` exited0. Pattern checks found no private-key/token patterns in changed files; this is not a universal secret-detection guarantee. All original tracked test files are unchanged; original1C.1 test/speech/provider/package/tool/report hashes match the saved baseline.
<!-- END RESULTS -->

Exact xcodebuild arguments, explicit developer directory, timestamps, exit codes, source hashes and post-run source-stability checks are retained under ignored `Evidence/Phase1C2/*.json`, logs and xcresult bundles. Verification uses Xcode27 beta/Swift6.4/macOS27SDK with macOS26 arm64 deployment and Swift6 strict concurrency; actual macOS26 execution and Swift6.2.3 toolchain builds remain NOT TESTED.

New coverage includes original capture ordering/generation, repeated clicks, start/stop/finalization, changed/foreign/secure/denied/unsupported targets, caret/selection/Unicode boundaries, typed failed/uncertain writes, native Command-V construction without posting, private native pasteboard multi-format restore/publication failure/restoration retry/newer-copy preservation, pending backup limits, cancellation before/after paste and during startup/recording/finalization/insertion, finalization deadline, history opt-out/settings, actual SwiftData reopen/schema/corruption/capacity/identity/search/date grouping, native non-key panel size and all page construction in both appearances. Fixtures never record microphone input, enable global key monitors, post keyboard events or change the general pasteboard. Native pasteboard tests use unique private named pasteboards only.

Native view bitmap snapshots are diagnostic artifacts, not accepted visual proof: NSHostingView bitmap capture returned incomplete/black layer regions despite successful layout construction. This is explicitly not a passing screenshot comparison or end-to-end sidebar interaction test. The running-app navigation check below provides separate limited UI evidence; it does not validate native paste.

## Live application verification matrix

| Application | Final-only click/stop insertion | Focus/duplication/punctuation/clipboard/cancel/app switch | Evidence |
|---|---|---|---|
| TextEdit | UNVERIFIED | UNVERIFIED | Needs human speech and native target test |
| Apple Notes | UNVERIFIED | UNVERIFIED | Needs human speech and native target test |
| Safari text input | UNVERIFIED | UNVERIFIED | Needs human speech and native target test |
| Browser ChatGPT editor | UNVERIFIED | UNVERIFIED | Needs human speech; never submit |
| VS Code | UNVERIFIED | UNVERIFIED | Needs human speech and native target test |
| Codex Desktop/Electron | UNVERIFIED | UNVERIFIED | Needs human speech; never submit |

Previous user-confirmed1C.1 Fn dictation is historical evidence, not acceptance of this new click-based flow. The native UI tool initially selected an older build by display name and lost its connection. Reconnecting using the exact1C.2 build path succeeded. Actual UI actions selected Dictation, History, Insights, Dictionary and Settings and observed their truthful empty/disabled states. The system-dark Dictation screen was visually inspected: native sidebar labels and main controls were readable without the offscreen bitmap artifacts. Settings showed Mac-language English(India), actual disabled inference, real formatting/shortcut/privacy/general controls. Appearance-menu inspection succeeded; an attempted Light selection was interrupted by user interaction and did not apply, so actual light-theme acceptance remains UNVERIFIED. No permission prompt was accepted by automation, no inference was triggered and no test transcript was fabricated.

The user's first live attempt was BLOCKED by macOS Quit/Reopen selecting an obsolete task-foundation build; it is not an insertion pass. Diagnosis found56 same-identifier bundles under this repository's DerivedData. The obsolete running MemoryRemediation release-test app was identified by exact PID/path and terminated; build files were preserved. The verified Debug bundle was copied to the new ignored canonical `Run/Wesley Flow.app`, all copied file hashes matched and codesign --verify --deep --strict exited0. Only these repository build registrations were unregistered; the canonical copy was registered last. Native UI then confirmed the canonical copy opens the Dictation sidebar and reports Accessibility allowed; microphone/speech remained Not requested. No TCC database, consent or system security setting was changed. Evidence: canonical-launch-preparation.json and native UI tool observations. An additional human retry was requested. Automatic permission-triggered Quit/Reopen routing is still UNVERIFIED until that retry; registration/copy alone is not an end-to-end OS restart test.

Use `$REPO_ROOT/Run/Wesley Flow.app` for this checkpoint rather than historical build-cache apps. Future Xcode builds can register additional copies again; promote/register the intended build after verification before live testing. The canonical copy is a generated development artifact, not an installer or release-signing solution. Fixture success does not establish actual nonactivation, permission denial/revocation behavior, reliable clipboard round trips or editor support.

Manual procedure: open a disposable blank field, copy harmless clipboard text, place a caret/selection, click the pill, speak “Wesley Flow test one”, click to stop, verify single insertion at the original position and clipboard behavior. Repeat with cancellation, app switching, changed selection, unsupported and secure fields, light/dark UI and history copy/delete/clear confirmation. Keep all prompts unsubmitted. Review the reported insertion outcome; uncertain text remains available for manual copy. Reauthorize this ad-hoc development build manually in macOS if required.

## Incremental insertion decision

DEFERRED; no experimental switch is exposed. The current speech adapter emits replaceable complete transcript hypotheses and a terminal finish, not a cross-engine stable-segment/revision contract. Modern Speech results may provide finalized ranges internally, but the public reusable adapter does not promise monotonic finalized text. Incremental AX/paste would need segment identity, exactly-once committed offsets, user-edit detection, cancellation reconciliation and real-editor acknowledgements. Partial hypotheses must not be repeatedly pasted or used to delete later user text. Final-only insertion remains the baseline and itself still needs live acceptance.

## Requirements and readiness

| Requirement | Status |
|---|---|
| Baseline/repository/source preservation | COMPLETE with recorded before/final review evidence |
| Coordinator/reused speech | COMPLETE in software; live acceptance UNVERIFIED |
| Original-target binding | COMPLETE in native implementation/fixtures; native race limitations documented |
| Typed insertion/clipboard safeguards | COMPLETE in software; live editor/clipboard acceptance UNVERIFIED |
| Permission onboarding | COMPLETE; actual OS denial/revocation matrix UNVERIFIED |
| Compact clickable pill | COMPLETE in software; actual focus/visual behavior UNVERIFIED |
| Incremental insertion | DEFERRED with reasons; no mutable partial insertion |
| Sidebar/history/insights/settings | COMPLETE in software/construction tests; actual navigation and dark Dictation UI checked; light appearance and populated-history live interaction UNVERIFIED |
| Custom dictionary/advanced formatting | UNAVAILABLE, labelled truthfully |
| AI features | DISABLED; no inference/download/agent/submission |
| Full/replay/build verification | See measured results above |
| Manual application matrix | UNVERIFIED; not a production readiness claim |

No Phase1C.3 or coding-agent work began. Stop after this milestone; do not enable incremental insertion until a separately scoped follow-up demonstrates it.

## Working tree

<!-- GIT -->
Branch main, HEAD unchanged at0a3e91c731a716945853a6b84bcfaaf6d9e672d3. 30 outstanding files comprise the18 preserved Phase1C.1 files,11 new Phase1C.2 files and the Run/ generated-artifact ignore rule. Eight baseline files were intentionally amended (AGENTS, root/composition/app delegate/project, NativeDictationShortcut compatibility, security/model docs); ten baseline files retain exact hashes. No unexpected baseline modifications, original test changes, external dependencies or unignored generated artifacts were found. The staged diff is empty. No commit, push or remote creation occurred.

```text
 M .gitignore
 M AGENTS.md
 M App/AppComposition.swift
 M App/FoundationView.swift
 M App/WesleyFlowApp.swift
 M Docs/Phase1B/MODEL-PROVIDER.md
 M Docs/Phase1B/SECURITY-BOUNDARIES.md
 M Packages/WesleyFlowCore/Package.swift
 M Packages/WesleyFlowCore/Tools/OllamaEvaluation/EvaluationMain.swift
 M WesleyFlow.xcodeproj/project.pbxproj
?? App/ClickableDictationPill.swift
?? App/DictationModel.swift
?? App/DictationPreferences.swift
?? App/GlobalDictationView.swift
?? App/SystemWideDictationCoordinator.swift
?? AppTests/DictationTests.swift
?? AppTests/GlobalDictationTests.swift
?? Docs/Phase1C/PHASE1C1-COMPLETION.md
?? Docs/Phase1C/PHASE1C2-GLOBAL-DICTATION.md
?? Packages/WesleyFlowCore/Sources/Domain/Dictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/LocalPromptRewriter.swift
?? Packages/WesleyFlowCore/Sources/Persistence/SwiftDataDictationHistoryStore.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AppleDictationInput.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AppleSpeechConfiguration.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/NativeSpeechCallbacks.swift
```

The canonical copied bundle and all Evidence/DerivedData remain ignored. Final-review.json records original hashes, source equality across all accepted runs, module checks, paths and Git checks. The Run ignore rule and report were updated after compiled verification; executable sources were unchanged.
<!-- END GIT -->
