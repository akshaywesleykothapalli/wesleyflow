# Phase 1E — Core voice reliability

26 October 2026 · branch main · HEAD `0a3e91c731a716945853a6b84bcfaaf6d9e672d3`

**Automated verification: PASSED. Physical cross-application acceptance: NOT VERIFIED.** One confirmed failure-reporting defect corrected. No demonstrated new native ChatGPT delivery defect was found; repeated ChatGPT insertion remains unverified. Fixture success does not establish native Accessibility, audio, focus or paste-delivery reliability.

## Scope and inspection

Read AGENTS.md; Phase1D FUNCTIONAL-COMPLETION, OFFLINE-AI-REWRITE and evaluation records; earlier repeated-insertion remediation; actual coordinator, native modifier monitoring, AppleDictationInput/NativeSpeechCallbacks, formatting, native target capture, TextInsertionService, pasteboard leases, history persistence/outcomes, preview isolation and relevant tests. Checked working tree/branch/HEAD before edits. The task-start Swift source hashes match the prior verified 990-case source snapshot exactly (`Evidence/Phase1E/boundaries.json`). All earlier uncommitted work remains.

No physical shortcut experiment, microphone recording, real-app insertion, private conversation/clipboard inspection, permission change, AI inference, download, UI redesign, installed-app replacement, staging, commit or push was performed. Test editors/audio/events are injected synthetic fixtures. Existing private NSPasteboard tests use named disposable boards, not the user's general clipboard.

## Complete voice-path trace

| Stage | Actual behavior and safeguards | Remaining limits |
|---|---|---|
| Global shortcut | NativeDictationShortcut merges native monitor/tap signals into a bounded FIFO. Coordinator fences monitoring generations and held press/release; short holds cancel startup; repeated signals cannot create another active session. | No physical delivery or keyboard-layout acceptance tested here. |
| Recording | Original target captured before asynchronous startup. Apple input owns a UUID, audio ingress, bounded conversion/stream, recording engine and cleanup. Callback adapters are nonisolated and explicitly hop to MainActor for state. | Real microphone/device-change/repeated native engine cleanup remains physical testing. Legacy cleanup can fail closed as busy while native work settles. |
| Speech | Installed Apple on-device Speech/Dictation or requiresOnDeviceRecognition legacy path; no cloud/asset download. Session-fenced cumulative transcript; 60-second capture and 8-second finalization timers. | Permission/native framework waits and teardown are cooperative; no hard OS preemption claim. |
| Formatting | Deterministic existing spacing, punctuation, vocabulary and enabled preferences apply at completion, not partial insertion. Raw/cleaned values remain separate. | Formatting heuristics are unchanged; no new model in the dictation path. |
| Target validation | Bound process/launch/window/element, current focus, secure-input exclusion, original readable text/caret/selection, bounded AX reads and lifespan. Terminal stays manual-copy only; no accessibility-tree activation. | Cross-process focus/content may change around native calls; validations reduce races, not atomicity. Unsupported or unreadable targets fail closed. |
| Insertion | Service checks session, limits, deadline and cancellation. Direct mutation is observed; otherwise paste or bounded plain Unicode fallback only under existing capability rules. No uncertain route retry. Native paste constructs Command-V down/up, no Return. | Keyboard dispatch alone is not confirmation. Unicode fallback disallows control/line separators; OS delivery is not a transactional operation. |
| Clipboard | Bounded representation backup, ownership token/revision, pending recovery ID, no old restoration over a newer revision. Expected post-insertion text permits restoration; unacknowledged paste retains backup and uncertainty. Superseded leases retire without writes/retry. | Backup is RAM-only and normal Quit is guarded; external force termination cannot retain it. NSPasteboard has no cross-process compare-and-swap transaction. |
| History | One session ID per completed attempt; save only with start/current consent. Separate versioned SwiftData store, unique IDs, actor executor, explicit save/rollback, bounded store. Actual delivery receipt retained even during cancellation; storage failure surfaced separately. | History persistence does not prove delivery; store-full/unavailable can prevent archival while latest text remains available. |

Source locations: `App/SystemWideDictationCoordinator.swift`; core `SystemOperations/{NativeDictationShortcut,NativeTextInsertion,TextInsertionService}.swift`, `VoiceInput/{AppleDictationInput,NativeSpeechCallbacks}.swift`, `SystemOperations/NativeDictationFormatting.swift`, `Persistence/SwiftDataDictationHistoryStore.swift`, `Domain/GlobalDictation.swift`.

## Confirmed defect and correction

**R1 — speech failure falsely reported as uncertain insertion (correctness).** Coordinator receive paths produced `.uncertain/.speechFailed/attempted:false` after a failed or oversized transcript, before insertion. `TextInsertionReceipt.status` exposed uncertainty and Insights counted that raw outcome as uncertain delivery. Recognition failure is known; there was no attempted text delivery to be uncertain about.

Evidence before fix: `voice-reproduce` exit65; `VoiceFailureReportingTests.speechFailureIsNotAnUncertainInsertion` failed the expected failed-status/non-uncertain-receipt checks; `legacySpeechFailureDoesNotInflateUncertainDelivery` failed failed-status/count checks. Two test declarations, four failing assertions; retained log/result bundle.

Narrow changes:

- `App/SystemWideDictationCoordinator.swift` receive failure/oversize paths: emit existing `.denied` outcome with `.speechFailed`, attempted false. This maps to failed, **not permission denied**; the speech reason stays explicit. Partial text remains for manual copy, never inserted.
- `Domain/GlobalDictation.swift` status: interpret **legacy** `.uncertain/.speechFailed/attempted:false` as failed without rewriting its stored payload. Attempted delivery uncertainty is unchanged; no new enum/schema/migration.
- `App/DictationPreferences.swift` Insights aggregation: exclude that known failed legacy status from Uncertain Insertions. Categories/layout/preferences unchanged. Historical totals may correctly decrease by the number of such records; saved text and total dictations are unchanged.
- `AppTests/GlobalDictationTests.swift`: append-only regression suites. Both speech error and oversized-after-partial paths tested; legacy JSON still round-trips.

No change to the insertion service, native AX target, native key event construction, speech engine or clipboard broker was justified by this reproduction. No app-specific delay, retry, focus activation or relaxed verification was added.

## Repeated-session and clipboard evidence

New deterministic `VoiceRepeatedPipelineTests.consecutiveSessions` runs eight scenarios: counts 3 and 10 × same/alternating targets × direct/verified-paste routes. It drives an injected shortcut through input, finalization, real formatting, real coordinator/service, fake editor observations, ownership-aware fake clipboard and an in-memory history fixture. Each captures a fresh session/target against the editor's current text/caret. Assertions cover exactly one capture/start/effect/history record per session, unique IDs, exact cumulative field contents, focus unchanged, no partial insertion, no duplicate completion delivery, stale callbacks ignored, original clipboard restored and no retained lease after verified paste. Fixtures are independent of real native delivery.

Additional new scenarios:

- Focus changed after recording: original target rejected with zero effect, no redirect; next freshly captured target succeeds.
- Cancelled session ignores late completion and never writes. An unacknowledged following paste yields dispatched-unverified, retains recovery, and blocks a new recording before capture. A synthetic newer clipboard supersedes that lease; fresh dictation succeeds, old recovery ID cannot restore, newer clipboard stays intact, and old paste count stays one.
- Speech failure and oversized partial have failed status, no effect, error phase and one truthful saved receipt. Legacy failure excluded from uncertain metric; true attempted deadline remains counted.

Existing preserved regressions cover cancelled permission/startup, recording/finalizing cancellation, finalization timeout, cancellation after dispatch, unavailable restoration, stale recovery across newer sessions, private pasteboard representations/publication failures, newer revisions, unsupported/secure/changed targets, no retries on uncertain direct/paste, native event construction excluding Return/Enter, control-character rejection and Unicode bounds. Clocks/phase streams/continuations synchronize these tests; no arbitrary sleep added.

No conclusion is drawn about native queued input from a fixture acknowledgement. No real clipboard values or private messages are diagnostic evidence.

## Automated results and commands

Verified predecessor: 990 expanded cases / 460 declarations, full and replay exit0, bound to identical task-start sources. Final result bundles distinguish expanded cases from declarations:

| Run | Expanded passed cases | Passed declarations | Failed declarations | Exit |
|---|---:|---:|---:|---:|
| voice-focused-fixed | 656 | 357 | 0 | 0 |
| voice-full | 1003 | 465 | 0 | 0 |
| voice-replay | 1003 | 465 | 0 | 0 |

Final 1,003 expanded cases / 465 declarations: +13 cases / +5 declarations. All previous tests remain exact unchanged prefixes; no removed or weakened tests. Focused run preceded addition of the extra oversize parameter case; full/replay include it.

- Debug: exit 0; `Evidence/Phase1E/voice-debug.json/log`.
- Release: exit 0; `Evidence/Phase1E/voice-release.json/log`.
- Concurrency: exit 0; `Evidence/Phase1E/voice-concurrency.json/log`.

Selected developer directory `/Applications/Xcode-beta.app/Contents/Developer`; recorded Xcode27.0 build27A5237l, Apple Swift6.4, SDK27.0, target macOS26 arm64; host arm64 macOS27.2. CLI selection unchanged. `toolchain.json` records version commands/exit0. Complete concurrency compile is not proof of absence of runtime races.

Common command prefix (each exact invocation, timestamps and exit in `Evidence/Phase1E/voice-*.json`):

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild \
  -project WesleyFlow.xcodeproj -scheme WesleyFlow \
  -destination platform=macOS,arch=arm64 \
  -derivedDataPath DerivedData/Phase1E \
  -disableAutomaticPackageResolution -skipPackageUpdates
```

Focused: `-configuration Debug -resultBundlePath <voice-focused-fixed.xcresult> test -only-testing:WorkspaceTests -only-testing:WesleyFlowAppTests`. Full/replay: corresponding `voice-full.xcresult` / `voice-replay.xcresult`, no filters. Builds: `-configuration Debug build`, `-configuration Release build`, and `-configuration Release SWIFT_STRICT_CONCURRENCY=complete build`. Summaries extracted with `xcrun xcresulttool get test-results summary --path <bundle>`; commands/results retained. Independent replay is a separate complete test invocation, not a relabelled first run or clean-build claim.

Development records retained: intentional reproduced test failure exit65; initial fix compile exit65 because a multi-statement case invalidated an implicit switch expression. Corrected to an early legacy guard plus `return switch` preserving other mappings. Subsequent focused/full/replay passed. Existing unused withLock result/AppIntents metadata warnings remain unrelated. No warnings/race checks suppressed.

## User-operated real-application procedure — NOT EXECUTED

This is a prepared acceptance plan, not authorization to automate physical shortcuts. No new physical experiments were run. Use only blank disposable documents/drafts and synthetic phrases; never send/submit a prompt. Native shortcuts remain physically unverified. Verify the actual app identity in its About/menu—ChatGPT macOS and Codex Desktop are separate matrix entries even where earlier bundle naming was confusing.

Preparation:

1. Finish/cancel active dictation and resolve any pending clipboard backup through Wesley Flow's existing confirmation path. Do not force quit or overwrite an unresolved lease. Use the verified Phase1E build only after a safe normal quit of another instance; no installed bundle was replaced by this milestone.
2. Keep both AI previews and preview shortcuts OFF; dictation should use the existing configured hold-to-talk key. Enable native dictation permissions yourself only if needed. Command Mode must not be armed.
3. If you choose to check restoration, first establish a known harmless disposable clipboard item **after** resolving any previous lease. Record only “baseline item restored / newer item preserved / recovery pending / not checked”; do not share its value. Leave any private clipboard unchanged if you do not want this test; mark restoration not checked.

For each app, perform **three consecutive sessions in the same original field**, with the caret at the end. Start with TextEdit blank document, then ChatGPT macOS blank unsent prompt, then Codex Desktop blank unsent composer. Use generic short phrases such as “Test session one”, “Test session two”, “Test session three”. Do not press Return or any Send button.

For each session: click the intended field, hold the configured dictation key, speak, release, then wait for the actual result before the next session. Confirm the app/window/field stayed focused, the new text visibly appeared exactly once, earlier text remains and nothing was submitted. Inspect Wesley Flow's result sentence: verified means the service observed expected text; “attempted/unverified”, unsupported, denied, changed or cancelled must be recorded as such. A visible phrase with an unverified receipt remains unverified in software.

After a verified result, you may manually inspect clipboard restoration by pasting only your known synthetic baseline into a separate disposable TextEdit document. If recovery is pending, first confirm the actual target result, use the displayed recovery confirmation only for that current lease, and record uncertainty if unresolved. Do not infer completion from waiting; do not blindly repeat a possibly delivered phrase or retry a dispatch. For the next session return to the original test field. If any outcome is uncertain/missing/duplicate, stop that app's sequence and retain only capability/outcome metadata; no private text/log export.

| App / session | Target identified | Text appeared | Duplicate / missing | Clipboard | Focus | Actual receipt/outcome |
|---|---|---|---|---|---|---|
| TextEdit / 1 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| TextEdit / 2 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| TextEdit / 3 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| ChatGPT macOS / 1 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| ChatGPT macOS / 2 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| ChatGPT macOS / 3 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Codex Desktop / 1 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Codex Desktop / 2 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Codex Desktop / 3 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

All cells remain **NOT RUN**. No placeholder PASS or screenshot success is claimed. ChatGPT repeated insertion: **UNVERIFIED**; Codex Desktop repeated insertion: **UNVERIFIED**; TextEdit repeated insertion: **UNVERIFIED** for this milestone. Earlier one-off user confirmations are not three-session current-build acceptance.

## AI preview isolation and limits

Smart Polish/Prompt Engineering provider, protection and model instructions are unchanged. Dictation begin/cancel closes pending preview token; changing supplied/selected source, deleting selected history, opt-out and close fence stale results. Completed voice text reaches preview only by explicit user action, never automatically into insertion. Existing 8-second deadline, actor single settling slot, model/language checks, unchanged 4GiB floor/normal pressure/no growing swap and deterministic fallback remain. Provider regressions passed in focused/full/replay.

No real generation authorized as part of a physical voice test was attempted here; no memory probing/retries/model load. The Phase1D 3.9612GiB rejection is historical evidence, not a new measurement. Tone differentiation and real structured-prompt output remain unverified from that blocked run. Automatic AI insertion stays disabled; app-owned HTTP blocking is unchanged, with no cloud fallback or OpenCode.

## Remaining blockers and final status

- Real-app three-session acceptance above is required before declaring repeated ChatGPT/Codex/TextEdit insertion reliable. No native repeated-insertion root cause was demonstrated here, so speculative delivery changes were avoided.
- Accessibility availability, native editor rerender/focus observations and framework teardown still require physical verification. Unknown target capabilities continue manual-copy fallback; Terminal manual-copy and declined accessibility-tree activation remain.
- Unacknowledged queued paste remains uncertain and can require clipboard review. No automatic timeout-based restore, duplicate retry or forced quit is safe evidence of delivery.
- No UI redesign or new AI feature. Normal installed/running app left unchanged; only build/test artifacts produced.

## Git and preservation

Only four existing Swift files changed during this task: coordinator (two outcome substitutions), Domain receipt mapping, metrics aggregation and append-only AppTests. New report is this file. Source hashes, exact narrow diffs, predecessor-source match, empty staging and `git diff --check` exit0 are retained in `Evidence/Phase1E/boundaries.json` and adjacent diffs. Native speech/insertion/clipboard/hotkey, previews/providers, UI views, package/project dependency configuration and earlier Model Lab work were not edited. No source removed, no dependency added, no commit/push/remote created. Branch and HEAD unchanged.

Final short Git status includes all preserved predecessor work:

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
?? Docs/Phase1E/
?? ModelLab/
?? Packages/WesleyFlowCore/Sources/Domain/AppOpeningCommand.swift
?? Packages/WesleyFlowCore/Sources/Domain/ApplicationNetworkPolicy.swift
?? Packages/WesleyFlowCore/Sources/Domain/Dictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift
?? Packages/WesleyFlowCore/Sources/Domain/PromptEngineering.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/AppleTranscriptRewriter.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/LocalPromptRewriter.swift
?? Packages/WesleyFlowCore/Sources/Persistence/SwiftDataDictationHistoryStore.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeAppOpening.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativePreviewShortcuts.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/
```
