# Milestone 45A-R1 — website routing correction

31 October 2026 · build 45.0.2 · preserves all uncommitted 45A work on main.

## Report and confirmed cause

The user said “Search for YouTube.com” and observed “youtube.com Search for youtube.com” being searched in Brave. The user confirmed they wanted YouTube’s website opened directly.

In 45.0.1, PersonalConversation.quick treats generic “search for …” as searchGoogle. NativePersonalApps.search builds a Google results URL and hands it to the system’s default HTTPS handler. Brave can therefore be the correct default browser while the URL is the wrong intent. Website addresses had no independent default-browser action. The duplicated form also lacked a deterministic website path and could fail or reach broader planning with the whole text.

The coordinator’s receive(.transcript) replaces raw with the supplied cumulative snapshot; it does not concatenate callbacks. From the reported words alone, the native speech-provider/range cause of the duplicated snapshot cannot be established. This correction does not claim to repair arbitrary speech duplication or change the dictation transcript accumulator. Raw “Heard” text remains available for diagnosis.

## Implementation

PersonalWebsiteRequest separates HTTPS website navigation from free-text searches. “Search for YouTube.com”, “Open youtube.com”, “Visit https://youtube.com” and a bare domain open the exact HTTPS site in the configured default browser. An explicit suffix such as “in Safari” or “in Brave” targets that browser. Installed application identities retain priority for “Open com.apple.Safari”.

Only identical website requests may collapse: the reported address-plus-command form and two to four complete identical website commands yield one typed website step. Conflicting addresses within these repair forms are rejected. Arbitrary search queries, note/message bodies and literal replies are not deduplicated. “Search Google for YouTube.com” remains a Google search; “Search YouTube for very very good music” retains the repeated words. Explicit search payload punctuation is preserved.

The new website tool uses native NSWorkspace URL opening, binds the chosen handler’s bundle identity, and never builds a search URL. No Apple Events permission, clipboard operation, foreground text insertion, model call, cloud API or conversation submission is involved. Browser handoff is distinguished from page verification: the pill says “Website opened”, while the receipt explicitly says page loading is unverified and prevents automatic replay.

Accepted direct addresses are bounded ASCII DNS hosts with HTTPS, optional path/query, no credentials, port, encoded host characters, whitespace or backslash. Unsupported schemes, encoded hosts or ambiguous addresses are refused. Full spoken-dot spelling, arbitrary URL repair and other browsers by spoken name are not added; the default browser may be any configured HTTPS handler.

Fn dictation, native shortcuts, speech range/session handling and insertion services are unchanged. This fixes the reported interpretation; it does not assert a new cause or fix for an OS modifier-key collision. Existing key-conflict validation and secure-field restrictions remain.

## User-operated acceptance

1. Confirm build 45.0.2 / 45A-R1. In another app, hold the configured Agent key, say “Search for YouTube.com”, and release. YouTube should open directly, rather than a Google results page. If Brave is your default browser, opening YouTube in Brave is expected.
2. Say “Search Google for YouTube.com”; confirm a Google search. Say “Search YouTube for very very good music”; confirm YouTube search terms retain both “very” words.
3. Say “Search for youtube.com in Safari”; confirm Safari receives the direct website address. Try “Open WhatsApp” afterward to check installed-app routing.
4. Repeat the Agent command, release promptly, and press again; each recording must create one task. A raw “Heard” snapshot may retain duplicated words, but the interpreted website action must contain one HTTPS address. Do not retry an uncertain native effect automatically.
5. Click a text field, hold Fn and dictate a normal sentence. Confirm one insertion, Transcribing… then the pill disappears, and no Agent task. Repeat Fn after the Agent handoff. Check clipboard contents remain yours. Test the same sequence from a fullscreen app.

## Verification

Passed 448 focused cases; 1824 full cases and matching replay, zero failures; Debug, Release and complete Swift concurrency builds; 13 CI unit tests; repository/history checks and separate new-file secret scan. All 9 protected voice/shortcut/insertion/speech files match the 45.0.1 baseline. Testing used a fresh build folder after the reused incremental build imported a stale Domain module. Frozen source hashes were checked after verification. No native browser was opened by the fixture tests. Physical acceptance remains pending.

Release executable SHA-256: `0c95fe44c85cbcc8f234c6a7524131304ab76bfbd27859500fb7d8812fcc3670`. Deep/strict local ad-hoc signing verification passed; this is a local test build, not notarized distribution. Evidence: `Evidence/Milestone45A-R1/manifest.json`, xcresults, logs and source hashes. Installation is recorded separately in `Evidence/Milestone45A-R1/installation.json`. No branch, commit or push was created. Do not downgrade a queue containing the new website tool to 45.0.1.

Publication note: this implementation report records its original handoff. Later user acceptance and source publication are recorded in [the build 45 checkpoint](BUILD45-PUBLICATION-CHECKPOINT.md).
