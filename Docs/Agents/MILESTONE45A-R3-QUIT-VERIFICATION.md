# Milestone 45A-R3 — normal quit verification and Agent pill clicks

Build 45.0.4 · 1 November 2026. Preserves all existing uncommitted 45A/R1/R2 work on main.

## Confirmed findings and limits

The user reported that WhatsApp visibly closed while the pill stayed on Processing and then said Agent needs review. The saved local close-task summaries contain two needsReview records with generic native-failure-or-unverified diagnostics and no receipts, alongside an earlier verified normal termination. Read-only inspection found no current WhatsApp main application; separate Intents and notification-service extensions remained. Those extensions are separate processes and are not targets of app quit.

The previous NativePersonalApps.close held NSRunningApplication objects and polled isTerminated plus kill(pid, 0) for ten seconds, then threw a generic verification error. Signal 0 cannot distinguish a zombie from a live process. A slower shutdown or stale native registration could therefore leave the UI waiting and then lose useful outcome details. The old records do not establish exactly when WhatsApp exited or distinguish those causes retrospectively. This report does not claim a physical reproduction or prove that the app had fully quit before the old deadline.

A separate, confirmed code defect was in pillClicked: only a short list of Agent status strings opened Command Mode. Agent needs review, Done and several other Agent results could fall through into ordinary dictation. Clicking an Agent outcome now opens its details; it never starts a new capture or retries the action.

## Implementation

NativePersonalApps.close delegates to NativeAppClosing after validating the installed app target. The native environment binds the exact original main-app process IDs and public libproc start timestamps, retains the corresponding NSRunningApplication objects, and sends one normal termination request per original live instance. It never force-quits, dismisses save prompts, repeats quit requests or terminates a replacement instance. Public process state handles exited processes, zombies, stale registration and PID reuse. Signal 0 is used only as a read-only missing-process fallback; it sends no termination signal.

The foreground task performs up to eight 100 ms observation waits. Confirmed exit displays App closed. Slower shutdown returns a scoped unverified receipt and displays Quit pending in both the pill and task details, releasing the command's busy state so Fn can work. A separate read-only observer checks scoped pending/refused requests for up to thirty seconds. A refused native request is never sent again; if the original process exits afterward, the observer can still confirm the requested outcome without claiming which action caused that exit. A confirmed original exit with no current replacement updates the same receipt/task to verified; refusal, replacement and unavailable metadata have specific states. If the observation window ends without proof, Check app explains that automatic observation stopped. Merely hiding an app window never proves full process termination.

PersonalAppCloseObservation carries a unique observation token, target bundle ID and original process identities in an optional backward-compatible receipt field. PersonalAgentEngine.reconcileAppClose accepts only a matching pending close step and token. It never invokes the tool runner, creates a new task or automatically executes remaining routine steps. Remaining steps require fresh review. In a multi-app routine, an earlier successful close cannot hide a later pending close. Old uncertain records without these scoped receipts are preserved; they are not retroactively declared successful.

Late observations can update saved records, but cannot replace a newer Fn/Agent recording, another command's HUD, an active rewrite or a pending review/question. Observers are bounded, canceled on app shutdown or explicit conversation cancellation, and stopped when their task is deleted. They do not run a new capture, touch the clipboard, inspect app content or send communications.

The specific wording “Now I want you to close the WhatsApp” also resolves deterministically: leading now/right now introductions are supported, and a standalone target article is removed only after checking the full installed app name. A genuinely installed app named The WhatsApp therefore retains exact-name priority.

Fn waveform, Transcribing…/pill dismissal, speech session/range logic, key bindings, secure-field checks and insertion services are unchanged. No model/cloud call, download, permission expansion or lowered memory reserve is added. No live WhatsApp close was performed by automated tests.

## User-operated acceptance

1. Confirm 45.0.4 / 45A-R3. Hold the Agent key and say “I want you to open WhatsApp”. Release and confirm the app opens.
2. Hold again and say “Now I want you to close the WhatsApp”. The pill should show Closing app, followed by App closed once process exit is proven. A slower shutdown can briefly show Quit pending and then update automatically.
3. Click the completed/pending/error Agent pill. It must open Command Mode with task details, without starting the microphone, inserting text or issuing another quit.
4. Use a disposable unsaved document in another app to test its native save prompt. Ask to close that app. Wesley Flow must leave the prompt to you and show pending/refused/check status rather than falsely claiming the app closed. Choose your own save/cancel action. No force quit occurs.
5. While a quit is pending, click an editable field and hold Fn. Verify normal dictation and release-to-insert. A late quit observation must not replace the waveform/Transcribing state or insert Agent text. Check that clipboard contents remain yours.
6. Repeat open/close, rapid release, cancellation and a fullscreen app. Each request should invoke normal quit at most once. If you manually reopen an app while its old quit is being observed, the new instance must be left alone and the result must say App reopened.
7. If a result remains uncertain, inspect its exact receipt. A missing/denied process observation or an unfinished native prompt must stay honest. Never replay an uncertain quit automatically, and never mark older unknown records verified simply because the app is closed now.

## Verification

Passed 507 focused cases; 1883 full cases and matching replay, zero failures; Debug, Release and complete Swift concurrency builds; 13 CI unit tests; repository/history checks and separate new-file secret scan. All 9 protected voice/shortcut/insertion/speech files match the 45.0.3 baseline. A fresh final build folder was used; frozen source hashes were checked after verification. Synthetic quit tests cover delayed exit, save prompts, refusal, process zombies, PID reuse/relaunch, bounded observation expiry/cancellation, wrong-token rejection, no duplicate execution, partial routines and Fn isolation. No live app was quit by the fixture tests. A separate public libproc probe read only its own process and confirmed the native metadata API on this host. Physical acceptance remains pending.

Release executable SHA-256: `921657cb14f26754bb010a67447b83798f01c46c18c36e8eaad16a9299fab9fd`. Deep/strict local ad-hoc signing verification passed; this is a local test build, not notarized distribution. Evidence: `Evidence/Milestone45A-R3/manifest.json`, xcresults, logs and source hashes. Installation is recorded separately in `Evidence/Milestone45A-R3/installation.json`. No branch, commit or push was created. Old receipts without close-observation fields still decode. Earlier uncertain records without scoped native tokens remain preserved and are not automatically declared successful.

Publication note: this implementation report records its original handoff. Later user acceptance and source publication are recorded in [the build 45 checkpoint](BUILD45-PUBLICATION-CHECKPOINT.md).
