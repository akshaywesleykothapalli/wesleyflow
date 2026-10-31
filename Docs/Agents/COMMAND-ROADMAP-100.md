# Original command roadmap — 100 additions

Original planning document · 31 October 2026 · baseline build 44.0.1

Implementation update: see [45A implementation](MILESTONE45A-100-COMMANDS.md) and the [100-command guide](COMMAND-GUIDE-100.md). The original requirements below are retained for traceability; the guide records actual scope, assisted actions and native limitations.

Original planning statement (superseded by the implementation guide above): all 100 entries below were **proposed, not implemented or promised compatible**. They are a backlog for review and incremental delivery. Example speech describes desired behavior, not syntax accepted by the current build. Platform and app APIs must be checked before selecting an implementation; unsupported capabilities stay unavailable rather than falling back to guessed keystrokes, generated scripts or cloud services.

Current build already supports separate Fn dictation and Agent commands, generic installed-app opening/closing and selected window states, scoped folder operations, named-browser searches, audio volume/mute, Safari/Brave tab creation/switching and basic Music/Spotify controls. See [44A implementation](MILESTONE44A-MAC-APP-CONTROLS.md) and [43A folder commands](MILESTONE43A-FOLDERS-BROWSERS-COMMANDS.md). These existing features are not counted toward the 100 proposals.

## Delivery rules

P1 means start with a small feasibility check, then a bounded implementation; P2 needs additional targeting or integration work; P3 depends on deeper communication/privacy/approval design. Priorities are suggested implementation order, not claims that an API is available. Native permissions remain user-controlled. No model downloads, cloud AI fallback or relaxation of the existing 4 GiB admission rule. Normal dictation remains separate from Agent execution.

For each selected command: settle exact target/scope and supported phrasing; validate the native API; add a typed tool and permission boundary; bind any approval to the exact final action; verify the observed result or report dispatch/uncertainty explicitly; test denial, ambiguity, duplicate transcripts, cancellation, restart and no unintended insertion; then require user-operated native acceptance. Effects involving deletion, overwrite, communications or private content access require explicit scope and appropriate review. Never auto-replay an uncertain effect.

## Mac settings and capture — P1

| ID | Example command | Intended result | Acceptance requirement / constraint |
|---|---|---|---|
| 001 | “Increase the brightness” | Raise a supported display by one bounded step | Display API feasibility; read back brightness |
| 002 | “Set brightness to fifty percent” | Set a supported display to an exact level | Unsupported external displays fail transparently |
| 003 | “Dim the screen” | Lower brightness by one bounded step | Read back value; never claim measured luminance |
| 004 | “What is my battery level” | Show charge and charging state | Read-only native power status |
| 005 | “Turn on Low Power Mode” | Request the supported energy setting | Feasibility gate; native confirmation; no sudo |
| 006 | “Lock my Mac” | Lock the current session | Explicit request; verify available session transition |
| 007 | “Take a screenshot of this display” | Save a capture to an agreed screenshots folder | Screen Recording consent; explicit destination; no automatic upload |
| 008 | “Take a screenshot of an area” | Open native region selection and save the chosen region | User selects region; cancellation saves nothing |
| 009 | “Switch sound output to my headphones” | Choose an exact available output device | Disambiguate matching devices; read back selection |
| 010 | “Use the built-in microphone” | Choose the requested input device | Never switch during active recording; read back device |

## Window layouts and displays — P1

| ID | Example command | Intended result | Acceptance requirement / constraint |
|---|---|---|---|
| 011 | “Move Safari to the left half” | Tile the selected window to the left visible half | Accessibility; verify bounds and owner |
| 012 | “Move Brave to the right half” | Tile the selected window to the right visible half | No ambiguous window selection |
| 013 | “Move Notes to the top half” | Tile the selected window to the top visible half | Respect app minimum size |
| 014 | “Move Calendar to the bottom half” | Tile the selected window to the bottom visible half | Verify bounds with tolerance |
| 015 | “Move Safari to the top-left quarter” | Tile to the top-left visible quarter | Respect display coordinates and size constraints |
| 016 | “Move Brave to the top-right quarter” | Tile to the top-right visible quarter | Verify target process/window identity |
| 017 | “Move Notes to the bottom-left quarter” | Tile to the bottom-left visible quarter | Fail if unsupported rather than moving another window |
| 018 | “Move Reminders to the bottom-right quarter” | Tile to the bottom-right visible quarter | Preserve unrelated windows |
| 019 | “Move VS Code to the next display” | Move the selected window to a named/next connected display | Disambiguate displays; preserve usable bounds |
| 020 | “Centre the Safari window” | Centre the selected window without resizing | Use its current display visible frame |

## Safari and Brave tabs — P2

| ID | Example command | Intended result | Acceptance requirement / constraint |
|---|---|---|---|
| 021 | “Reopen the last closed tab in Safari” | Restore a recently closed tab if a supported API exists | Feasibility gate; no global keystroke guessing |
| 022 | “Close the current tab in Brave” | Close only the reviewed tab | Review bound tab/window identity; respect unsaved work |
| 023 | “Duplicate this tab in Safari” | Create a duplicate in the named browser | Read URL metadata only after explicit permission; reject unsafe schemes |
| 024 | “Find the tab named Documentation in Brave” | Select a uniquely matching tab title | Opt-in tab metadata; ambiguity asks rather than guessing |
| 025 | “Find my example.com tab in Safari” | Select a matching domain tab | Read-only URL metadata; never read page bodies |
| 026 | “Bookmark this page in Safari” | Save a reviewed title/URL to an agreed folder | Native API feasibility; confirmation and duplicate handling |
| 027 | “Open my Travel bookmark in Brave” | Open a uniquely matching saved bookmark | Explicit bookmark access; supported HTTPS URL |
| 028 | “Zoom in on this Safari tab” | Increase browser page zoom by a bounded step | Supported API feasibility; no injected page script |
| 029 | “Zoom out on this Brave tab” | Decrease browser page zoom by a bounded step | Verify zoom where supported |
| 030 | “Reset zoom in Safari” | Restore page zoom to normal | Unsupported browser versions fail honestly |

## Files and Finder — P2

| ID | Example command | Intended result | Acceptance requirement / constraint |
|---|---|---|---|
| 031 | “Rename folder Drafts to Archive in Documents” | Rename one exact selected folder | Review source/destination; identity check; never overwrite |
| 032 | “Move folder Projects from Desktop to Documents” | Move one exact folder between allowed locations | Review both locations; no silent conflict replacement |
| 033 | “Duplicate folder Projects in Documents” | Create a copy with an agreed new name | Bound size/time; cancellation reports partial copies |
| 034 | “Rename file draft.txt to final.txt in Documents” | Rename a scoped file | Exact extension/identity review; no traversal |
| 035 | “Copy file agenda.pdf from Desktop to Documents” | Copy one scoped file | Conflict prompt; verify size/content digest where feasible |
| 036 | “Move file agenda.pdf to Downloads” | Move a reviewed scoped file | Disambiguate source; verify destination; never overwrite |
| 037 | “Reveal file agenda.pdf in Finder” | Reveal an exact scoped file | No arbitrary external file-content reading |
| 038 | “Show information for folder Projects in Documents” | Show native metadata for an exact folder | Metadata only; permission-aware |
| 039 | “Compress folder Projects in Documents” | Create an archive beside the reviewed folder | Closed archiving implementation; no user-provided shell |
| 040 | “Restore the folder I just trashed” | Restore the exact recorded Trash item | Review original location; identity match; no conflict overwrite |

## Notes and writing — P2

| ID | Example command | Intended result | Acceptance requirement / constraint |
|---|---|---|---|
| 041 | “Show my Notes folders” | List native Notes folder names | Explicit Notes metadata consent; bounded list |
| 042 | “Create a Notes folder called Ideas” | Create a named Notes folder | Native API feasibility; verify folder identity |
| 043 | “Find notes titled Project Plan” | Search note titles in an agreed account/folder | Opt-in title metadata; do not scan all note bodies |
| 044 | “Open the note titled Project Plan” | Open one uniquely matching note | Ask on duplicates; verify selected note identity |
| 045 | “Append Buy batteries to my Shopping note” | Append literal text to a reviewed note | Exact target/content approval; preserve existing body |
| 046 | “Rename my note Project Plan to Launch Plan” | Rename a reviewed note | Check identity and existing title before changing |
| 047 | “Move my Project Plan note to Work” | Move a reviewed note between Notes folders | Native API feasibility; verify destination |
| 048 | “Duplicate my Project Plan note” | Create a clearly named copy | Preserve original; verify copied content |
| 049 | “Export my Project Plan note as PDF” | Save an explicitly selected note to an agreed folder | Export feasibility; review content access and destination |
| 050 | “Move my Old Draft note to Recently Deleted” | Delete a reviewed exact note recoverably | Native API/recovery feasibility; never permanent deletion |

## Reminders and task lists — P1

| ID | Example command | Intended result | Acceptance requirement / constraint |
|---|---|---|---|
| 051 | “Show reminders due today” | List due items from selected lists | Reminders permission; bounded private results |
| 052 | “Show overdue reminders” | List incomplete overdue items | Read-only; explicit list scope |
| 053 | “Create a reminder list called Work” | Create a named list | Check duplicate names and supported account |
| 054 | “Mark Buy milk as complete” | Complete one reviewed reminder | Disambiguate title/list; verify completion |
| 055 | “Move Call Sam to tomorrow at ten” | Reschedule a reviewed reminder | Resolve timezone/date; show exact new due time |
| 056 | “Rename Buy milk to Buy oat milk” | Change one reviewed reminder title | Bind item identity; preserve notes and due date |
| 057 | “Move Buy milk to my Shopping list” | Move one reviewed reminder | Verify target list/account supports operation |
| 058 | “Flag Call Sam as important” | Set supported priority/flag on one item | Confirm platform mapping; read back |
| 059 | “Delete the reminder Buy milk” | Delete one reviewed reminder | Explicit final approval; truthful recovery limitations |
| 060 | “Find reminders mentioning passport” | Search selected reminder titles | Explicit access; bounded results and ambiguity handling |

## Calendar and scheduling — P2

| ID | Example command | Intended result | Acceptance requirement / constraint |
|---|---|---|---|
| 061 | “What is on my calendar tomorrow” | Show an agenda for selected calendars | Calendar permission; timezone-aware dates |
| 062 | “Find a free hour tomorrow afternoon” | Suggest a free interval from explicit calendars | Read-only suggestion; no event auto-creation |
| 063 | “Find my dentist appointment” | Search bounded calendar titles/date range | Do not read attendee notes by default |
| 064 | “Open my next meeting” | Open one specific calendar event | Verify event identity; no automatic meeting join |
| 065 | “Rename Lunch with Sam to Lunch with team” | Rename a reviewed personal event | Reject attendee notifications until separately reviewed |
| 066 | “Move my dentist appointment to Friday at three” | Reschedule a reviewed personal event | Show exact date/time; conflict check; external invitations need extra review |
| 067 | “Extend my focus block by thirty minutes” | Change one reviewed event end time | Conflict check; preserve start and metadata |
| 068 | “Cancel my personal focus block” | Delete one exact personal event | Final review; no silent attendee cancellation |
| 069 | “Remind me fifteen minutes before my appointment” | Set an alert on one reviewed event | Verify alarm time; preserve other alarms |
| 070 | “Show my next event location” | Display location from one selected event | Explicit private metadata access; do not open arbitrary location URLs |

## Music and media — P2

| ID | Example command | Intended result | Acceptance requirement / constraint |
|---|---|---|---|
| 071 | “Play the song named Imagine in Music” | Select an exact available track | Disambiguate artist/library; supported native API |
| 072 | “Play the album named Discovery in Spotify” | Request a reviewed matching album | Provider/API feasibility; no credential scraping |
| 073 | “Play my Focus playlist in Music” | Play an exact saved playlist | Disambiguate playlist name; verify player context |
| 074 | “Turn shuffle on in Spotify” | Enable supported shuffle state | Native API feasibility; read back |
| 075 | “Turn shuffle off in Music” | Disable supported shuffle state | Read back the player setting |
| 076 | “Repeat this track in Music” | Enable supported single-track repeat | Read back repeat mode |
| 077 | “Turn repeat off in Music” | Disable supported repeat mode | Read back repeat mode |
| 078 | “Skip forward thirty seconds in Music” | Seek within the current supported track | Bound to duration; verify position tolerance |
| 079 | “Play this podcast at one and a half speed” | Set speed in an explicitly supported podcast player | Player/API feasibility; never assume a universal control |
| 080 | “What song is playing in Spotify” | Show current track and artist metadata | Read-only native metadata; no audio recording |

## Communications and contacts — P3

| ID | Example command | Intended result | Acceptance requirement / constraint |
|---|---|---|---|
| 081 | “Draft an email to Sam about Friday” | Create a local draft with literal supplied details | Resolve exact contact; never invent body or send |
| 082 | “Draft a reply saying I can attend” | Prepare a reply to a user-selected email | Explicit message access; no automatic send |
| 083 | “Attach agenda.pdf to this email draft” | Attach a reviewed scoped file | Exact draft/file review; no unrelated file access |
| 084 | “Send the email draft I just reviewed” | Send only the immutable reviewed draft | Final recipient/body/attachments approval; delivery remains distinct from dispatch |
| 085 | “Find Sam in Contacts” | Show bounded matching contact names | Contacts consent; do not expose unrelated details |
| 086 | “Open my chat with Sam in Messages” | Open the exact resolved conversation | Supported native routing; no text insertion or sending |
| 087 | “Open my chat with Sam in WhatsApp” | Open a uniquely resolved chat if supported | App API/deep-link feasibility; no unsupported UI guessing |
| 088 | “Show the phone numbers for my selected contact” | Display explicit contact detail | Native Contacts permission; never infer a recipient |
| 089 | “Schedule a reviewed message for tomorrow” | Prepare a pending local communication | Scheduling feasibility; explicit approval of content/time; recheck before effect |
| 090 | “Cancel my scheduled message to Sam” | Cancel one exact pending communication | Verify not already dispatched; never claim recall |

## Routines and agent management — P2

| ID | Example command | Intended result | Acceptance requirement / constraint |
|---|---|---|---|
| 091 | “Save these reviewed steps as Morning setup” | Store a named bounded routine | Only allowlisted typed tools; no hidden permissions |
| 092 | “Edit my Morning setup routine” | Preview and change saved steps | Show complete diff; approval grants do not carry over |
| 093 | “Run my Morning setup routine” | Execute the exact reviewed routine | Recheck permissions/targets; destructive steps still require review |
| 094 | “Open my development apps together” | Open an explicitly saved group of installed apps | No inferred app choices; no duplicate launch effects |
| 095 | “Arrange my work windows” | Apply an explicitly saved layout | Revalidate every owner/display; report partial completion |
| 096 | “Set a tea timer for four minutes” | Create a named timer with a unique identity | Verify scheduled notification and exact due time |
| 097 | “Show my active timers” | List Wesley Flow-owned pending timers | Read-only; do not enumerate unrelated app notifications |
| 098 | “Cancel my tea timer” | Cancel one exact Wesley Flow-owned timer | Disambiguate name; verify pending request removed |
| 099 | “Pause this routine after the current step” | Stop before the next effect | In-flight effects retain verification; no false rollback claim |
| 100 | “Continue this interrupted routine” | Propose remaining verified-safe steps for review | Never replay uncertain effects; create fresh approval for changed steps |

## Suggested first implementation batches

1. P1 read-only status and reminders: battery level, today/overdue reminders and bounded task search.
2. P1 window placement: start with left/right halves, then expand after multi-display and app-size verification.
3. Scoped file operations: rename/copy/reveal before reviewed moves and recoverable deletion.
4. Browser and media integrations: adopt only documented/native controls that support truthful result checks.
5. Calendar modifications and communications: implement exact review/identity binding before adding effects.

Each batch should have its own implemented-command list and acceptance record. A Help entry must appear only when its command is actually wired and supported. This backlog itself grants no execution permission and enables none of the listed actions.
