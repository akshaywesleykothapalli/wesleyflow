# Phase 1C.1 — Native keyboard dictation verification

Status: basic Fn dictation/insertion **confirmed by the user** after the multi-path monitor revision. The compact waveform refinement passes automated verification. Real AI prompt rewriting is implemented behind unchanged provider guards but **BLOCKED by measured memory admission**. The user selected keeping it gated; no model or admission change is authorized. Broader voice quality/offline compatibility gates remain open.

## Authorized product behavior

The user selected the Mac's language, hold **Fn / Globe** to speak and release to insert into the focused text field. They subsequently requested removal of the microphone start button and initially a deterministic structured coding prompt. They then rejected the static wrapper and explicitly selected a fuller AI-generated rewrite. No coding task is submitted; AI is invoked only by the explicit Rewrite action after provider admission. This is the existing greenfield Wesley Flow app.

The user separately authorized read-only inspection of DailyOps on GitHub for behavioral understanding. References inspected: `akshaywesleykothapalli/dailyops`, source tree `34383cb2bc8109de1acc6743ba58434e3cdc1bd7`, `DailyOpsApp/Sources/HotkeyMonitor.swift` and `DictationController.swift`. Relevant observations: redundant AppKit/global/local keyboard observation, permission re-arming, held-state deduplication, foreground-target capture and visible status. No source was imported, copied, executed or migrated. No legacy model, command engine, history, settings or service was adopted. The new implementation uses bounded FIFO signals, generation fences and explicit actor hops rather than the legacy concurrency wrappers. Rote found no matching Play and no installed GitHub adapter; its catalog adapter required separate token setup. Existing GitHub CLI authentication was used without reading credentials. This source-specific code review produced no reusable automation Play or pending workspace.

## Implementation and boundaries

- Domain: Sendable transcription values, typed failures, MainActor dictation/shortcut/destination ports, bounded whitespace cleanup and deterministic prompt formatting.
- VoiceInput is a populated Swift package target depending only on Domain. App composes VoiceInput and SystemOperations; Domain imports no platform framework. No external package dependency was introduced.
- Installed SpeechTranscriber is evaluated first, then installed DictationTranscriber, then SFSpeechRecognizer with both on-device support and `requiresOnDeviceRecognition = true`. Missing capability leaves typed input available. No asset download or cloud fallback is requested.
- Locale comes from `Locale.preferredLanguages.first`, falling back to `Locale.current.identifier`. Read-only target-machine inspection resolved `en-IN`: modern modules were supported but not installed; legacy on-device recognition advertised support. This is a capability observation, not an accuracy benchmark.
- Authorization, recognition and audio callbacks are created outside actor isolation. Only Sendable values/signals cross to MainActor; audio buffers are converted/consumed synchronously behind a scoped native lock. No unsafe continuations or custom unchecked Sendable wrapper were added.
- Native shortcut monitoring is opt-in. It requests native Accessibility consent, combines a listen-only event tap with local/global AppKit monitors, and handles wake/tap interruption without synthesizing a fresh press. One bounded 16-signal FIFO feeds a generation-fenced coordinator. No ordinary typed text is stored or logged. Duplicate down/up signals cannot create multiple insertions.
- After a user requests enable, returning from Settings rechecks authorization and reinstalls monitoring when granted. Revocation disarms the shortcut when detected. Disable removes observers, event monitors and the tap. Quit stops capture and monitoring.
- UI has no microphone start button. Fn signal counts, setup/error messages, a menu bar icon and a non-activating status panel expose the actual state. Enabling the shortcut keeps the app alive after its window closes. The panel does not activate Wesley Flow or change the destination focus. Its final size is84×32 points: only a seven-bar waveform-style activity animation, with no visible text. It is not an audio-amplitude meter. Reduced Motion uses static bars; detailed messages remain in the main window and the indicator has a screen-reader label.
- Destination capture is limited to supported editable AX text roles, excludes secure text fields, and binds app identity, focused element and selection. Before insertion these are rechecked. Text is whitespace-cleaned and inserted once via selected-text accessibility writing or a text-only Cmd-V compatibility fallback targeted at the captured process. No Enter is sent. Failed/changed destinations retain the transcript for manual copy. OS focus and paste dispatch are not atomic, and posted paste has no delivery acknowledgement; UI says insertion was requested rather than claiming receipt.
- Paste fallback deliberately leaves the latest dictation on the clipboard; UI discloses this. App code does not save audio or transcripts. This does not promise that OS speech services or clipboard managers retain nothing.
- Raw snapshots replace prior partial text. Modern range revisions replace overlap instead of duplicating words. Cleanup changes whitespace only. The static Request/Scope/Verification formatter was removed at the user’s request. An explicit text-only AI rewrite now creates the draft when admitted; errors preserve the previous draft with no template substitution. The prompt editor is scrolled into view and focused after the explicit action.
- Limits: 60 seconds recording, 8 seconds finalization, 16 KiB per text/prompt, 256 transcript ranges, 32 queued modern audio buffers. Each converted buffer is capped at 65,536 mono Int16 frames (about 4 MiB queue payload maximum). These cap application-owned buffers, not undocumented OS/framework internals. Cancel discards new dictation and fences late callbacks; stop finalizes it.

## Bugs found and corrected during implementation

1. Initial Swift 6 region-isolation errors around non-Sendable SDK objects required scoped synchronous ownership using OSAllocatedUnfairLock. No actor suppression was used.
2. A synthetic native audio test triggered Speech's Int16 PCM precondition. Added format rejection and a valid conversion regression before using AnalyzerInput.
3. The user's first microphone test crashed in the speech authorization callback with a Swift executor assertion. Explicit nonisolated Sendable callback factories now cover authorization, recognition and audio taps; tests deliver them from background queues. The user subsequently confirmed that in-app transcription appeared.
4. Terminal callbacks during startup or synchronous stop could reopen the recording state or arm an unnecessary finalization timer. Added terminal-state guards and regressions.
5. Early Fn builds used one tap and had inadequate native permission registration/feedback. The user's live failures are preserved; the revised implementation adds independent observation paths, permission re-arming and visible diagnostics. The user subsequently confirmed live Fn capture/insertion working.
6. Xcode beta incremental builds during development failed to expose newly added Domain declarations. Final verification uses a new DerivedData directory. Earlier failed runs remain in evidence; fresh builds must pass before acceptance.

## Verification evidence

Evidence is local and ignored by Git under `Evidence/Phase1C1/`. Each runner JSON records exact argv, developer directory, exit status, timestamps and source hashes. Result bundles/logs are retained alongside it. The runner removes inherited SDKROOT and selects `/Applications/Xcode-beta.app/Contents/Developer`. It uses Swift 6 mode, complete concurrency checking for app configurations, arm64 and deployment target macOS 26.0. Installed compiler/SDK are Xcode 27 beta / Swift 6.4 / macOS 27 SDK; actual macOS 26 and Swift 6.2.3 compatibility remain untested.

Final command pattern (exact expanded paths/argv are in the evidence JSON):

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project WesleyFlow.xcodeproj -scheme WesleyFlow \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData/Phase1C1-Rewrite \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -configuration Debug -resultBundlePath <evidence-result-path> test
```

Focused adds `-only-testing:WesleyFlowAppTests`; replay repeats full `test`; builds use `build` with Debug/Release. Optimized QA uses Release `build-for-testing ENABLE_TESTABILITY=YES` in `DerivedData/Phase1C1-Rewrite-ReleaseTests`. Optimized compilation is not Release test execution. Automated tests never request microphone access, install keyboard monitors, access unrelated project roots, or insert into real applications.

<!-- RESULTS -->
| Check | Evidence stem | Exit | Outcome |
|---|---|---:|---|
| Focused tests | `accepted-rewrite-final-focused` | 0 | 59 expanded cases / 45 functions; 0 failed, 0 skipped |
| Full suite | `accepted-rewrite-final-full` | 0 | 683 expanded cases / 272 functions; 0 failed, 0 skipped |
| Independent replay | `accepted-rewrite-final-replay` | 0 | 683 expanded cases / 272 functions; 0 failed, 0 skipped |
| Debug build | `accepted-rewrite-final-debug` | 0 | Succeeded |
| Release build | `accepted-rewrite-final-release` | 0 | Succeeded |
| Optimized Release QA compilation | `accepted-rewrite-final-optimized-release-tests` | 0 | Succeeded |

All final source hashes matched after verification. AppIntents metadata extraction warnings and the existing linkd.autoShortcut connection log remain. No Swift concurrency diagnostic remained in final builds. The first rewrite-focused run found one erroneous fixture: its supposedly foreign response ID equaled the expected request ID. The fixture was corrected to use distinct identities, and all checks reran without weakening validation. Earlier failed runs are retained. Generated evidence/builds remain ignored and unstaged.
<!-- END RESULTS -->

New tests cover cleanup/Unicode, complete snapshot replacement, structured prompt bounds/content, explicit prompt population, cancellation during permission waits, late events, terminal startup/stop races, timeout/recording limits with a controlled clock, native audio conversion/overflow/device-format rejection, background SDK callbacks, gesture deduplication, preparation cancellation, denied monitoring, unsupported/changed targets, one-shot insertion, observer loss, authorization grant/revocation and quit cleanup. Existing task/recovery/permission/provider tests remain in the full suite.

## Live acceptance and remaining limits

The user confirmed basic Fn capture and insertion working and requested the smaller pill. The final visual refinement remains available for user feedback; automated tests do not establish appearance or speech accuracy. No automated global key monitor, clipboard write, microphone capture or cross-app insertion was used for verification. Packet-level offline speech operation, actual-OS denial/revocation, asset removal, wake/device changes, full-screen apps, secure input, repeated real capture cycles, accuracy, latency and aggregate memory remain NOT TESTED. ADR009’s broader readiness gate remains open.

### AI rewrite refinement and measured blocker

`LocalPromptRewriter` in ModelProviders depends only on Domain and the existing replaceable LocalModelProvider port. App now links this existing product; no target or external dependency was added. The provider’s version/model identity checks, loopback transport, process-local lease, pressure monitoring, cancellation, memory thresholds and quarantine behavior are unchanged. The adapter sends only the edited draft (no files or project context), requires a bounded JSON string, binds request/model identity and caps input at1,800 UTF-8 bytes, output at8KiB, context4096, output768 tokens and deadline60s. Root-string schema conformance and semantic rewrite quality remain unverified against loaded models. General schema-format support is documented by [Ollama](https://ollama.com/blog/structured-outputs); source/fixture support is not live acceptance.

The Rewrite button is explicit; Qwen2.5 Coder7B is selected by default, with the other already approved installed model selectable. Nothing infers on launch, capture or insertion. Dictation is blocked while rewrite work or cleanup is uncertain. Cancel is request-ID-bound; a late cancel cannot affect a later request. Editing a draft cancels the old rewrite and fences its late output. An explicit cleanup check can observe provider settlement; this is not proof of compute termination, zero memory, cross-process exclusion or durable uncertainty recovery across app restarts.

Native bounded probe: `Packages/WesleyFlowCore/.build/debug/OllamaEvaluation --probe-prompt-rewrite <Evidence/Phase1C1/rewrite-live-probe>`, exit0 for evidence capture, **0 generated rewrites**. It stopped at the first of two frozen synthetic examples with `memoryAdmissionDenied`; `/api/chat` count0, shutdown `notSent`, normal pressure. Baseline available5,115,592,704 bytes (4.76GiB); selected artifact4,683,087,561 plus unchanged6,442,450,944 reserve requires11,125,538,505 bytes (10.36GiB). One `/api/ps`, one `/api/show`, two version and two tags observations occurred; no model was loaded or downloaded. Evidence: `rewrite-probe-build.{json,log}`, `rewrite-live-probe-command.json`, `rewrite-live-probe/result.json`. The old Wesley Flow test instance was closed before the probe; unrelated apps/services were untouched. The user selected **keep local rewrite gated for now**. No smaller-model download, cloud provider, threshold reduction or application termination to reclaim memory was performed.

If macOS handles Globe as emoji, input switching or Apple Dictation, its Keyboard setting may need **Press Globe key to → Do Nothing**. The app does not alter system preferences. Ad-hoc development builds may require macOS permission reauthorization after rebuilding. Some applications expose no supported editable accessibility target; those must fail visibly and retain the text. Cross-app paste cannot be certified solely by successful event posting.

## Files and Git

Modified: `Docs/Phase1B/MODEL-PROVIDER.md`, `Docs/Phase1B/SECURITY-BOUNDARIES.md`, `Packages/WesleyFlowCore/Tools/OllamaEvaluation/EvaluationMain.swift`, `AGENTS.md`, `App/AppComposition.swift`, `App/FoundationView.swift`, `App/WesleyFlowApp.swift`, `Packages/WesleyFlowCore/Package.swift`, `WesleyFlow.xcodeproj/project.pbxproj`.

Added: `Packages/WesleyFlowCore/Sources/ModelProviders/LocalPromptRewriter.swift`, `App/DictationModel.swift`, `AppTests/DictationTests.swift`, `Packages/WesleyFlowCore/Sources/Domain/Dictation.swift`, `Packages/WesleyFlowCore/Sources/Domain/DictationShortcut.swift`, `Packages/WesleyFlowCore/Sources/VoiceInput/AppleDictationInput.swift`, `Packages/WesleyFlowCore/Sources/VoiceInput/NativeSpeechCallbacks.swift`, `Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift`, this report.

Branch `main`; starting HEAD `0a3e91c731a716945853a6b84bcfaaf6d9e672d3`. Changes remain uncommitted and unstaged. No remote was created and no push was performed. Existing task orchestration, proposal validation, workspace broker and guarded inference behavior were preserved. Only the explicitly requested draft-rewrite integration was added. No coding agent, command/voice automation, model download, task execution or future phase was enabled. Keep AI rewrite gated and the broader unmeasured voice/inference acceptance gates open.
