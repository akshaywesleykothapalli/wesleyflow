# MILESTONE 41A-R2 — Full-screen Agent access and faster speech startup

30 October 2026, Asia/Calcutta. Build **41.0.3**, marketing version 0.1.0, arm64. Implements the user's full-screen “Agent unavailable” and Preparing-delay corrections. Physical full-screen/microphone/latency acceptance remains pending; no live microphone recording or productive app action was run by verification. The prepared production bundle is not launched.

## Root cause and correction

Agent capture previously used a system-wide AX focused-element lookup and required a successful text/focus element even though an Agent command never inserts into that element. A full-screen video, canvas, desktop or app that explicitly exposes no focused element can therefore throw `TextTargetError.unsupported` before speech starts; the coordinator labels it Agent unavailable. Validation repeats while recording, at transcript callbacks and before planning, so the same unnecessary requirement could also cancel a session later.

`NativeDictationShortcut.validateAgentCapture` now queries the **frontmost application's** security metadata. A trusted process with Secure Event Input off may proceed when the application explicitly returns `noValue`, `attributeUnsupported` or `notImplemented` for a missing focused element. A present element is checked for secure/password subrole **and** role. Permission loss, global secure input, known secure fields, invalid/malformed successful metadata and unknown failures such as `cannotComplete` remain blocked. There must still be a live foreground app and the original key-delivery activation identity check remains. No field value, selected text or clipboard contents are read by this check. This changes the Agent security requirement, not dictation's captured insertion destination or its stricter field requirements.

AX messaging timeout is limited to 100 ms per application/element request, scoped to those objects; system-wide AX timeout defaults are not changed. This reduces the potential wait on an unresponsive app. It is not a single overall 100 ms deadline: focus/subrole/role are separate requests, and real OS scheduling varies. Unknown/unresponsive AX failures can still show Agent unavailable rather than silently bypassing security. The user's exact native AX error in the reported session was not captured; the confirmed code-level cause above is a reproducible class of full-screen rejection, not a claim of physical acceptance.

The existing compact nonactivating panel already has `.canJoinAllSpaces` and `.fullScreenAuxiliary` with status-bar level, and does not become key/main. That code is preserved. No app activation, Space switch or foreground editor selection is introduced to start Agent capture.

## Actual startup work removed

Previously every hold called the shared dictation `start`, requested a speech-authorization callback even when authorization was already settled, inspected modern speech/dictation inventories/locales, constructed a modern module/analyzer and prepared that analyzer before starting the audio tap. Speech resource inspection has multiple asynchronous framework calls; modern preparation can add a cold-start wait. Renaming the HUD alone would not remove that work.

New optional `AgentDictationInput.startAgent` is implemented by the **same** `AppleDictationInput` instance. For Agent only, when `SFSpeechRecognizer` is available and supports on-device recognition for the requested locale, it uses the existing on-device legacy speech pipeline directly. It skips the modern inventory inspection and analyzer preparation for that session. Settled speech authorization is checked synchronously, while first-time authorization remains user-initiated and awaited. Microphone authorization is still checked on every session. `requiresOnDeviceRecognition` stays true; there is no cloud recognition or resource download fallback.

If that on-device recognizer is unavailable, Agent retains the existing installed modern-engine discovery/preparation fallback. Ordinary dictation continues to call `start` and retains its original modern-first engine selection, permission callback, inventory inspection, speech merging/range/finalization and insertion behavior. Agent uses the existing legacy passage/recovery/error pipeline rather than a new transcript merger. The diagnostics identify the fast path with `fallbackReason=agentFastOnDevice`, provider `legacyOnDevice`; its modern inventories remain uninspected rather than falsely marked ready. Both paths retain unique session/task diagnostic IDs.

Agent also skips the optional dictation hold-debounce gate; ordinary dictation keeps it. The production constructor's prior default was zero, so that change is not claimed as a measured production saving by itself.

There is **no idle microphone warm-up**, background audio capture, parallel speech adapter or recognition task reuse. The same session admission, exclusive capture, previous-task settling, cancellation and cleanup gates still protect both hotkeys. Release during startup cancels the gesture; late startup/transcript completion cannot begin recording or create a task. This deliberately does not capture words spoken before the microphone is ready.

The HUD truthfully shows **Starting mic…** until `input.startAgent` returns with the microphone running, then **Agent listening**. The existing status/diagnostic area records measured `agentStartupMs` from Agent begin through microphone readiness, including security/permissions/startup; it is unmeasured on a canceled/failed start. It is elapsed wall time, not a benchmark promise. No claim of zero cold-start delay or a measured percentage improvement is made. Initial consent, OS audio initialization, unavailable on-device legacy speech and modern fallback can still take time. Physical recognition quality/latency of this Agent-only engine preference remains to be compared; it does not change ordinary dictation's provider preference.

## Source and preserved boundaries

- `Domain/Dictation.swift`: optional `AgentDictationInput` entry point, no transcript schema migration.
- `SystemOperations/NativeDictationShortcut.swift`: Agent-only security validation; native shortcut decoder/event taps, conflict checking, key identity and activation fences are preserved.
- `VoiceInput/AppleDictationInput.swift`: shared-session Agent startup preference; existing merge/range, microphone ingress, audio callback, release/finalization, error and cleanup implementations remain.
- `App/SystemWideDictationCoordinator.swift`: selects Agent startup when implemented, preserves fallback for existing adapters, skips Agent debounce, records readiness time and uses truthful startup status.
- `AppTests/GlobalDictationTests.swift`: full-screen/no-focus security and Agent startup regressions; project build identity **41.0.3**, General marker **41A-R2 / speech38L3R3**.

Installed-app matching/direct WhatsApp opening from 41A-R1, parser/planner/approval/native tools, the 4 GiB local model admission, the independent dictation shortcut, HUD waveform, insertion/clipboard protections, Messages review and existing 38/39/40/41 uncommitted work remain. No model generation/probe, cloud call, download, native message, force quit, staging, commit, push or merge.

## Verification

- **140 focused expanded cases passed**, zero failures.
- Full headless Debug build/tests: **1,516 expanded cases passed**, zero failures.
- Independent test-without-building replay: **1,516 passed**, zero failures. Existing CI required test selection and the unchanged four graphical exclusions were validated.
- **Release and Swift 6 complete strict-concurrency builds passed**, Xcode 27 / Swift 6.4 / macOS 27 SDK, arm64, deployment target macOS 26. Active architecture only, indexing disabled, dwarf information and one compiler job as in 41A. Existing AppIntents/test-runner OS notices remain in logs.
- **13 CI helper tests passed**; tracked-file/reachable-history repository scan and `git diff --check` passed; packaged code signature verified.

New cases cover explicit absent AX focus with secure input/permission denial, unknown focus failures, secure subrole/role, revoked permission, missing metadata, a non-text full-screen/window role, Agent fast-entry routing with no text-target capture and no dictation debounce wait, competing-hotkey audio ownership, cancellation/early release with late startup/transcripts and native exclusive admission before any permission or microphone access. Test fixtures represent full-screen/no-focus state; no physical full-screen success is claimed.

Existing full-suite tests retain short/long held speech, range/error/recovery, dictation debounce, waveform/transcribing states, hotkey repetition/collisions, secure fields, no Agent insertion, clipboard preservation, app opening, model denial and exact message approval checks. The new native admission test invokes `startAgent` but deliberately rejects it **before** microphone/speech permissions or recognition startup. No native speech latency measurement was made by tests. A preliminary verification run was interrupted during review to correct a cancellation test's recording-only wait expectation; its `interrupted-*` artifacts are retained and not counted as final passing results.

Evidence: `Evidence/Milestone41A-R2/manifest.json`, source/backups/hash and preservation checks, milestone-only diff, verifier, final xcresults/summaries/test trees, build/CI logs and signature verification. HEAD remains `24db5c924f8598c6971c771e41f1678262e54379`; staging remains empty.

## Identified build and later user-operated acceptance

Release build **41.0.3**, signature verified:

`/Users/akshaywesley/Developer/WesleyFlow/Run/Milestone41A-R2-41.0.3-a87a4454/Wesley Flow.app`

Executable SHA-256: `a87a4454b343d74c0d7b10412e7cd29acc35e0300319202608a9f42c5f69b4b8`.

The production bundle is **not launched** and the running copy has not been replaced. Finish/cancel active work and resolve clipboard recovery in the old copy, quit normally, then open this exact build when ready. Confirm **41.0.3** and **41A-R2 / speech38L3R3** in General; keep the working Agent key.

1. In a normal window, hold Agent until **Agent listening**, say “Open WhatsApp”, release and verify actual launch with no insertion. Check the measured microphone-ready time and provider in General. Repeat several holds to distinguish first-use consent/cold startup from repeat startup.
2. Repeat over a full-screen browser, video/canvas and another full-screen app with **no text field selected**. The Agent key should capture without exiting full screen or requiring an editor. Verify the compact HUD appears in that Space and the actual requested app opens. Test a second display/Space separately; visual placement remains physical acceptance.
3. Test an ordinary text field, then a disposable password/secure field and native Secure Event Input case. Secure cases must refuse/cancel recording, not launch an action. Revoke Accessibility separately and verify explicit refusal. An unresponsive/unknown AX failure must remain a clear refusal rather than a permission bypass.
4. Release immediately during **Starting mic…**, cancel while listening, repeat rapidly and alternate both hotkeys. Only one capture may run. Late transcripts after cancellation must not execute. Check actual microphone indicator stops.
5. Repeat short app commands and 5/20/45-second Agent holds, speech errors/partial recovery and native on-device-unavailable fallback. Compare actual words/recognition quality, ready time and outcomes. Modern fallback may still require preparation; no download/cloud fallback is allowed.
6. Dictation control: dictate “Open WhatsApp” into a disposable editor. Expect inserted text, original waveform/Transcribing flow and no Agent action. Verify clipboard sentinel, existing range/focus safeguards and no unexpected text over the full-screen app.
