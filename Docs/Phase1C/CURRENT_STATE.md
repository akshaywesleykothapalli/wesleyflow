# Current state reconciliation — 20 October 2026

This inventory was established from the actual working tree, source, reports and running UI before this milestone's edits. HEAD main: 0a3e91c731a716945853a6b84bcfaaf6d9e672d3. No newer commits or newer Phase1C reports beyond the repeated-insertion report were present. 41 outstanding files, nothing staged. Prior work is preserved in place; baseline status/hashes and before-files: Evidence/GlobalVoiceParity. No other session's claimed results are assumed current.

| Feature | Entry status | Actual evidence / gap |
| --- | --- | --- |
| Native sidebar, Settings, History, Commands | WORKING AND VERIFIED | Own canonical UI observed; fixture UI rendering evidence exists. |
| Fn monitoring and press/release | WORKING AND VERIFIED | User reports capture/insertion; decoder/coordinator fixtures exist. Not all lifecycle conditions live-tested. |
| Right Option / Right Command selection | MISSING | No selection setting or decoder. |
| Minimum hold / accidental tap rejection | MISSING | Native composition starts capture without hold threshold. |
| Nonactivating84x32 HUD | WORKING AND VERIFIED | Panel/code and fixture layout; user approved waveform size. Animated bars are decorative, not audio amplitude. |
| Clickable idle pill | PARTIAL | Panel exists but mouseDown does nothing; idle pill hidden. Existing Fn-only preference must remain default. |
| Microphone and on-device transcription | WORKING AND VERIFIED | User spoke and saw transcript. Existing Apple installed-module/legacy fallback reused; no cloud or downloads. |
| Sleep/wake / event-tap recovery | PARTIAL | Wake observer and tap re-enable exist; tap is not recreated if invalidated. No physical sleep/wake verification. |
| Permission revocation | IMPLEMENTED BUT NOT LIVE-VERIFIED | Fakes cover explicit refresh; no continuous refresh while idle. |
| Original destination binding | IMPLEMENTED BUT NOT LIVE-VERIFIED | PID+launch, CF element/window identity, text/selection revalidation; broad live app matrix absent. |
| Native/WhatsApp/browser insertion | PARTIAL | Prior human success and saved INSERTED receipts; no new cross-app matrix. |
| ChatGPT/Codex repeated insertion | BROKEN | Intermittent first delivery, unverified paste and subsequent pending-clipboard denial. Live UI still shows DENIED/UNCERTAIN. No consistent acceptance. |
| Apple Terminal | PARTIAL | Intentionally manual-copy only per explicit user decision. |
| Clipboard safety | PARTIAL | Bounded representations/ownership/explicit recovery tested; backup only in RAM and lost on termination. No claim of crash-safe clipboard recovery. |
| Newer insertion diagnostic + pre-recording guard | IMPLEMENTED BUT NOT LIVE-VERIFIED | Source has802-case checked change; canonical Run bundle is older. Do not discard pending RAM clipboard backup to update. |
| Whitespace normalization | WORKING AND VERIFIED | Pure tests and source. |
| Spoken punctuation/capitalization/filler/repetition | MISSING | No pipeline options. |
| NSSpellChecker/vocabulary/replacements | MISSING | Dictionary page explicitly unavailable; no settings. |
| Local history/raw recovery | WORKING AND VERIFIED | SwiftData fixtures/reopen tests; running UI history visible. Plaintext local store, no retained audio. |
| Incremental external insertion | MISSING | Deliberately not enabled: volatile hypothesis snapshots lack stable-segment/destination-mutation contract. HUD activity is not external live typing. |
| AI rewriting / agents | PARTIAL | Foundation present, intentionally gated/disabled; never part of dictation. |

Latest source-matched prior evidence:802 cases/355 functions full and replay;178 cases/128 functions focused; Debug/Release/Release QA exit0 (accepted-observation-final-*). These are historical baseline checks, not verification of new changes or native universal compatibility. No application-source migration or external dependency introduced by reconciliation.

See GLOBAL-VOICE-PARITY-REVIEW.md for final changes, current verification and live acceptance limits. Baseline categories above remain historical so missing-at-entry features are not silently relabelled as previously implemented.

## Final source classification for this milestone

| Feature | Final status | Verification boundary |
| --- | --- | --- |
| Deterministic formatting / technical protection | WORKING AND VERIFIED | Pure injected-correction cases pass; transformed speech acceptance still manual. |
| Apple spelling integration | IMPLEMENTED BUT NOT LIVE-VERIFIED | Builds/type-checks; installed dictionary behavior not benchmarked. |
| Vocabulary / exact replacements / preferences | IMPLEMENTED BUT NOT LIVE-VERIFIED | Round-trip/pure/layout tests pass; source not deployed. |
| Configurable native keys /250ms hold | IMPLEMENTED BUT NOT LIVE-VERIFIED | Controlled clocks/decoder/generation tests pass; physical key conflicts unverified. |
| Optional clickable84x32 pill | IMPLEMENTED BUT NOT LIVE-VERIFIED | Fake target/session tests; panel remains nonactivating; physical cross-app acceptance absent. |
| Normal-Quit clipboard guard | IMPLEMENTED BUT NOT LIVE-VERIFIED | Pending-lease recovery assertions pass; crashes/force-quits cannot be guarded. |
| Recovery / permission changes | PARTIAL | Existing/new deterministic tests pass; physical sleep/wake and idle-without-view remain live limits. |
| ChatGPT/Codex repeated insertion | BROKEN | Pending clipboard/observation failure unresolved; no blind bypass. |
| Incremental external insertion | MISSING | Intentionally disabled due absent stable-segment contract; final-only gate tested. |
| Current canonical application | PARTIAL | Existing binary preserved with pending RAM clipboard backup; verified new build not promoted. |

Final exact counts, commands, cross-app matrix, Git status and source changes: GLOBAL-VOICE-PARITY-REVIEW.md. Automated success does not upgrade any untested native behavior to live verified.

## 21 October 2026 remediation handoff update

[Repeated insertion remediation](REPEATED-INSERTION-REMEDIATION.md) records safe obsolete-backup recovery, the confirmed stale-lease correction,841-case verification/replay and installation of the exact verified build. Earlier uninstalled statements above are historical. Real repeated ChatGPT acceptance is still UNVERIFIED; no earlier result is relabelled.
