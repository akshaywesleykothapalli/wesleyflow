# Milestone 45A — 100-command implementation

Build 45.0.1 · 31 October 2026 · based on main 3771f99fc8adc06e4d517604a48d95d6923f7c59. Implementation handoff was uncommitted on main; subsequent publication is tracked in [the build 45 checkpoint](BUILD45-PUBLICATION-CHECKPOINT.md). No branch, dependency, cloud API, model download or inference was added.

## Result and scope

The [original 100-entry roadmap](COMMAND-ROADMAP-100.md) now has typed command or context paths, native adapters, review and result handling, plus a catalog in the existing Command Mode Help. The [complete guide](COMMAND-GUIDE-100.md) maps every original ID to actual behavior. All 100 are addressed; this does not mean all 100 are autonomous or physically accepted.

Two entries intentionally require native selection: Safari Add Bookmark (026) and Spotify album search (072). The user explicitly chose native Spotify selection over account/cloud integration. Browser menu handoffs and chat links retain unverified receipts. Brave bookmark opening additionally requires the native bookmark item’s HTTPS URL metadata; missing metadata is unsupported, and bookmarklets/credential-bearing URLs are rejected. Hardware, English semantic menus, app version, permissions and installed apps constrain availability. Lock Screen requires the native own-app NSMenu or own Accessibility menu bar to expose the unique semantic Lock Screen Control-Command-Q item; absence is reported unsupported. Podcasts speed requires a native 1.5× menu control. Brightness requires a supported IOKit display or the exact native Settings slider. Low Power Mode uses the supported Settings control and public ProcessInfo readback, without privileged helpers.

This remains a typed deterministic agent with explicit target/date questions, not arbitrary computer control or unrestricted natural-language AI. Unknown commands fail transparently; they never become dictation, shell commands or submitted conversations.

## Production paths

`PersonalAgentDialogue` and `PersonalConversation` admit Mac/window/browser/file/object/record/menu/mail/timer/schedule commands. `NativeAgentResolution` binds native targets and preserves `requiresReview`; `NativePersonalTools` dispatches the allowlisted typed tools. `PersonalAgentEngine` owns durable execution, cancellation, receipts, paused tasks, one-use continuations and exact human-observation acknowledgement. `SystemWideDictationCoordinator.contextCommand` binds recent Trash, reviewed messages, saved routines and interrupted-task references. Pending literal replies take precedence over context interpretation.

New Domain contracts are PersonalMacControl, PersonalWindowLayout, PersonalBrowserExtra, PersonalFileAction, PersonalObjectCommand, PersonalRecordCommand, PersonalMenuAction, PersonalMailCommand, PersonalScreenCapture, PersonalTimerControl, PersonalScheduledMessage, PersonalRoutine and PersonalRoadmapCatalog. Matching Native adapters live under Packages/WesleyFlowCore/Sources/SystemOperations. UI changes are limited to existing review/help/status and routine/scheduled-draft controls.

No dictation input, native shortcut or insertion implementation changed. Existing Fn waveform, Transcribing… and disappearing completion behavior remain. Agent commands never insert/paste into another app. Screenshot/export operations do not write the clipboard. Existing recovery leases remain preserved.

## Boundaries and verification

Native files use descriptor-relative no-follow identities, exclusive destinations and digest readback; actual disposable fixture copy/move/archive/PDF effects are tested. Notes binds account/note/version and refuses protected/shared/attachment-dependent edits. Calendar and reminder changes bind calendar/item/fingerprint, reject attendees/recurrence and require final review. Calendar show matches the exact EventKit external UID in Calendar. Mail final send revalidates recipients, body, exact attachment paths, inode identities and digests before dispatch. Due-message draft claims and continuation source replacement are durable and one-use; uncertain effects never auto-replay.

Screenshots require explicit review and native consent, restore the originating app before capture, exclude new Wesley review/HUD windows and write exclusive local PNGs. No screen, contacts, mail, notes or calendar data were collected during automated verification. Production AppleScript templates were compiled through injected execution seams without executing native app effects. Tests do not prove microphone/TCC/AX/native app behavior.

The queue schema adds tools/states and optional review/completion/continuation metadata. Older records decode with defaults. Do not downgrade a queue containing new tools or paused state to build 44; preserve the queue and inspect unfinished work first. Scheduled drafts and routines are bounded separate local stores under the existing Agent data directory. No saved approval survives a routine edit or fresh run.

## User-operated acceptance

1. Confirm About/Command Mode says 45.0.1 / 45A. Use only /Applications/Wesley Flow.app. Resolve any existing recovery warning and quit normally before replacing a running copy.
2. Click an editable text field, hold Fn, dictate a control sentence and release. Check insertion once, Transcribing… then pill hidden, and no Agent task. Hold the configured Agent key and say “Open Safari”, then “Close Safari”; confirm only the intended app changes. Repeat Fn after each. Repeat on another app’s fullscreen Space, and after 5/20/45-second Agent recordings; cancel/release/rapid repeats must not create two captures or duplicate tasks.
3. Say “What is my battery level”, “Set a tea timer for four minutes”, “Show my active timers”, “Cancel my tea timer”. Check owned notification behavior; other apps’ notifications stay untouched.
4. With harmless test windows, try each half/quarter/centre and next display. Unsupported sizes/displays must report failure rather than move another window. Verify brightness/audio device/Low Power controls on your hardware and permission denial without forcing permission changes.
5. Create disposable Drafts/Projects folders and agenda.pdf in the stated allowed roots. Try rename/copy/move/reveal/info/compress, refuse conflicts and symlinks, and restore only an immediately recorded reviewed Trash action. Inspect every filesystem destination.
6. In a disposable default Notes account/folder, create Ideas and a uniquely titled note; exercise find/open/append/rename/move/duplicate/plain-text PDF and reviewed Recently Deleted. Inspect note content, actual PDF and recovery. Permission denial or unsupported account must stop honestly.
7. Use a disposable explicitly named Reminders list/calendar. Exercise IDs 051–070 from the guide; inspect title/date/timezone/priority/location/alerts. Verify AM/PM questions, duplicate names, changed-target rejection and refusal of attendee/recurring events. Free-time suggestions cover the stated calendar only.
8. Use disposable browser tabs/bookmarks and local Music items. Inspect reopen/close/duplicate/find/zoom results. Safari bookmarking requires native confirmation. Spotify album search requires your selection. Qualify duplicate Music titles with “by ARTIST from album ALBUM”. Check actual playback and Podcasts speed rather than trusting dispatch.
9. For Mail/Contacts/chat tests, use your own test recipient. Draft creation and chat opening must send nothing. Inspect exact final email/message recipients, body and attachments; test edited/changed files before sending. Send only if you explicitly intend that communication. Scheduled message 089 must stay a local draft until due-time review and fresh Send; cancellation cannot claim recall.
10. Save two harmless app-opening steps as Morning setup, edit with a complete replacement list and run after reviewing exact steps. Set up Development apps/Work windows with your choices. Pause between steps; restart and continue only pending verified-safe steps. Repeated Continue, final transcript callbacks and due-draft Review must not duplicate execution. Uncertain native effects require inspection; acknowledging observation never invokes a tool.

For each command category also deny its permission, cancel during preparation/review/effect, change the target while review is open, and restart. Record actual outcomes separately. No physical acceptance is claimed by the automated results.

## Primary native references

Apple public SDK interfaces and installed app scripting dictionaries were checked. See [ProcessInfo low-power state](https://developer.apple.com/documentation/Foundation/ProcessInfo/isLowPowerModeEnabled), [IOPowerSources](https://developer.apple.com/documentation/iokit/iopowersources_h), [display brightness](https://developer.apple.com/documentation/iokit/1574900-iodisplaygetfloatparameter), [Apple Archive](https://developer.apple.com/documentation/accelerate/compressing-file-system-directories), [Calendar attendees](https://developer.apple.com/documentation/eventkit/ekcalendaritem/hasattendees), [Notes recovery](https://support.apple.com/en-ie/guide/notes/not5585d71a8/4.13/mac/27) and [WhatsApp click-to-chat](https://faq.whatsapp.com/5913398998672934). Native availability can differ by app/system version.

## Final verification and installation

Passed: 428 focused cases; 1,804 full cases and matching 1,804-case replay, zero failures; Debug, Release and complete Swift concurrency builds; 13 CI unit tests; repository/history checks and separate new-file secret scan. Four existing graphical acceptance cases remain explicitly manual. The 9 protected voice/shortcut/insertion/speech source files match the baseline hashes. Release executable SHA-256: `a9f78295779bc882651338c118dd06fff75f0c605afc9096f0f41a6da8714d16`. Local ad-hoc signature passed deep/strict verification; this is a local test build, not a notarized distribution. Physical acceptance remains pending. Evidence: `Evidence/Milestone45A/manifest.json`, xcresults, logs, source hashes, baseline bundle and patch. Installation status is recorded separately in `Evidence/Milestone45A/installation.json`.

Publication note: this implementation report records its original handoff. Later user acceptance and source publication are recorded in [the build 45 checkpoint](BUILD45-PUBLICATION-CHECKPOINT.md).
