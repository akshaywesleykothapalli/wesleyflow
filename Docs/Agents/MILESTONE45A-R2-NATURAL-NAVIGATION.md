# Milestone 45A-R2 — natural local navigation

Build 45.0.3 · 31 October 2026. The user physically accepted the 45.0.2 website correction before this extension. Existing 45A/45A-R1 work was preserved uncommitted at handoff; subsequent publication is tracked in [the build 45 checkpoint](BUILD45-PUBLICATION-CHECKPOINT.md).

## Behavior

“Open Google”, “Go open Google”, “Open Gmail” and “Open YouTube” resolve to a fixed local website registry. No domain guessing, DNS request, cloud API or model is needed to understand them. Twenty-three familiar services include Google/Gmail/YouTube, Maps/Drive/Docs/Sheets/Slides/Calendar/Meet/Photos, YouTube Music, GitHub, Wikipedia, Reddit, LinkedIn, Instagram, Facebook, Netflix, WhatsApp Web, Spotify Web, DuckDuckGo and Bing. The exact addresses and aliases are in PersonalWebsiteNames.sites and the existing Command Mode Help.

“Hey, open WhatsApp”, “Hey Wesley, please open WhatsApp”, “Could you just open WhatsApp”, “Please go and open WhatsApp”, “Bring up WhatsApp” and “Pull up WhatsApp” retain their exact installed-app target. Courtesy/wake-like words are interpreted only from an explicitly initiated Agent request; there is no always-listening wake word. For open/launch/start requests, installed apps take precedence over a same-named service, unless “website” or a named browser explicitly requests the web version.

Direct website opening can target Safari, Brave, Chrome, Firefox, Edge, Opera or Arc, if installed. For example: “Open Gmail in Safari”, “Open Google using Firefox”, “Take me to YouTube in Chrome”. No fallback to another browser is hidden if the named browser is missing. This expanded browser selection applies to website navigation; existing Safari/Brave tab controls are unchanged. Old website records using browser strings “safari”/“brave” still decode.

“Open YouTube and search for piano music” or “Go open Google and search for Swift tutorials” becomes one explicit search action. “Search Google for Gmail” remains a literal search. Repeated query words/punctuation and literal note/message replies are preserved. “Take me to youtube dot com” supports a spoken dot in an otherwise unambiguous address. Only the existing identical-website repetition repair is retained; arbitrary payload words are never deduplicated.

An unknown explicitly named website asks for its exact address, retaining any requested browser. It never invents a bank or service domain. A complete new opening command can replace that navigation question. Replies to an “open” question may name a known website or exact address; closing-app questions never launch a website.

Understanding these supported requests works offline using local rules and the installed-app index. Opening installed apps works without a network when the apps themselves permit it. Online sites, searches, streams and Gmail data still need a connection and any native-app login. This is bounded local command understanding, not unrestricted language understanding or arbitrary computer automation. Unknown phrases can still need clarification; no new model download, cloud fallback or relaxation of the 4 GiB admission floor was added.

## Production changes and preservation

PersonalWebsiteNames is a fixed Domain registry. PersonalWebsiteRequest separates known names, direct addresses and explicit searches, preserves native-app precedence, and uses its own browser enum so adding browser handlers does not expand the native tab/menu automation allowlist. PersonalAgentDialogue accepts bounded leading introductions and keeps pending content replies literal. NativeWebsiteOpening reuses the existing NSWorkspace handoff and target-identity check. No browser contents are inspected.

Fn dictation, native hotkeys, audio, speech range/session handling, secure-field checks, clipboard/insertion services and explicit review for communications/destructive effects remain unchanged. No passive recording, text insertion, conversation submission, email/message send or personal browser action was performed by automated verification. This correction does not promise general wake-word detection or unrestricted offline AI.

## User-operated acceptance

1. Confirm 45.0.3 / 45A-R2. Hold the Agent key and say “Hey, open WhatsApp”; release and verify the installed app opens. Repeat with “Could you just open Safari” and “Go open Brave”. The “hey” prefix must not trigger recording without the hold key.
2. Say “Go open Google”, “Open Gmail”, “Open YouTube” and “Bring up Google Drive”. Check the exact expected website in your default browser, without saying .com. “Open WhatsApp Web” must open the web service, while “Open WhatsApp” keeps the installed app.
3. Try “Open Gmail in Safari” and another installed browser. A missing named browser must report failure, not silently use another. Site loading/login is a separate native/browser outcome.
4. Say “Open YouTube and search for very very good piano”; verify the repeated terms. Say “Search Google for Gmail”; verify search results rather than the Gmail site.
5. Say “Open my unknown bank website in Firefox”; verify an exact-address question rather than a guessed URL. Reply with an address you trust, or replace the request with “Hey, open Gmail”.
6. Disconnect the network yourself if desired. “Hey, open WhatsApp” should still be understood and launch the installed app; Google/Gmail opening must still have a locally determined target, while page loading can fail offline. Reconnect yourself afterward; no network settings were changed during development.
7. Repeat Agent requests, cancellation and rapid key release from a fullscreen app; each hold must produce at most one task. Then click an editable field and use Fn dictation. Verify ordinary insertion, Transcribing… then pill dismissal, no Agent task and unchanged clipboard contents.

## Verification

Passed 493 focused cases; 1869 full cases and matching replay, zero failures; Debug, Release and complete Swift concurrency builds; 13 CI unit tests; repository/history checks and separate new-file secret scan. All 9 protected voice/shortcut/insertion/speech files match the physically accepted 45.0.2 baseline. A fresh build folder was used; frozen source hashes were checked after verification. The new local requests were tested with an unavailable generator and zero inference budget. No native browser was opened by the fixture tests. Physical acceptance remains pending.

Release executable SHA-256: `d3437291ec9157cbb42a55e270acab56ce86edd3260d58959b35ba61b74a0da6`. Deep/strict local ad-hoc signing verification passed; this is a local test build, not notarized distribution. Evidence: `Evidence/Milestone45A-R2/manifest.json`, xcresults, logs and source hashes. Installation is recorded separately in `Evidence/Milestone45A-R2/installation.json`. No branch, commit or push was created. Old Safari/Brave website records still decode. New named browser values require this build; inspect pending work before any downgrade.

Publication note: this implementation report records its original handoff. Later user acceptance and source publication are recorded in [the build 45 checkpoint](BUILD45-PUBLICATION-CHECKPOINT.md).
