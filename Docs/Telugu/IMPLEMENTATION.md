# Offline Romanised Telugu: repository audit and slice

Historical baseline and callback-fix evidence follows. For the current model setup, routing and real Telugu verification, use [Recognition quality fix](RECOGNITION-QUALITY-FIX.md).

Audit: 2026-11-01. Repository `/Users/akshaywesley/Developer/WesleyFlow`, initial HEAD `c1a9a3e`, clean `main`. The ChatGPT project directory is a reference mirror, not this Git repository.

- App: native SwiftUI, macOS 26 arm64, Swift 6, local WesleyFlowCore package. Explicit project source membership.
- Capture: AppleDictationInput implements DictationInput, AgentDictationInput, metering, diagnostics and recovery. Apple SpeechTranscriber/DictationTranscriber with legacy on-device fallback. No Parakeet/WhisperKit/whisper.cpp implementation found in production source.
- Gesture: NativeDictationShortcut supplies bound origin identity; SystemWideDictationCoordinator captures the original target before microphone startup, filters short presses, requires release before insertion, ignores callbacks for old sessions, and has an eight-second finalization watchdog.
- Delivery: TextInsertionService preserves target identity, clipboard leases, verification and no-second-dispatch rules. Terminal stays manual copy. No changes to these policies are needed.
- Dictionary: DictationFormattingOptions has protected vocabulary and explicit phrase replacements. DictationPreferenceStore stores version-one Codable preferences with backward-compatible defaults.
- Tests: Swift Testing app suites plus package suites; four graphical layout checks are explicitly manual in existing CI. Existing regression counts are historical until rerun.
- Permissions/signing: microphone usage text and audio-input entitlement already present; hardened runtime and ad-hoc local signing. Production distribution signing is a separate gate.

Implementation boundaries: English/Agent capture continues through AppleDictationInput unchanged. New mode selects local multilingual Small; automatic language identification is default and Telugu-only is explicit. The recognizer owns one serial context, with no runtime network client. Romanisation and whole-token loanword restoration are deterministic; explicit user replacements take priority. Telugu skips English spelling/LLM cleanup.

Verification results and known limitations will be appended after actual builds and tests.

## Implemented baseline

General → Speech engine now offers **English (existing engine)** and **Telugu (Romanised)**. Existing preferences migrate to English, retaining the configured Mac locale and Apple engine selection. Agent recognition remains Apple Speech. Mode, language policy and Telugu dictionary replacements are frozen at gesture start.

Telugu uses `LocalPCMRecognizing`, with `LocalWhisperRecognizer` as the current implementation. An actor owns a persistent `whisper_context`; synchronous C calls never overlap or suspend inside inference. The context survives successive gestures and mode switches. A small owning wrapper frees it after its last reference. Sample buffers and language C strings stay alive for the entire C call. The abort callback reads an atomic cancellation flag whose object remains alive until the synchronous call returns. Cancellation never frees an in-use context.

The microphone tap downmixes Float32 into a preallocated single-producer/single-consumer ring. It performs no conversion, locks, allocation, task creation or ASR. A separate producer task uses AVAudioConverter to produce 16 kHz mono Float32, drains resampler EOF, and splits utterances. Ring publication uses release/acquire atomics; shutdown waits for an in-progress tap write before the final drain. Timestamp discontinuities, device changes, invalid samples and overflow fail closed. The decode queue holds two pending segments; overflow reports failure instead of dropping audio.

The first segmenter is an **energy gate, not Silero VAD**: 20 ms frames, RMS > 0.005, 200 ms minimum cumulative voiced audio, 500 ms silence boundary, 160 ms preroll, and 25 s cap. Cap boundaries can cut a spoken word. There is no overlapping audio and no word-based deduplication. It preserves repeated words. Silence alone and short impulses are rejected in synthetic tests. Quiet voices, noise, music and microphone hardware still require tuning and physical acceptance.

The producer continues while the serial decoder works. Partial native-script snapshots are retained for recovery; external insertion happens only once after release and successful finalization through the existing TextInsertionService. Session IDs fence late results. Telugu has a bounded 60-second post-release watchdog; the existing English eight-second watchdog is unchanged. No LLM, Apple spellchecker or English smart-formatting pass runs on Telugu's completion path.

## Text policy

`TeluguRomanizer` handles independent vowels, vowel signs, virama/conjuncts, Telugu joiners, common nasal spelling and Telugu digits. Punctuation and Latin spans are preserved. Canonical normalization applies only to Telugu runs, preserving decomposed Latin text. The ASCII spelling intentionally merges dental/retroflex consonants and short/long e/o; long a/i/u use aa/ee/oo. Example: `నేను రేపు మీటింగ్ కి వస్తాను` → `nenu repu meeting ki vastaanu`.

Restoration is a conservative whole-token table (meeting, call, office, file, message, email, project, code, team, link, update). Unlisted words are romanised without guessing their English spelling. Existing Dictionary phrase replacements win over built-ins, accept Telugu or Romanised keys, support literal phrases, and do not recursively expand their own output. Vocabulary/Latin spelling is naturally retained; English spelling correction is skipped. The final output is checked against the existing 64 KiB insertion bound.

Automatic language identification is the default. Telugu-only explicitly passes `te`; it can harm English-only or mixed recognition. Auto mode still detects a dominant language per segment and does not guarantee good code-switching. Punctuation-only ASR output is discarded. Native-script ASR accuracy and desired Romanised spelling are separate acceptance questions.

## Pins, setup and distribution

- [whisper.cpp v1.8.2](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.8.2), source commit `4979e04f5dcaccb36057e059bbaed8a2f5288315`.
- XCFramework archive: 42,187,623 bytes; SHA-256 `3ffeec1df254d908f01ee3d87bf0aedb8fbc8f29cbf50dc8702741bb85381385`. SwiftPM verifies the archive checksum. Acquisition happens at build time, independently of inference.
- Multilingual Small, **not small.en**: [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1), revision `5359861c739e955e79d9a303bcbc70fb988958b1`.
- `ggml-small.bin`: 487,601,967 bytes; SHA-256 `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b`.
- Model location: `~/Library/Application Support/WesleyFlow/Models/ggml-small.bin`.

Run from the repository:

```sh
python3 Tools/Telugu/install_model.py
# Or install an existing download without network access:
python3 Tools/Telugu/install_model.py --source /absolute/path/to/ggml-small.bin
```

The installer pins the source revision, limits download size, verifies SHA-256 before publishing the file, uses a temporary file on the destination volume and refuses to overwrite an existing invalid installation. Existing invalid files are preserved for explicit user recovery. The backend checks file size and SHA-256 again on first load. Missing/corrupt models report an actionable error before microphone consent or capture. English remains available. The recognizer contains no networking or model acquisition client.

On this host the verified model was installed successfully; a second installer invocation reported it already verified. Runtime inference does not require the installer or Python. No model weights or audio fixtures are committed.

Whisper and whisper.cpp MIT notices are included in `VoiceInput/Notices` and copied into the application resource bundle. Existing microphone usage text/audio-input entitlement remain; Telugu requests microphone consent only, on user-initiated startup, and does not request Apple Speech authorization. Debug and Release remain locally ad-hoc signed. Distribution still requires Developer ID signing of embedded code and the app, hardened runtime validation and notarization. No library-validation bypass was introduced. No production distribution claim follows from local signing verification.

The running installed application was not replaced, launched or terminated; live preferences and clipboard contents were not intentionally changed. The model folder is the only persistent setup addition outside the source checkout.

## Reproduce deterministic tests

Use the full configured Xcode, matching the repository's build lane:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
python3 Tools/Telugu/run_tests.py
```

The helper runs both Unicode and synthetic-audio suites and verifies both suite completion markers. It explicitly strips real-model opt-in variables, never requests microphone consent and never loads weights. CI includes this helper separately because the existing Xcode test targets do not automatically include newly created package test files. The five coordinator regressions are also required by the existing CI result validator.

Opt-in real inference uses a locally supplied public sample and verified Small weights. For this run, the public [JFK sample](https://github.com/ggml-org/whisper.cpp/blob/4979e04f5dcaccb36057e059bbaed8a2f5288315/samples/jfk.wav) had SHA-256 `59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e` and 11 seconds of 16 kHz mono audio. Build the package tests first, then run:

```sh
sandbox-exec -p '(version 1)(allow default)(deny network*)' env \
  WESLEY_TELUGU_TEST_MODEL='/absolute/path/to/ggml-small.bin' \
  WESLEY_TELUGU_TEST_WAV='/absolute/path/to/jfk.wav' \
  xcrun swift test --disable-sandbox --skip-build \
    --package-path Packages/WesleyFlowCore \
    --scratch-path Evidence/Telugu/Package \
    --filter WhisperSmallIntegrationTests
```

The outer profile denies network operations for the inference process tree; `--disable-sandbox` avoids nesting SwiftPM's manifest restriction inside that profile. This is test evidence for offline execution, not a claim that the unsandboxed production app's other features cannot access the network.

## Actual verification — 2026-11-01

Baseline: clean `main` at `c1a9a3e`. Full pre-change Xcode test run passed 824 test declarations / 1,890 expanded cases. The initial restricted attempt failed on Xcode cache permissions and was rerun with required cache access.

Final source verification:

- Debug build and full Xcode tests: **829 declarations / 1,895 expanded cases, zero failures**. Existing English and insertion regressions passed, plus five new coordinator tests (preference migration, backend/Agent routing, one-shot insertion through the real insertion service with fixture editor, cancellation/stale completion, and missing model).
- Package Unicode tests: four declarations / 19 expanded cases passed. Synthetic audio tests: eight passed; the ninth declaration is the separately opt-in real-model test, skipped in deterministic runs.
- Real Small inference with networking denied: passed. English-only auto recognition contained the expected public-sample text. Forced `te` on English did not produce the English result. The backend also filters punctuation-only output. Pre-cancelled and in-flight cancelled decoding raised cancellation; the persistent context then reproduced its original auto result.
- First measured run: verify/load 12.075 s, 11-second auto decode 1.829 s, maximum RSS 766,459,904 bytes (~731 MiB).
- Final cached run: verify/load 0.985 s, auto decode 0.726 s, maximum RSS 875,528,192 bytes (~835 MiB). These are two single-host test runs, not a sustained benchmark; Metal allocations/unified-memory pressure are not fully described by process RSS.
- Release build with `SWIFT_STRICT_CONCURRENCY=complete`: passed. Existing unrelated `NativeRecordTools.swift` nil-coalescing warning and AppIntents extraction notices remain; no unrelated source was changed.
- Repository publication checks: passed (no issue categories); CI helper unit tests: 15 passed. The new deterministic Telugu CI helper passed locally. Hosted CI has not run for these commits.

Failures discovered and corrected during development: Swift Testing cannot directly macro-expand an atomic load (load into a scalar first); SwiftPM's dynamic framework runner needed a test-only relative runpath; one segmenter test assumed a half-frame silence boundary; and a missing-model test called a helper that itself asserted recording success. The first network-denied attempt failed on nested SwiftPM sandbox setup; the corrected invocation above passed.

The initial test commands used abbreviated skip identifiers, which did **not** exclude four layout tests. Those tests passed, but the separate CI result validator correctly rejected that selection. The exact CI-selector replay and signature results are recorded below after completion.

## Remaining physical acceptance and limits

No human Telugu audio was transcribed in this task. Google FLEURS Telugu train/test row endpoints returned HTTP 500; metadata was available, but corpus shards were not acquired. No Telugu WER, code-switch accuracy, colloquial spelling quality or dialect claim is made. No microphone recording, native cross-app text dispatch or running-app handoff was performed for this slice. Fixture insertion verifies orchestration, not actual editor delivery.

Next acceptance: after safely quitting the older app with no pending session/clipboard recovery, launch the built app; select Telugu (Romanised), Automatic; wait for the actual waveform before speaking a short Telugu-English sentence, then release. Confirm the complete Romanised text and one insertion in an ordinary editable draft. Test English-only speech in Telugu Auto, Telugu-only mode, silence/noise, cancellation during decoding, repeated gestures and existing English mode. Preserve diagnostics and raw text if recognition fails. Keep Terminal manual-copy policy. Long Telugu speech, microphone-route changes and noisy-room behavior remain unverified.

No Medium/Large comparisons, Core ML conversions, learned VAD, LLM normalizer or UI redesign were attempted.


## Final replay, signatures and checkpoint

The corrected invocation reused `Tools/CI/run_checks.py`'s exact test-selection arguments. It passed **825 declarations / 1,891 expanded cases, zero failures**, excluding the four graphical tests. `require_test_results` passed, including all previously required English/insertion regressions and all five new Telugu coordinator regressions. The earlier full run's 829 / 1,895 pass remains separate evidence; those counts are not added together.

`codesign --verify --deep --strict` exited zero for both Debug and Release application bundles, including the embedded Whisper framework. Both MIT notices were inspected in the built Release resource bundle. This verifies local signatures, not notarization or distribution signing.

Implementation checkpoints: `05a55f7` (romaniser/audit) and `d0efeb1` (native backend, capture, preferences, tests, installer and CI wiring). No remote push was performed. The source application name, bundle identifier, existing English recognizer and insertion service were preserved.

Local evidence: `/private/tmp/wesley-telugu-baseline2-tests.xcresult`, `/private/tmp/wesley-telugu-final.xcresult`, `/private/tmp/wesley-telugu-ci-selection/tests.xcresult`, `/private/tmp/wesley-telugu-release.log`, `/private/tmp/wesley-telugu-real-final.log`, and ignored repository `Evidence/Telugu/package-tests.log`. Temporary evidence can expire; the counts, limits, pins and reproduction commands are retained here. The prepared Release application is `/private/tmp/wesley-telugu-build/Build/Products/Release/Wesley Flow.app`; the installed running copy was not changed.


## Follow-up: Fn startup queue assertion — 2026-11-01

The user reported that Telugu Fn startup showed no pill and the app stopped responding. Their screenshot showed Xcode paused in `_dispatch_assert_queue_fail` with `EXC_BREAKPOINT`, plus the separate `NativeRecordTools` nil-coalescing warning. The screenshot did not include application stack frames.

A confirmed defect was found in Telugu startup: an inline `AVAudioNodeTapBlock` was constructed inside `@MainActor` code. The SDK explicitly marks this legacy callback type non-Sendable and warns that it can execute off the main thread. Swift inferred MainActor isolation for the closure. A microphone-free reproducer compiled with `-enable-actor-data-race-checks` stopped under LLDB at `_dispatch_assert_queue_fail + 120`, `EXC_BREAKPOINT`, with the same subcode address shown in the screenshot. The emitted Swift intermediate representation also identified the closure as MainActor-isolated. This reproduces the failure mechanism without claiming a complete backtrace from the user's paused process.

The installed Telugu tap now comes from an explicitly nonisolated factory returning an `@Sendable` callback. It retains the same ring/meter-only real-time work. The configuration-change notification also uses a nonisolated factory and explicitly hops to MainActor before touching UI/session state. No check was disabled in production. The new regression creates the production callback from MainActor, converts it to the actual Objective-C `AVAudioNodeTapBlock` type, and invokes it on a worker with actor race checks enabled. A second regression verifies notification delivery on MainActor. The deterministic CI helper now enables those runtime checks so this boundary stays covered.

Telugu startup now shows **Preparing Telugu…** while the model/microphone are preparing, then the existing waveform only when capture is ready. English preparation behavior remains unchanged. A coordinator regression verifies both modes, including cancellation with no insertion. The reported compiler warning was repaired by removing an unreachable fallback for nonoptional `EKCalendar.title`; reminder-list matching is otherwise unchanged.

Follow-up verification:

- Fresh native Debug build/tests through the repository CI runner: **826 declarations / 1,892 expanded cases passed, zero failures**, including required English/insertion regressions and the new preparation-pill test.
- Actor-checked package suites: **10 synthetic audio/callback tests passed**, plus the four Unicode test declarations / 19 cases. The opt-in real-model declaration remains skipped in the deterministic lane.
- Separately opted-in real Small inference/cancellation test passed with actor checks enabled and networking denied, using the public JFK fixture and the installed verified model. No user audio was recorded.
- Release build with complete Swift concurrency checking passed. Deep strict local signature verification passed for Debug and Release. The specific `NativeRecordTools` warning was absent from the fresh build logs.
- CI helper unit tests: 15 passed. Repository publication checks passed with no issue categories. Hosted CI has not been run for this follow-up.

The first attempt to reuse the earlier temporary package build folder failed because its XCFramework Info.plist was missing; a fresh ignored build folder resolved it without cleaning unrelated files. One regression initially used thread inspection directly from an async context, which the current SDK prohibits; moving that read into a synchronous helper fixed the test compile error. These were verification setup/test issues, distinct from the reproduced callback crash.

Evidence is retained under ignored `Evidence/TeluguCallbackFix/Native`, `Evidence/TeluguCallbackFix/CallbackRepro`, and `Evidence/Telugu/package-tests.log`. The new Debug app is `Evidence/TeluguCallbackFix/Native/DerivedData/Build/Products/Debug/Wesley Flow.app`. The installed app and the user's paused debugger process were not replaced, stopped or resumed.

To use the fix in Xcode, **Stop the paused run, then Run again**; Continue would resume the old loaded executable. Fn remains hold-to-talk: keep it held through preparation, wait for the waveform, speak, and release to finish. Live Telugu microphone recognition/insertion still needs a user-operated acceptance test; this follow-up verifies the callback boundary, preparation UI state and offline model path without claiming that physical test has passed.
