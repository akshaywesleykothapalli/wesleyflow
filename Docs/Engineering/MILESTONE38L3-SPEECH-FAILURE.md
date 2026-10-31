# Milestone 38L3 — Long Dictation Failure Diagnosis

Local implementation; no commit, push or merge. Target: macOS 26+, tested on this macOS 27.2 (26B5112a) arm64 device with Xcode-beta 27 toolchain. Test build marker: **38L3R1**, bundle build **38.3.1**. This extends the existing 38L1/38L2 working tree; their original reports remain intact.

## Confirmed physical failure and cause

The user-operated build 38.3 produced a concrete failure at **30,047 ms capture / 30,126 ms recognition**, while the hotkey was still held. The active engine was **legacyOnDevice**, selected/resolved locale **en-IN**. There were **43 partial callbacks, zero finals**, 300 audio buffers / 1,440,000 frames at 48 kHz, all queued, and **zero sample discontinuities**. Audio ingress was still open. The failure stage was `transcriptMerge`, rejection `legacyTimestampReset`, and there was **no native NSError**. Target capture succeeded; insertion and clipboard acquisition never started. Accepted recovery contained 107 UTF-8 bytes and the rejected candidate had 2 bytes. No dictated content is reproduced here.

The immediate root cause is confirmed: Wesley Flow's legacy timestamp-reset guard treated a new short result range as fatal and cancelled otherwise healthy capture before release. This was an application merge rejection, not evidence of a native recognition timeout, missing microphone buffers or insertion failure. The higher-level delivery result described the consequence, not the cause. Apple's reason for changing the range in this particular callback remains unknown. The earlier generic “Speech failed” observation lacked native metadata and cannot independently establish the same cause.

A later user-supplied build 38.3 trace showed **6,129 ms capture / 6,317 ms recognition**, 13 partials and one final, clean release, verified insertion and restored clipboard. It still recorded legacyOnDevice/en-IN and `modernModuleAssetsNotReady`. This confirms only that short operation; it is not long-form acceptance and does not establish the app's current resource preparation status after installation.

## Repair

Legacy cumulative revisions replace only their current passage. Distinct non-overlapping ranges preserve preceding passages. A backward range becomes a provisional boundary while recording instead of terminating capture. Earlier accepted text remains immutable. A new epoch can be appended only when public SpeechRecognitionMetadata supplies a strictly advancing, non-overlapping speech start anchor and positive duration. Subsequent revisions replace only that epoch. There is no fuzzy text deduplication, lexical overlap guess, confidence-as-final heuristic or automatic request restart. Repeated words and Telugu/English are retained verbatim in the merge layer.

Without adequate metadata, recording continues while held and a bounded unresolved candidate is retained separately. On finalization, an unresolved/contradictory boundary fails visibly; it cannot quietly deliver a late fragment or an uncertain concatenation. Explicit manual review/copy is available through the existing settings flow. Pending fragments may overlap; they are not advertised as a complete ordered transcript. Accepted text and unresolved candidates have separate 64 KiB bounds, pending fragments are bounded to eight, and modern volatile segments remain bounded to 256. Exceeding a bound reports failure with earlier recoverable text intact.

The modern analyzer retains finalized phrases across volatile updates. Audio tap delivery reports actual received/queued counts, timestamp gaps and stream closure without recording audio. Stop first removes/stops the capture source, then drains the converter with a bounded EOF loop and trims converter padding to the received frame duration. Only then does it finish the analyzer input and await final results. Legacy release sends `endAudio`, without a redundant forced `finish` call. Callback arrival time is checked against release time so a provider final received before key-up cannot become successful merely because its MainActor handling was delayed.

Legacy callbacks use a bounded 32-entry FIFO and one MainActor drain, preventing independent actor hops from reordering passages/finals. Queue pressure or an oversized callback reports an explicit application delivery error (`WesleyFlowSpeechDeliveryError`, code 1) rather than dropping data and claiming completion. Native NSError domains are preserved separately from this application-generated error domain. FIFO order and overflow behavior have focused tests. The current inspected resource states/preparation are included separately from historical operation metadata, avoiding a stale successful dictation being mistaken for modern resource preparation.

Terminal diagnostics are frozen before cleanup: actual provider, requested/resolved locale, held/release state, capture and recognition durations, task state, partial/final counts, preserved byte/segment counts, merge reason, module status, preparation and fallback reason, audio counters and NSError domain/code with at most four underlying domain/code pairs. No NSError descriptions/userInfo, audio or transcript is included. The last eight operation metadata records are bounded. Unmerged recovery is transient, excluded from diagnostics/history/Insights, and never automatically inserted. Accepted recoverable text follows the existing history policy.

Production capture has an instance ownership check before permissions or microphone start. A second copy cannot independently capture; the status directs the user to finish/cancel, resolve clipboard recovery and quit the other copy normally. No application was force-quit. Two copies were observed during investigation, but the inspection itself could launch a resolved app; this does **not** prove simultaneous copies caused the original physical failure. The user selected the standard Xcode copy for testing.

## Modern resource readiness on this device

The read-only probes observed SpeechTranscriber.isAvailable=true, supported en-IN and installed locale lists containing en_IN. **Both configured module inventories still returned `supported`, not `installed`**. The selected locale remained en-IN; the legacy recognizer was on-device available. Thus the code correctly refused to advertise a prepared modern engine on the basis of installedLocales alone.

The user subsequently reported installing Apple speech resources. A separate process read-only probe at 2026-10-28 15:03:16 UTC still returned the same configured-module status, reservedLocales=[] and prepareAttempted=false. This probe has its own process/reservation context and cannot establish the app's post-install preparation state. Modern activation remains **unverified in the actual app** until General reports Preparation verified or a new speech diagnostic names SpeechTranscriber/DictationTranscriber. User-reported installation is recorded without converting it into an unsupported readiness claim.

The existing explicit General installation action requests the same configured module used by capture through AssetInventory, monitors real progress, verifies inventory plus installed locale, and calls SpeechAnalyzer.prepareToAnalyze without microphone capture. Nil installation requests do not automatically imply success. Failure/cancellation/status remain visible; no language change or automatic download occurs during inspection/capture. No resources were downloaded by this investigation. User-operated installation is the only reported download action.

Legacy remains explicitly labeled compatibility mode with an approximately one-minute provider restriction. This repair handles legacy result boundaries; it does not remove Apple's task-duration restrictions or promise seamless unlimited legacy dictation. A provider termination before release retains recoverable text, reports the limitation and makes no automatic insertion. Modern readiness must be resolved before extending physical tests beyond legacy limits.

## Verification

Final repaired build checks: **369 focused cases**, **1,352 full cases**, **1,352 independent replay cases**, all passed with zero failures or skipped cases. Full/replay included the four graphical checks excluded from the headless CI selection. **Debug, Release and complete strict-concurrency builds all passed**. Expanded counts include parameterized cases across the test bundles. The one-, three-, and five-minute checks use synthetic PCM/result fixtures and virtual lifecycle durations; they do not exercise real recognition or prove language accuracy.

Evidence: `Evidence/Milestone38L3/FinalR1Verified/commands.json`, corresponding xcresult bundles, summaries/test trees, compiler logs and `build-hashes.json`. The CI helper's 13 tests passed. CI floor is 1,348 (1,352 minus four graphical checks), with explicit required new regression identities; the headless lane is checked separately below. Initial build 38.3 diagnostics passed 1,340 expanded full tests and an independent 1,340-test replay before the user exposed the real timestamp-reset failure. Those results are historical and do not count as physical acceptance or verification of the subsequent repair.

The first repair test compile exposed a Swift Testing macro restriction on direct calls to a mutating sequence guard; binding the results before expectations corrected the test. This was a test compilation issue, not a runtime speech observation. The FIFO implementation initially failed Swift's Sendable check because a value-producing closure crossed the lock boundary; it was replaced with an already-copied Sendable observation. The final compile and complete concurrency build pass without weakening checks or adding unchecked Sendable conformance. Earlier converter tests exposed resampler padding; frame-duration trimming was implemented and the stronger total-frame assertions retained. No test failures are hidden by removing tests.

## Manual acceptance matrix — user-operated, pending on repaired build

Use the standard Xcode copy, General marker 38L3R1/build 38.3.1. Finish/cancel and resolve clipboard recovery before quitting other copies normally. Use an unsent draft; do not submit. Record only metadata plus whether beginning/middle/end appeared exactly once. Do not paste the transcript into diagnostics.

| Scenario | Required check | Physical result on repaired build |
| --- | --- | --- |
| Current General resource status | Selected en-IN unchanged; configured module installed and Preparation verified; actual provider captured | Pending |
| 20 seconds held | Remains recording until release; full beginning/middle/end once; clean quiet dismissal | Pending |
| 40/45 seconds with a silence pause around 30s | No application timestamp-reset stop; no missing/duplicate passage; metadata records provider | Pending |
| 75 seconds | Run after modern preparation verified and shorter checks pass; release finalizes all text | Pending |
| 3 minutes | Normal, fast/slow speech and mid-recording pauses; full ordered text | Pending |
| 5 minutes | Only after 3-minute acceptance; no physical success claim from fixtures | Pending |
| App switches across supported editors | Capture target/focus safeguards; no unintended insertion or submission | Pending |
| Telugu + English / names / code / paths | Selected engine/language supports request; inspect actual recognized fidelity | Pending |
| Cancel and OS/provider interruption | No insertion; accurate status and explicit recovery; microphone stops | Pending |
| Clipboard changes/recovery | User clipboard preserved or explicit existing recovery; no hidden overwrite | Pending |

Waveform, Transcribing state, quiet verified-success dismissal, existing clipboard and target/insertion safeguards, AI admission floor and rewriting restrictions are preserved. AI rewriting and UI identity were not redesigned. Unsupported editor replacement remains unsupported even when ordinary dictation insertion verifies.

## Primary API references

- [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory): module configuration determines required assets; installation/reservation and installed-locale checks are distinct.
- [Installation request](https://developer.apple.com/documentation/speech/assetinventory/assetinstallationrequest(supporting:)): automatic locale reservation only in the explicit installation path; nil when installed.
- [Speech start timestamp](https://developer.apple.com/documentation/speech/sfspeechrecognitionmetadata/speechstarttimestamp) and [speech duration](https://developer.apple.com/documentation/speech/sfspeechrecognitionmetadata/speechduration): public timing anchors, not a blanket guarantee of stable partial-result boundaries.
- [Legacy task errors](https://developer.apple.com/documentation/speech/sfspeechrecognitiontask/error): classic error meanings are applied only to the matching legacy provider/domain/code.
- [Analyzer finalization](https://developer.apple.com/documentation/speech/speechanalyzer/finalizeandfinishthroughendofinput()): finalization follows completed input consumption.

## Local checkpoint and preservation

Branch `feature/milestone-31-integration`; HEAD `24db5c924f8598c6971c771e41f1678262e54379` is unchanged. Nothing is staged, committed, pushed or merged. Pre-existing uncommitted 38L1/38L2 work is retained. The existing pill/audio-level style, preferences, formatting implementation, history persistence implementation and previous milestone reports are byte-identical to their turn-start versions where recorded in `baseline-preservation.json`; narrowly extended dictation/recovery files are listed separately. AI provider/admission code and the 4 GiB floor were not changed. No model training or downloads were run. User transcript text was not copied into this report/evidence.

## Final CI selection and build identity

The actual headless CI test command passed **1,348 expanded cases** with every required regression identity present and the four intended graphical exclusions honored. Evidence: `Evidence/Milestone38L3/FinalCILane/gate.json`, summary/test tree and xcresult. Repository/history security checks passed (299 tracked files, 648 history objects, no issue categories); CI helper tests passed 13/13; `git diff --check` passed. Final full/replay runs had no observed test flakiness. Earlier incremental compilation used inconsistent cached Domain artifacts while sources were being edited; verification was repeated in a dedicated derived-data directory with source mutations and builds sequenced. These compiler/setup issues are not physical recognition evidence.

Prepared test application: `DerivedData/Milestone38L3-PassageR1/Build/Products/Debug/Wesley Flow.app`, build **38.3.1**, General marker **38L3R1**. The user chose the standard Xcode build: rebuild/run that copy from these sources instead of launching another copy alongside it. No existing running app was replaced/relaunched by this final verification. The final CI command relinked/re-signed the Debug product without Swift source compilation; current hashes below were recorded afterward. Earlier pre-CI hashes remain separately preserved as historical evidence.

- `DerivedData/Milestone38L3-PassageR1/Build/Products/Debug/Wesley Flow.app/Contents/MacOS/Wesley Flow`: `25e6b0a403f033fc02a21d1c0724ed2eabfa7e5f6d063a39cb15878a2fde2fed`
- `DerivedData/Milestone38L3-PassageR1/Build/Products/Debug/Wesley Flow.app/Contents/MacOS/Wesley Flow.debug.dylib`: `b39eee1d124ff5f108b57c830e0c3cafe42cb00f84550e73e5ee51c745897fc4`
- `DerivedData/Milestone38L3-PassageR1/Build/Products/Release/Wesley Flow.app/Contents/MacOS/Wesley Flow`: `49543aaa99e76a3fc371412f88a8bc1a7177d799de4c5e838b6576f4ba8cd8ef`
