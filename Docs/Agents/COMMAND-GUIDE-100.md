# 100-command guide — 45.0.1

31 October 2026. All 100 roadmap entries have a routed implementation or context workflow. Native availability and permissions still apply; this is not a claim that all 100 are automatic or physically verified. Use the configured Agent hold key, release to process, and read any exact-target question or review. Fn remains ordinary dictation. Help in Command Mode contains this catalog.

Spotify album selection is assisted by explicit user choice: native album search opens; select the album and press Play in Spotify. Safari bookmarking opens its native confirmation dialog. “Inspect native result” means dispatch is known but the final state is not verified. These outcomes are never marked completed automatically.

Calendar and Reminders use the default calendar/list, or append “in Work calendar” / “in Shopping list”. Duplicate item names require a more specific target; no arbitrary item is chosen. Dates without AM/PM ask for clarification. Free-time suggestions inspect only the stated calendar. Notes use the default Notes account; protected/shared or attachment-dependent edits are refused. PDF exports contain plain text, not rich formatting or attachments.

Native app writes are not atomic with simultaneous user edits. Detected target/version changes stop the action; avoid editing the same item during execution and inspect any uncertain result. Sound-device commands need the actual unique device name shown by macOS; personal aliases such as “my headphones” work only when they match that name.

Files are scoped to direct names in Documents, Desktop or Downloads. Moves do not overwrite; copies are bounded to 64 MiB total, 16 MiB per file, 1,000 entries and depth 8. Packages and symlinks are refused. Compression writes an Apple Archive (.aar), not a ZIP. Partial copies on cancellation are reported for inspection, never presented as successful.

Mail drafts/replies retain literal content. Sending always requires final recipient/body/attachment review. A native send acknowledgement does not prove delivery. Scheduled messages are **local drafts with due-time review notifications**, requiring a fresh Send approval, not unattended sends. Contact/chat actions never send text.

Routines contain up to eight explicit typed steps. Set up Development apps and Work windows once with your exact commands. Save/edit/run requires exact review; previous approval never carries over. Pause uses the current task’s button while executing; the microphone is not opened concurrently with an active task. Continue offers only pending steps after verified effects. An uncertain step must be inspected and explicitly acknowledged as observed by the user before continuation; it is never retried automatically.

| ID | Say | Behavior | Scope / limitation |
|---|---|---|---|
| 001 | Increase the brightness | Native action | One display; IOKit or an unambiguous native brightness slider. |
| 002 | Set brightness to fifty percent | Native action | One display; exact native setting readback. |
| 003 | Dim the screen | Native action | One display; native control availability required. |
| 004 | What is my battery level | Native action | A supported battery must be present. |
| 005 | Turn on Low Power Mode | Review first | Native English System Settings control must be available; no administrator bypass. |
| 006 | Lock my Mac | Review first | Native Lock Screen command and inactive-session observation. |
| 007 | Take a screenshot of this display | Review first | Screen Recording consent; local PNG; original app restored. |
| 008 | Take a screenshot of an area | Review first | Native region selection; Escape cancels without saving. |
| 009 | Switch sound output to my headphones | Native action | Exact connected audio device; ambiguous names need qualification. |
| 010 | Use the built-in microphone | Native action | No active capture; default input device readback. |
| 011 | Move Safari to the left half | Native action | Installed target and required native permissions; actual state verified where supported. |
| 012 | Move Brave to the right half | Native action | Installed target and required native permissions; actual state verified where supported. |
| 013 | Move Notes to the top half | Native action | Installed target and required native permissions; actual state verified where supported. |
| 014 | Move Calendar to the bottom half | Native action | Installed target and required native permissions; actual state verified where supported. |
| 015 | Move Safari to the top-left quarter | Native action | Installed target and required native permissions; actual state verified where supported. |
| 016 | Move Brave to the top-right quarter | Native action | Installed target and required native permissions; actual state verified where supported. |
| 017 | Move Notes to the bottom-left quarter | Native action | Installed target and required native permissions; actual state verified where supported. |
| 018 | Move Reminders to the bottom-right quarter | Native action | Installed target and required native permissions; actual state verified where supported. |
| 019 | Move VS Code to the next display | Native action | At least two connected displays and one selected app window. |
| 020 | Centre the Safari window | Native action | Installed target and required native permissions; actual state verified where supported. |
| 021 | Reopen the last closed tab in Safari | Inspect native result | Native Safari menu command; inspect the restored tab. |
| 022 | Close the current tab in Brave | Review first | Exact Brave tab identity/URL/title; native unsaved-work prompts remain. |
| 023 | Duplicate this tab in Safari | Native action | Exact reviewed Safari HTTPS URL; page loading not read. |
| 024 | Find the tab named Documentation in Brave | Native action | Unique bounded title match; no page bodies. |
| 025 | Find my example.com tab in Safari | Native action | Unique exact domain match; no page bodies. |
| 026 | Bookmark this page in Safari | Finish in native app | Choose the destination and confirm in Safari’s native Add Bookmark dialog. |
| 027 | Open my Travel bookmark in Brave | Inspect native result | Unique native bookmark-menu leaf with HTTPS URL metadata required; unavailable metadata fails safely; page loading unverified. |
| 028 | Zoom in on this Safari tab | Inspect native result | Native semantic menu; zoom level cannot always be read back. |
| 029 | Zoom out on this Brave tab | Inspect native result | Native semantic menu; zoom level cannot always be read back. |
| 030 | Reset zoom in Safari | Inspect native result | Native semantic menu; inspect resulting zoom. |
| 031 | Rename folder Drafts to Archive in Documents | Review first | Exclusive destination; same scoped directory; no overwrite. |
| 032 | Move folder Projects from Desktop to Documents | Review first | Scoped roots and same-volume exclusive move. |
| 033 | Duplicate folder Projects in Documents | Review first | Proposed new copy name is shown for review; bounded contents. |
| 034 | Rename file draft.txt to final.txt in Documents | Review first | Exact extension/name; no path traversal or overwrite. |
| 035 | Copy file agenda.pdf from Desktop to Documents | Review first | Bounded byte copy with digest readback; no overwrite. |
| 036 | Move file agenda.pdf to Downloads | Review first | Asks which source root if omitted. |
| 037 | Reveal file agenda.pdf in Finder | Native action | Asks which source root if omitted; exact Finder selection. |
| 038 | Show information for folder Projects in Documents | Native action | Directory entry metadata, not recursive folder size. |
| 039 | Compress folder Projects in Documents | Review first | Bounded verified staging copy to LZFSE Apple Archive (.aar). |
| 040 | Restore the folder I just trashed | Review first · prior context required | Just-completed Trash receipt; exact identity/root; no destination conflict. |
| 041 | Show my Notes folders | Native action | Installed target and required native permissions; actual state verified where supported. |
| 042 | Create a Notes folder called Ideas | Native action | Installed target and required native permissions; actual state verified where supported. |
| 043 | Find notes titled Project Plan | Native action | Default Notes account; bounded title metadata. |
| 044 | Open the note titled Project Plan | Native action | Installed target and required native permissions; actual state verified where supported. |
| 045 | Append Buy batteries to my Shopping note | Review first | Attachment-free note; literal append; concurrent changes refused. |
| 046 | Rename my note Project Plan to Launch Plan | Review first | Installed target and required native permissions; actual state verified where supported. |
| 047 | Move my Project Plan note to Work | Review first | Installed target and required native permissions; actual state verified where supported. |
| 048 | Duplicate my Project Plan note | Review first | Attachment-free note; original untouched. |
| 049 | Export my Project Plan note as PDF | Review first | Plain-text PDF, attachment-free; Documents; no overwrite. |
| 050 | Move my Old Draft note to Recently Deleted | Review first | Upgraded Notes account, ordinary default folder only; recovery readback can remain unverified. |
| 051 | Show reminders due today | Native action | Default list or explicit “in Shopping list” scope. |
| 052 | Show overdue reminders | Native action | Default list or explicitly named list. |
| 053 | Create a reminder list called Work | Review first | Exact list/source; duplicate names refused. |
| 054 | Mark Buy milk as complete | Review first | Installed target and required native permissions; actual state verified where supported. |
| 055 | Move Call Sam to tomorrow at ten | Review first | Installed target and required native permissions; actual state verified where supported. |
| 056 | Rename Buy milk to Buy oat milk | Review first | Installed target and required native permissions; actual state verified where supported. |
| 057 | Move Buy milk to my Shopping list | Review first | Installed target and required native permissions; actual state verified where supported. |
| 058 | Flag Call Sam as important | Review first | Installed target and required native permissions; actual state verified where supported. |
| 059 | Delete the reminder Buy milk | Review first | Native deletion is not guaranteed recoverable; final review required. |
| 060 | Find reminders mentioning passport | Native action | Installed target and required native permissions; actual state verified where supported. |
| 061 | What is on my calendar tomorrow | Native action | Default or explicitly named calendar; bounded date range. |
| 062 | Find a free hour tomorrow afternoon | Native action | Only the stated calendar; other calendars are not checked. |
| 063 | Find my dentist appointment | Native action | Installed target and required native permissions; actual state verified where supported. |
| 064 | Open my next meeting | Native action | Exact EventKit external UID matched to native Calendar show. |
| 065 | Rename Lunch with Sam to Lunch with team | Review first | Bare rename asks whether this is a reminder or calendar event. |
| 066 | Move my dentist appointment to Friday at three | Review first | Asks for AM/PM or exact ISO time if ambiguous. |
| 067 | Extend my focus block by thirty minutes | Review first | Installed target and required native permissions; actual state verified where supported. |
| 068 | Cancel my personal focus block | Review first | Personal, nonrecurring event with no attendees; no silent invitation cancellation. |
| 069 | Remind me fifteen minutes before my appointment | Review first | Installed target and required native permissions; actual state verified where supported. |
| 070 | Show my next event location | Native action | Installed target and required native permissions; actual state verified where supported. |
| 071 | Play the song named Imagine in Music | Native action | Unique available Music library track; no cloud catalog lookup. |
| 072 | Play the album named Discovery in Spotify | Finish in native app | Native Spotify album search; user selects the matching album and plays it. |
| 073 | Play my Focus playlist in Music | Native action | Unique saved Music playlist. |
| 074 | Turn shuffle on in Spotify | Native action | Spotify must be installed and native control available. |
| 075 | Turn shuffle off in Music | Native action | Installed target and required native permissions; actual state verified where supported. |
| 076 | Repeat this track in Music | Native action | Installed target and required native permissions; actual state verified where supported. |
| 077 | Turn repeat off in Music | Native action | Installed target and required native permissions; actual state verified where supported. |
| 078 | Skip forward thirty seconds in Music | Native action | Installed target and required native permissions; actual state verified where supported. |
| 079 | Play this podcast at one and a half speed | Native action | Apple Podcasts must expose the native 1.5× control. |
| 080 | What song is playing in Spotify | Native action | Native track metadata; acoustic output not inspected. |
| 081 | Draft an email to Sam about Friday | Native action | Exact email/contact resolution; draft creation never sends. |
| 082 | Draft a reply saying I can attend | Review first | One selected Mail message; literal reply body; no send. |
| 083 | Attach agenda.pdf to this email draft | Review first | Exact draft/file scope and attachment bytes; opaque cache paths remain unverified. |
| 084 | Send the email draft I just reviewed | Review first | Sender, all recipients, body and attachment identities/digests rechecked; delivery unverified. |
| 085 | Find Sam in Contacts | Native action | Requested names only; no unrelated phone-number enumeration. |
| 086 | Open my chat with Sam in Messages | Inspect native result | Exact number; Messages app-bound handoff; no message text. |
| 087 | Open my chat with Sam in WhatsApp | Inspect native result | Exact international number; native wa.me handoff; no text sent. |
| 088 | Show the phone numbers for my selected contact | Native action | Recent unique Agent contact or an exact-name question; other app selection is not guessed. |
| 089 | Schedule a reviewed message for tomorrow | Review first · prior context required | Local draft and due-time review notification; no unattended sending. |
| 090 | Cancel my scheduled message to Sam | Review first | Only an exact pending local draft; never a dispatched-message recall. |
| 091 | Save these reviewed steps as Morning setup | Review first · prior context required | Only the exact recent/reviewed typed steps; saving executes none. |
| 092 | Edit my Morning setup routine | Native action · prior context required | One complete replacement command per line; compare-and-swap save. |
| 093 | Run my Morning setup routine | Review first · prior context required | Fresh plan IDs, target validation and mandatory review each run. |
| 094 | Open my development apps together | Review first · prior context required | Explicitly define the Development apps group first; no guessed apps. |
| 095 | Arrange my work windows | Review first · prior context required | Explicitly define Work windows first; no guessed layout. |
| 096 | Set a tea timer for four minutes | Native action | Named owned notification; due time bound to request. |
| 097 | Show my active timers | Native action | Only Wesley Flow-owned pending timers. |
| 098 | Cancel my tea timer | Native action | Exact unique pending timer name; no delivered notification recall. |
| 099 | Pause this routine after the current step | Native action · prior context required | Pause button or typed control while executing; capture remains exclusive. |
| 100 | Continue this interrupted routine | Review first · prior context required | Fresh review; verified steps skipped; uncertain effects require observation first; no duplicate continuation. |
