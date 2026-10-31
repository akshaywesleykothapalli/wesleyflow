# Milestone 44A — Mac audio and browser/player actions

Build 44.0.1. The user confirmed 43.0.1 working and requested both more Mac commands and more app actions. This adds the bounded native controls below through the existing voice/text planner and durable executor. Physical acceptance of these new effects remains pending.

## Commands

- Set volume to forty-five percent / Set the volume to 40%
- Volume up / Turn down the volume (10 percentage points, clamped 0–100)
- Mute / Unmute audio / What is the volume
- New tab in Safari / Open a new window in Brave
- Next tab in Brave / Switch to the previous tab in Safari
- Next track in Spotify / Play the previous song in Music

Audio status and mutation receipts show the actual output volume and mute state. Setting volume does not automatically unmute; both final settings are visible. Browser commands name Safari or Brave explicitly, select that browser's front window, and wrap at the first/last tab. With no window, New tab creates a blank window. Tab switching requires the browser already running and an existing window. Creation uses about:blank, never a user-provided script or URL. The Help command library includes the new examples. Existing generic app/window, folder, browser search, Notes, Reminders, Calendar, timers and approved Messages capabilities remain.

## Implementation and boundaries

Domain/PersonalControls.swift contains validated Codable payloads for systemAudio/browserControl, closed phrase parsing, English numeric values 0–100, and identical whole-request repetition folding. PersonalConversation.quick and PersonalAgentDialogue intake route commands before generic app lookup, after pending reply payload handling. Notes and message bodies stay literal. Invalid/out-of-range or incomplete control requests are rejected rather than silently mapped to another action. Arbitrary app/browser/plugin commands and arbitrary phrasing are not enabled.

NativePersonalControls uses fixed NSAppleScript templates and installed app identities, never shell, UI keystrokes, JavaScript, clipboard publication or webpage content extraction. Only fixed enum choices and a validated integer enter scripts. Audio uses Standard Additions output volume/mute APIs with readback; devices with fixed volume or unsupported controls can fail verification. Output volume changes require readback within one percentage point; mute/unmute require exact Boolean state. Readback reports configured output, not measured acoustic loudness.

Browser scripts check bounded tab counts (maximum 500), use the named browser's window ID, mutate only creation or active-tab selection, and verify the resulting window/tab count or selection. They do not close tabs, reload potentially unsaved pages, read page titles/URLs/contents or enable browser JavaScript automation. Existing native Automation consent applies. Missing browsers, denied permissions, missing windows and unsupported native behavior fail conservatively. App startup and user changes can affect native state; fixtures do not prove every browser version or window configuration.

Music/Spotify next/previous use fixed native track commands in already running players. Track identity is read before the one command, then observed up to 12 times with 150 ms pauses; a changed identity is required for success. Only readback is repeated, never the command. Cancellation is checked between observations. Player availability, a current track, queue state, transition delays, repeat mode or Previous restarting the same track can prevent verified completion. Playback/audio quality and streaming delivery are not inspected. Permission denial and uncertain effects remain needsReview with no automatic replay.

New tools use the existing write-ahead journal, one active task, cancellation boundaries, typed receipts and restart recovery. Cancellation after a possible effect does not undo the effect. No new model execution/download, cloud AI, communications, destructive folder action, entitlement or unrelated file capability is introduced. Existing explicit Messages/Trash approval and 4 GiB model admission remain. An old build cannot decode tasks containing the new enum cases; preserve the queue and do not downgrade such records.

Fn dictation, Agent key handling, audio ownership, secure field/focus rules and clipboard-free insertion implementations were not changed. Existing Agent transcripts continue into the planner and are never pasted into the foreground editor. Only the coordinator's new receipt/status display and build marker change in this pipeline. Compact HUD stays in use; clicking Audio/Browser results opens existing Command Mode without starting a recording.

## Verification

{"focused": {"exitCode": 0, "cases": 228, "failed": 0}, "test": {"exitCode": 0, "cases": 1604, "failed": 0}, "replay": {"exitCode": 0, "cases": 1604, "failed": 0}, "release": {"exitCode": 0}, "concurrency": {"exitCode": 0}}. Focused/full headless Debug, independent test-without-building replay, Release and Swift concurrency builds all passed.

Tests cover spoken numeric boundaries, invalid payload/range rejection, explicit browser identities, new tab/window/next/previous phrases, named players, unsupported and compound requests, whole speech repetition, literal note payload preservation, validated audio readback and compile-only checks for all fixed volume/browser templates. No test executes a native volume/browser/player effect or injects speech/text. Existing hotkey/insertion/approval/recovery suites also run. The four existing graphical exclusions remain manual. Release signing and microphone/Automation entitlements are verified separately.

Final evidence, source hashes and pre-change copies are in Evidence/Milestone44A. Intermediate failures/review runs are prefixed; only unprefixed final logs count. All prior uncommitted work is preserved. No stage, commit, push or merge. Canonical app target is /Applications/Wesley Flow.app; installation.json records actual normal quit, replacement and reopen. No versioned Run app copy is created.

## User-operated acceptance

Confirm 44.0.1 and marker 44A / speech38L3R3. At a safe listening level, ask What is the volume, then Set volume to 30 percent, Volume up, Mute and Unmute; compare macOS Sound settings and restore your preferred volume. A fixed-volume external device must not produce a false verified setting.

In Safari/Brave, use disposable blank tabs: New tab in Safari, New window in Brave, Next tab in Brave, Previous tab in Safari. Inspect actual selected tabs/window count. Check a stopped browser, zero windows, one tab, denied Automation and missing browser; a failed switch must not silently target another app. Repeat a whole request once in a single transcript and verify only one action. Do not assume uncertain creation failed and blindly repeat it.

With Music/Spotify already playing a disposable queue, request Next track in Spotify or Previous song in Music. Check the actual track and saved receipt. Try end-of-queue/repeat/current-track restart cases; uncertainty must not be labelled Done. Native permission dialogs require the user's own decision.

Back-to-back Fn/Agent, rapid repeats/cancellation and a clipboard sentinel remain control checks: Fn inserts dictated text and hides after Transcribing; Agent changes the requested setting/app state without inserting the spoken command or submitting any conversation. Physical results remain pending until operated by the user.

Signed Release executable SHA256: 021ca269462a1710e03e9593f9bfd022bf235b3586e83e3033681e80ef78ce20
