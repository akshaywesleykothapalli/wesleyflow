# 38L3R3 — Dictation activation identity binding

## Confirmed evidence and limits

R2/build38.3.2 completed 124.569 seconds of modern on-device speech. The user confirmed the transcript contained beginning, middle and end without missing words. External delivery failed before dispatch: captured destination `local.wesleyflow.WesleyFlow`, noneditor focus candidates, bounded search limit64, TARGET_CAPTURE_FAILED/UNSUPPORTED_TARGET. No typing, paste or clipboard lease was dispatched for that operation.

The user clarified **“i was in chatgpt.”** Therefore the failure must not be dismissed as intentionally starting in the wrong window. The trace establishes what capture reported; it does not establish why that differed from the user's intended active ChatGPT editor. Exact activation-change timing/cause remains **UNCONFIRMED**. No ChatGPT/Codex UI or content was inspected or automated. The user subsequently confirmed holding the keyboard shortcut. Whether the main window moved forward remains unconfirmed.

## Source finding

The native dictation monitor previously queued only pressed/released signals. The coordinator later called NativeInsertionTargetCapture, which chose NSWorkspace.frontmostApplication at handling time. No immutable app identity survived the native callback-to-MainActor FIFO handoff. Capture itself occurs before speech startup and before the recording pill is displayed, but after coordinator cleanup/state updates. Thus the code had an unguarded identity gap; this is a confirmed source property, **not proof that a queue race caused the physical failure**.

The existing pill remains borderless/nonactivating and cannot become key/main. No code path activating ChatGPT, guessing the previous editor, activating AX accessibility trees or redirecting at release was added.

## Focused safeguard and diagnostics

Native shortcut callbacks now copy public application identity from a synchronized workspace-activation mailbox into the existing bounded16 signal FIFO: process ID, launch identity, bundle ID, observation time and monitor source. C callbacks still perform no AppKit/AX/editor-text work. A main-queue workspace activation observer updates the mailbox using the notification's application identity; its epoch changes even if the user leaves and returns to the same process. Wake invalidates the snapshot and refreshes it after existing authorization checks. Registration/disable cleanup removes the observer and clears retained activation context.

At delivery, a pressed signal carries its immutable identity and whether the activation epoch remained unchanged. The coordinator pins that context for the recording. Native target capture independently reads current workspace identity and compares process, launch and bundle plus activation continuity **before any editor AX lookup**. Missing/stale/mismatched identity fails as TARGET_CHANGED and preserves copy-only dictation. It never substitutes Wesley Flow, another foreground app or a remembered previous editor. Existing in-recording focus/selection/element validation and clipboard/readback checks still apply at insertion.

Capturer conformers must explicitly implement identity-bound capture; the protocol default fails closed rather than silently ignoring an origin. Existing unbound/manual/pill behavior remains unchanged. This patch binds the **app identity observed at native callback time**; asynchronous system monitor delivery and workspace-notification timing remain platform constraints. It cannot reconstruct an editor identity before observation or claim that a selection was read synchronously in the event tap. The original editable field is still captured at the normal, guarded initial AX lookup and never reacquired at release.

General diagnostics now show `destinationActivation` separately from `observedAtCapture`, including sanitized bundle/PID/launch metadata, source and activation continuity. These fields appear in both speech-copy and insertion diagnostic summaries. No window title, text, clipboard payload, arbitrary key content or transcript hash is recorded. The existing eight-second post-release finalization watchdog, speech resource checks/engine selection, waveform and quiet HUD behavior are unchanged.

## Regression coverage

Six focused regressions exercise matching identity, changed application, PID reuse/relaunch, changed bundle, missing identity, activation-epoch change despite return to the same app, native rejection before AX reads, fail-closed default capturers, exactly one capture despite redundant presses, and preserved full transcript with no clipboard/dispatch on a pre-capture focus switch. Existing focus changes during recording, stale completion, cancellation, clipboard recovery, cross-app insertion, modern/legacy speech and AI safety regressions remain.

The first compile correctly rejected capturing the complete non-Sendable Notification across the actor boundary. Extraction of the application reference before the synchronous main-queue-isolated metadata read fixed that error. No unchecked Sendable conformance, disabled concurrency checking, new timing tolerance, editor allowlist or enlarged search limit was introduced. Final results and evidence are appended below after verification.

## Physical handoff

Identifiable test build: **38L3R3 / 38.3.3**. R3 ChatGPT insertion is **UNVERIFIED**. R2's confirmed complete two-minute speech result remains valid and does not need another long recording to diagnose focus.

Before replacing a running copy, the user's important two-minute transcript must be saved/copied if needed and clipboard recovery resolved. Its latest visible transcript may be held in memory depending on history settings. Normal Quit must continue to pass the app's active-session/setup/clipboard safety gate; no force quit is authorized or used.

The next user-operated test should be short: select the intended ChatGPT draft/caret, hold the selected keyboard key for about5–10seconds, release without submission, then report delivery and only General diagnostic metadata if it fails. This is not a request to automate ChatGPT UI, insert through tools or bypass unsupported editor restrictions. Capture identity mismatches should now identify both observations; the mechanism of the original discrepancy remains open until physical metadata establishes it.

## Preservation and Git

Speech accumulator/configuration, all R2 physical acceptance evidence, original waveform/pill, formatting, AI rewriting, Model Lab, memory floor4GiB, history and clipboard insertion implementations are preserved. Changes are limited to gesture-origin contracts, native shortcut identity handling, native capture precondition/metadata, coordinator binding/metadata, tests/CI and build identity. Earlier uncommitted work is retained. No model downloads, training, commits, staging, pushes, rebases or merges.

Branch `feature/milestone-31-integration`, HEAD `24db5c924f8598c6971c771e41f1678262e54379`.

## Primary references

- [NSWorkspace.frontmostApplication](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication): current app receiving key events, not a historical key-press identity.
- [Workspace activation notification](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification): workspace notification center and affected-app metadata.
- [Global event monitor](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)): system event copies are delivered asynchronously; no assumption of synchronous original-field acquisition is made.

The existing compact error HUD now distinguishes current-operation TARGET_CHANGED (“Target changed”) and UNSUPPORTED_TARGET (“Field unavailable”). These statuses require the current final operation ID, so a blocked new attempt does not reuse an older target-error label. Waveform, Transcribing state and verified-success dismissal are unchanged.

The native sample now also carries the OS event timestamp (NSEvent startup seconds, or CGEvent startup nanoseconds converted to seconds), callback-observed uptime and the workspace activation observation time. A delayed event older than the currently observed activation, a zero/invalid timestamp or an event from the future fails origin admission. No arbitrary age tolerance or wall-clock offset is used. This prevents a pre-activation key event arriving late from being rebound to the newer app even before the FIFO snapshot. A seventh regression covers that case. Conservative rejection around delayed activation notifications remains possible and results in explicit copy-only speech, never retargeting.

Primary timestamp references: [NSEvent.timestamp](https://developer.apple.com/documentation/appkit/nsevent/timestamp), [CGEventTimestamp](https://developer.apple.com/documentation/coregraphics/cgeventtimestamp), [systemUptime](https://developer.apple.com/documentation/foundation/processinfo/systemuptime). These clocks are gesture/activation metadata; they are not mixed with speech audio timelines.

## Final verification checkpoint

- **395 focused expanded cases passed**.
- **1,378 full regression cases and independent 1,378-case replay passed**, zero failures/skips. All four graphical unit checks ran in full/replay.
- **1,374-case headless CI selection passed**, all required regressions present, exactly four intended graphical exclusions.
- **Debug, Release and complete Swift concurrency builds passed**.
- **13 CI helper tests passed**, repository/history security scan passed (299 tracked files, 648 history objects, no issue categories), `git diff --check` passed.

Evidence: `Evidence/Milestone38L3R3/Complete/commands.json`, xcresult bundles, summaries/test trees/logs, `prepared-build-hashes-after-ci.json`, `preservation.json`, and `Evidence/Milestone38L3R3/CILane/gate.json`. Final code was verified in a fresh `DerivedData/Milestone38L3R3-OriginFinal` directory after an incremental build referenced an obsolete Domain module and could not resolve the new timing type. This was a build artifact issue, not a runtime test failure; fresh full/replay/concurrency builds pass with checks intact. No final-run test flakiness was observed.

The R2 speech accumulator, speech resource configuration, waveform/pill, view, formatting and other unchanged files are verified against the turn-start baseline. No staged files; HEAD remains `24db5c924f8598c6971c771e41f1678262e54379`.

Prepared Debug test app: `DerivedData/Milestone38L3R3-OriginFinal/Build/Products/Debug/Wesley Flow.app`, **38L3R3 / 38.3.3**. The standard running copy has **not been replaced or quit** in this follow-up. The user was asked to confirm that needed transcript text is saved and clipboard recovery resolved before a safe standard-copy handoff. No answer to that state check has been received at this checkpoint, so dependent app replacement/launch remains pending. Do not start a second copy alongside the existing one. R3 ChatGPT physical insertion and the original activation-change mechanism remain unverified; two-minute R2 speech/content preservation remains user-confirmed.
