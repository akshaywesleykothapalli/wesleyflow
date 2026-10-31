# Milestone 38L1 — held dictation, formatting and waveform

Date: 28 October 2026 (Asia/Kolkata).

## Disposition

Engineering changes are implemented locally. Automated verification is recorded below. **Physical acceptance of this build is PENDING.** The user reports that ordinary cross-editor dictation acceptance passed on the preceding build; that report is preserved as user-supplied evidence, not transferred to this build.

**Continuous 1–5 minute recognition is not established on this Mac.** The native inventory found modern speech resources supported, but not installed, for en-IN. The existing selector admits modern engines only for installed resources; otherwise it requires an available on-device legacy recognizer. Thus legacy fallback is expected from these observations, rather than a measured live capture. Apple documents a roughly one-minute limit for legacy recognition tasks. No resource/model installation was requested. No uninterrupted legacy rollover guarantee is made. An early provider ending stops capture, reports failure, preserves available text, and grants no automatic insertion. This is a remaining platform capability limit, not a successful five-minute physical result.

## Baseline and preservation

- Read the repository AGENTS.md first. The current request authorizes this milestone and supersedes historical phase stops only within its scope.
- Repository: `/Users/akshaywesley/Developer/WesleyFlow`; branch `feature/milestone-31-integration`; initial HEAD `24db5c924f8598c6971c771e41f1678262e54379`; initial working tree clean.
- Inspected the actual SwiftUI/AppKit coordinator, native hold-key monitor, AVAudioEngine tap/converter, SpeechAnalyzer/SpeechTranscriber/DictationTranscriber, legacy SFSpeechRecognizer, formatting, insertion/clipboard/readback, AI provider, history and Insights contracts, test fixtures and CI.
- No WhisperKit or Parakeet implementation/dependency was found in production source. This remains an Apple on-device speech implementation. No additional engine was introduced.
- Inspected the existing `DerivedData/Milestone37-PillR2/Build/Products/Debug/Wesley Flow.app` and prior 37R2 report. The running user app was observed at the separate standard Xcode DerivedData path, PID 70530, not the Milestone37-PillR2 path. A path difference alone does not prove different source or explain a recognition failure.
- No existing app was quit, force-quit, replaced or relaunched. No microphone capture, global synthetic key injection or live editor typing was performed by verification. Disposable Xcode test hosts are separate from the running user app.
- No commits, staging, pushes, PR updates or merges. PR #1 and main were not changed. No model downloads, training, cloud fallback, model inference, reserve reductions, AX tree activation, Terminal typing or submission were introduced.

## Established source defects and fixes

### Capture lifecycle

Both global dictation and the older DictationModel armed a 60,000 ms recording timer after startup. Its expiry called stop(), regardless of the held key. Removed those recording timers. The only normal stop is release or the existing explicit stop gesture. Cancel, permission loss, audio configuration interruption, bounded-buffer/text exhaustion and real provider failure can still terminate capture with a reported failure.

The eight-second watchdog applies **after release only** and bounds provider finalization; it is not a recording duration limit. Capture is closed before analyzer finalization. Stop is idempotent through stopRequested. The existing session UUID fences still reject obsolete permission, audio, recognition and cleanup callbacks.

The legacy adapter previously treated any provider final result as session completion, even while the key was held. The global coordinator also accepted an unexpected .finished event during recording as permission to format and insert. Both now require an explicit stop/release before successful completion. A provider ending early produces providerEnded and retains available text for intentional manual copy. A final result accompanied by a provider error does not become success. Empty legacy final results do not promote an older hypothesis into reliable final text.

The recording timestamp is obtained before publishing the recording phase, with a second session/cancellation guard after the clock suspension. Diagnostics distinguish the microphone engine's actual running flag, releaseRequested and recognition result counts from the UI's transcription phase.

### Transcript loss and request boundaries

The old TranscriptBuffer removed **every overlapping range**, regardless of whether earlier text was final. It also bounded all historical segments to 256, so many short finalized phrases could hit an artificial limit. The legacy path simply published formattedString snapshots, with no audio-range accumulation.

The modern accumulator now:

1. Commits finalized phrases to a bounded immutable prefix.
2. Replaces only the volatile tail for matching/cumulative ranges.
3. Ignores callbacks wholly behind the finalized watermark, preventing duplicate finalized text.
4. Rejects ambiguous crossing revisions or a narrow later range that would erase an earlier prefix; the previous full snapshot remains available instead of silently losing words.
5. Compacts final phrases so the 256-slot bound applies to unresolved volatile ranges, not the whole recording.
6. Checks the complete UTF-8 budget before committing any update, leaving the previous valid snapshot intact on overflow.

Legacy callbacks now copy segment start/end timestamps before the main-actor hop. Cumulative snapshots revise the same range; later disjoint passages append in audio order. A substantial backwards timestamp reset is rejected rather than substituting the final few words for the session. No guessed text-prefix or ordinary-word deduplication is used: an intended repeated phrase remains legitimate speech.

DictationTranscriber now uses explicit long-form options with no shortForm hint, volatile results and frequent finalization, replacing progressiveShortDictation. Installed SpeechTranscriber remains the first choice. Resources are never installed implicitly.

**Causality limit:** these defects and their deterministic reproductions are established in source/tests. Without a privacy-safe trace from the user's failed physical session, it is not established which backend/range sequence caused that particular last-words-only event. The fixes do not invent speech that a provider never recognized.

### Bounds, history and Insights

Dictation text is bounded to 65,536 UTF-8 bytes per raw/cleaned value, increased from 16 KiB for longer and multilingual input. Overflow is explicit; automatic insertion is withheld and the last valid text remains available. This is a byte bound, not a guarantee that any speaking speed/language fits an arbitrary duration. AI's separate 2,048-byte input bound and existing provider/memory limits remain unchanged.

The analyzer ingress still uses a 32-buffer bounded queue, with explicit overflow failure rather than dropped-audio success. The app retains no complete PCM recording. Pending volatile ranges remain bounded at 256. Native editor inspection/readback retains its existing separate bounds (64 KiB original context, 96 KiB final readback); a large existing document plus new text may therefore remain unsupported or unverified rather than claiming successful delivery. No audio is written to disk. Existing optional transcript history remains governed by the user's preference.

History formerly clamped durations to two minutes and Insights excluded larger values. Stored duration validation/aggregation now accepts up to 24 hours; this is a bounded history value, not a new capture timer. The encoded row reader and storage quota reserve now account for both 64 KiB strings and worst-case JSON escaping. A maximum-sized entry is saved, closed and reopened in a disposable real SwiftData store. The schema and existing rows are preserved; no migration/reset was added. Old two-minute-clamped values cannot be retrospectively reconstructed.

## Smart Formatting diagnosis and behavior

The production path is receive → complete session snapshot → NativeDictationFormatting.format(raw, saved options, spacing option, locale) → insertion → history. It was connected; no missing global formatter invocation was found. Formatting is deliberately applied once at completion, never by inserting successive recognition hypotheses. Loss of earlier raw text therefore also removed the material that would have been formatted.

Read-only inspection of the real saved booleans found spacing cleanup, spelling, spoken punctuation, capitalization, smart typography and filler removal ON. Repeated-filler collapsing and explicit self-corrections were OFF. The observed settings do not support blaming a disabled main formatting switch. No vocabulary/replacement contents or user transcript were copied into evidence.

Changes:

- Rename the misleading “Format text automatically” switch to “Clean up spacing,” with an explicit explanation that other transformations are separate choices for the next completed dictation.
- Correct Unicode token boundaries to include combining marks. A new regression reproduced corruption of an ASCII-looking suffix in Telugu text; that suffix now remains untouched.
- Supply six literal common typo mappings when spelling is enabled, even if NSSpellChecker declines a suggestion: teh, adn, recieve, seperate, definately, occured. They operate only on unprotected lowercase complete tokens. Vocabulary entries override them.
- Increase the bounded spelling work budget from 128 to 2,048 tokens for longer dictations. This remains bounded and opt-in; dictionary suggestions are not guaranteed.
- Preserve existing protected code, paths, shell lines, URLs, numbers, identifiers, capitalized names and explicit vocabulary/replacement outputs. Unknown lowercase names/technical words cannot be identified perfectly; add them to Vocabulary or disable spelling. The formatter does not promise semantic paraphrasing.

“Remove filler words” handles um/uh/erm. “Collapse repeated fillers” handles repetitions of those fillers; it is redundant and disabled in the UI when all fillers are being removed. It intentionally does not delete ordinary repeated words/emphasis. “Handle explicit self corrections” only handles the documented unambiguous whole-utterance restart; its saved setting was off. Arbitrary repetition/semantic repair is not silently enabled under these toggles.

Diagnostics add raw/output byte counts and a formattingChanged boolean, not transcript contents.

## Option+1 Smart Polish / Option+2 Prompt Engineering

The real saved feature, shortcut and in-place booleans were all ON. Disabled settings are a supported failure branch, but not the observed explanation here. The windowless route, native registration and memory/anchor guard branches were inspected and exercised with fixtures.

A read-only FoundationModels probe reported SystemLanguageModel.default available and English (India) supported. It created no generation session. A separate native resource sample at 18:27:53 IST found 3,965,894,656 available-proxy bytes and non-normal memory pressure. The unchanged 4 GiB/normal-pressure initial gate **would reject generation at that observation**. This was during engineering verification; memory is transient, and it is not evidence that every previous shortcut failed for the same reason. No generation request was made to test admission.

Independent prerequisites remain:

| Gate | Specific consequence |
| --- | --- |
| Shortcut preference/feature/in-place switch disabled | No inference or replacement; compact status identifies the relevant switch. |
| No fresh verified insertion/anchor in this process | No eligible recent dictation; a successful-looking paste alone cannot grant rewrite authority. |
| Unsupported AX exact read/write, range or composition | Ordinary dictation may still work, but automatic precise replacement remains unavailable. AX restrictions are unchanged. |
| Wrong app, changed caret/text/context, expired 120-second receipt | Replacement is rejected; text is not redirected. |
| Pending clipboard recovery | Rewrite is blocked until recovery is intentionally resolved. |
| Dictation exceeds AI's 2,048-byte input bound | “AI input too long”; the longer dictation remains intact. |
| Unsupported language / mixed prose scripts | Existing AI contract supports English prose only; Telugu/mixed prose is rejected. Deterministic formatting/history still preserve Unicode. Protected vocabulary/code can contain Unicode. |
| Model unavailable, failed resource sample, pressure, floor or swap growth | Generation is unavailable/blocked; no larger/cloud fallback or threshold change. |
| Timeout, invalid or fidelity-rejected output | Original stays unchanged. Prompt Engineering classifies source units; it cannot invent/reorder requirements. |

No new live shortcut trace was obtained from the user's editor, so the exact editor/receipt branch for their previous attempt is unproven. The established observations are enabled settings, model availability, and a failing resource observation; the previous milestone already distinguished ordinary insertion support from precise replacement support.

The existing Smart Formatting manual path is preserved: explicitly choose supplied text or a saved dictation → request the relevant preview → inspect the result → explicitly Copy. Option+1/2 never open a surprise editor panel or silently invoke that fallback. Preview generation still obeys memory/language/input/fidelity limits. Copy is an intentional existing UI action, never an automatic clipboard write after a failure. Nothing is submitted.

## Pill and microphone waveform

The same nonactivating 84×32 panel and seven teal capsules remain. Recording shows the existing waveform. Release shows “Transcribing…” throughout finalization and insertion. Verified success resolves directly to hidden; the checkmark case/view is removed. AI success also dismisses without a success icon. No Listening, Finishing, typing or insertion icon was introduced in the pill. Manual/unverified outcomes retain an honest status; failures show compact actionable status with details on the existing Dictation page.

The realtime meter still traverses actual microphone Float32 PCM, including the existing interleaved/multichannel stride handling. It now packs RMS, peak and sequence in one atomic scalar. There is no new callback queue, actor hop, lock, retained audio or allocation. The UI uses the larger of RMS and 18% of peak so brief real transients register without allowing peaks to dominate normal speech. The envelope uses a −60 dBFS floor, a 42 dB display range, 80% attack and 18% decay at the existing 50 ms UI cadence. Stale samples decay to silence. Seven recent energy observations remain the style; these are not claimed to be spectral bands. No random/oscillator motion exists. Hardware gain/noise-floor calibration remains a physical acceptance task.

## Verification and failure investigation

Final results and exact commands are in `Evidence/Milestone38/Verified/commands.json`; Xcode summaries, test trees, logs, result bundles, native inventory and build hashes are adjacent. Intermediate failures are preserved separately rather than erased.

- Initial focused compile corrections: two new assertions attempted to access private diagnostics; changed them to the existing public diagnostic summary.
- Focused regressions exposed the Telugu combining-mark corruption and an obsolete expectation that early provider completion should later insert. Fixed the formatter and strengthened the lifecycle expectation.
- First automatic-suite attempt stalled on two test waits for the removed recording timer. Cancelled that disposable test invocation; replaced timer-dependent waits with lifecycle waits. The running user app was not stopped.
- A subsequent full automatic run passed. Its replay exposed an intermittent 60-second CrossAppReliabilityTests wait on published UI state. Replaced asynchronous published-state observation with awaiting the coordinator's actual startup/insertion task boundaries. Assertions, clipboard expectations, safety gates and time limits remain; no sleeps, retries or disabled tests were used as the fix.
- The final gate audit found Xcode ignored abbreviated graphical-test exclusion identifiers in the local runner. Full and replay therefore **executed and passed** the four existing graphical window/layout unit checks. Ran an additional CI lane with the exact identifiers ending in `()`; its metadata confirms all four exclusions and all required regressions. These graphical fixtures are not physical dictation/editor acceptance.

### Final verification results

| Verification | Actual result |
| --- | --- |
| Focused integration/lifecycle/PCM/formatting/history/AI/clipboard | 297 expanded cases / 168 declarations passed; zero failures/skips |
| Complete local suite, including four graphical layout checks | 1,277 cases / 590 declarations passed; zero failures/skips |
| Independent complete replay, same source | 1,277 cases / 590 declarations passed; zero failures/skips |
| Exact CI lane, four graphical checks excluded | 1,273 cases passed; required-regression gate passed; metadata proves exclusions were honored |
| Debug build | Passed, exit 0 |
| Release build | Passed, exit 0 |
| Release with SWIFT_STRICT_CONCURRENCY=complete | Passed, exit 0 |
| Model Lab synthetic checks | 152 passed; no inference/training/download |
| Native resource-guard checks | 7 passed |
| CI/repository helper regressions | 13 passed |
| Repository checks | Passed: 299 tracked files / 648 history objects, no issue categories |
| Diff whitespace review | Passed |

Relative to the 1,256-case preceding complete local baseline, this adds 21 expanded cases in 12 declarations. The new CI floor is 1,273 (preceding 1,252 + 21); required long-dictation, legacy-range, Unicode, history and held-key tests are enforced by identifier, so a passing count cannot hide their omission. No existing safety test was dropped to make the count pass. The two earlier lifecycle expectations were strengthened to reject early provider success; recording auto-stop is replaced by an explicit held-capture regression.

The 15 s / 1 m / 3 m / 5 m tests use controlled time, timestamped transcript events and synthetic PCM with silence/soft/loud windows. They check app lifecycle, ingestion bounds and ordered text retention. They **do not run speech recognition on five minutes of real audio**, establish fast/slow human recognition accuracy, demonstrate reliable legacy rollover, or certify a physical waveform. The physical matrix below remains pending.

Exact CI-lane evidence is in `Evidence/Milestone38/CILane/gate.json` with summary/tree/result bundle. Model Lab evidence is in `Evidence/Milestone38/ModelLab/`. Final CI helper output and repository scan are copied into Verified. Compiler output includes the standard no-AppIntents metadata notice; disposable test hosts also emit macOS linkd service connection messages. These did not correspond to assertions in the passing final runs. Earlier timeout/compile failures remain in their original result bundles and logs.

## Identifiable test build and handoff

Test bundle: `/Users/akshaywesley/Developer/WesleyFlow/DerivedData/Milestone38-LongR1/Build/Products/Debug/Wesley Flow.app`.

The existing Settings/diagnostic marker is **38L1**. Debug/Release binary fingerprints are in `Evidence/Milestone38/Verified/build-hashes.json`. The existing bundle version is unchanged; use the path, 38L1 marker and hashes to identify this build. No canonical Run bundle was replaced. Do not start a second operational instance alongside a user app holding a capture or clipboard lease. In the running app, finish/cancel dictation and resolve pending clipboard recovery, then use normal Quit before opening this test bundle. This handoff is user-operated; this task did not claim a safe-idle check on the running app.

## Required user-operated physical matrix — all PENDING for 38L1

Use unsent synthetic drafts, record only status/count/timing observations, and check the original editor before any retry/copy to avoid duplicates. Never put passwords or sensitive material in a test.

| Test | Expected observation | Acceptance |
| --- | --- | --- |
| Hold for 15 seconds, 1, 3 and 5 minutes; unique numbered phrases at start/middle/end | Complete order, no missing prefix/suffix, no duplicates; zero insertion while held; one final insertion only after release. If legacy ends early: visible provider failure, retained available text, no insertion. Long-duration capability is then BLOCKED, not PASS. | PENDING |
| Repeat duration matrix with fast and slow speech | No app timer stop; retained content; explicit bounds/provider failures. Synthetic range/PCM tests cannot establish recognition accuracy. | PENDING |
| Pause silently for 5–15 seconds between numbered passages while still held | Microphone waveform settles; capture persists unless OS/provider interrupts; later passages retain the earlier text. | PENDING |
| Telugu + English, combining marks, proper names, Unicode, paths/code, vocabulary | Recognition quality assessed separately from exact text preservation; deterministic formatting respects protected material; English-only AI rejects unsupported prose without editing. | PENDING |
| Loud → soft → silence → speech | Same capsule style, prompt attack, gentle decay; no fabricated movement during silence. Note input gain/device. | PENDING |
| ChatGPT, supported native editor, browser field/contenteditable, WhatsApp; 3 consecutive sessions each | Preserve preceding user-reported baseline; verify this build independently, including clipboard restoration and no submission. | PENDING |
| Switch apps or move/change the original caret/text while held/finalizing | No redirected insertion; accurate target-changed/manual-copy outcome. | PENDING |
| Secure field, unsupported editor, Terminal | No unsafe capture/insertion/rewrite; Terminal remains manual-copy only. No AX activation bypass. | PENDING |
| Escape/cancel, quick tap, release during preparation, release twice, immediate next dictation | No late insertion, no duplicated sessions, clean next capture. | PENDING |
| Mic device/config change, sleep/OS interruption, provider failure | Capture and transcription states are distinct; compact failure; partial available text, no claimed verified success. | PENDING |
| Finalizing text longer than available byte budget / provider backlog | Explicit limit/failure; last valid snapshot retained; no silent truncation, guessed completion or automatic retry. | PENDING |
| Clipboard unsupported formats, newer external copy, pending recovery | Existing backup ownership and newer-copy safeguards remain; no automatic retry or overwritten newer data. | PENDING |
| Every formatting switch individually, then combined; save/relaunch preference | Final raw/output differ only as selected; names/paths/code/vocabulary preserved; ordinary emphasis retained. | PENDING |
| Option+1/2 with a fresh verified supported-editor receipt | Either requested in-place result or specific resource/eligibility error, no editor panel, no submission. Current admission may block. | PENDING |
| Option+1/2 with unsupported/uncertain/expired receipt or >2,048 bytes | Honest compact rejection; original remains, zero hidden fallback. | PENDING |
| Explicit manual preview and Copy, including resource/language rejection | Only intentional UI actions read chosen input/generate/copy; generation rejection does not copy or change editor text. | PENDING |
| History reopen and Insights after 3–5 minute physical capture | Correct stored duration and counts, complete text within bounds; no retroactive correction claim for old clamped records. | PENDING |

For a failure, retain only the 38L1 marker, selected engine, phase, final/volatile counts, microphone-running/release flags, byte counts, formattingChanged, speech failure code, insertion/clipboard/readback outcomes and AI provenance/model reason. No audio, transcript, clipboard contents, full AX tree or user-content screenshot is needed for the initial diagnosis.

## Platform references

- [Apple: SpeechTranscriber results](https://developer.apple.com/documentation/speech/speechtranscriber/results) and [DictationTranscriber.Result](https://developer.apple.com/documentation/speech/dictationtranscriber/result): phrases/ranges, volatile revisions and finalization semantics.
- [Apple: SpeechAnalyzer WWDC25 session](https://developer.apple.com/videos/play/wwdc2025/277/): incremental volatile/final results and explicit analyzer finalization.
- [Apple: SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer): legacy audio-duration/task/service limits. Those constraints are not evidence of uninterrupted rollover on this device.
- Checked the installed Xcode-beta macOS 27 Speech.swiftinterface against the actual APIs used. Runtime deployment remains macOS 26.0 arm64; builds do not establish compatibility or physical acceptance on other OS/device versions.
