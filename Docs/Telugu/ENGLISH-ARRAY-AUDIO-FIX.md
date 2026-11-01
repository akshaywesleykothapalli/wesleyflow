# English microphone-array audio fix and Telugu timing — 2026-11-01

## Observations

The user confirmed that Telugu recognition worked, with some delay, then provided diagnostics after switching to English. The successful Telugu-only run decoded with the specialist in **1.0077 seconds**, from a three-channel 48 kHz input. It admitted one 1.46-second utterance from 2.1 seconds of capture. Its whole-capture downmixed RMS was about 0.0031. The latest English attempt correctly selected Apple SpeechTranscriber en-IN/en_IN, received 273,600 source frames at 48 kHz (~5.7 seconds), drained conversion without gaps, and received zero partial/final results with no reported provider error. Several earlier English attempts had the same zero-result pattern. This is not evidence of missing microphone permission or an incorrectly retained Telugu backend.

## Reproduced defect and correction

Core Audio can map an unlabelled/discrete multichannel microphone format to mono with `channelMap = [-1]`, producing silence without a conversion error. A synthetic 440 Hz signal at amplitude 0.1 reproduced this for two and three discrete channels: output RMS was exactly zero on every individually active channel. Mono input produced RMS ~0.0707. This is a confirmed code defect consistent with the user's three-channel microphone and zero-result English runs; the exact hardware channel layout was not logged, so a physical retest remains necessary.

`AudioIngress` now explicitly averages Float32 multichannel input into mono before rate/type conversion. Every channel contributes; choosing only channel zero would lose microphones that place speech elsewhere. Mono input remains unchanged. The source-format guard still validates the actual hardware buffer, while the converter receives the normalized mono format. Legacy requests receive the same explicit mono input; modern requests retain the existing Int16 format, timestamp accounting, EOF draining, frame budget and queue bounds. Non-finite multichannel samples fail before analyzer delivery. Opposite-phase channels can still cancel under averaging, matching the existing Telugu policy; there is no invented per-device channel choice or gain change.

The existing Apple callback architecture is retained. This correction does not claim a new real-time-safe Apple capture architecture: that path already allocates/converts under its existing ingress lock. Telugu's ring/meter-only real-time callback remains unchanged.

## Telugu latency

The decoder already reuses persistent Small contexts and the reported run used Telugu-only, so it did not incur an Auto second decode. The ~1.01-second ASR time does not measure startup, insertion, or release-to-delivery latency. New metadata separately reports `prepareElapsed`, `startupElapsed`, and `releaseToTerminalElapsed`, alongside existing decoder elapsed time.

Selecting Telugu or changing its recognition policy in General now starts a cancellable model-preparation task. It verifies/loads the same persistent actor-owned model before Fn capture, without inference, microphone permission, audio capture, a download or a change to an active gesture. The UI reports preparing/ready. This moves cold model loading ahead of the first gesture when preparation finishes in time; it does not promise faster decoder inference. Leaving the page cancels the view task; already-created contexts remain reusable. English selection does not prepare an English model or change its engine.

A bounded synthetic-voice flash-attention comparison gave no consistent benefit: current-decode medians across three processes were 0.992 seconds with flash disabled and 1.096 seconds with flash enabled (variable individual times). The exploratory probe also executed a fallback variant that was much slower; fallback retries remain disabled in production. No acceleration, prompt, decoder, segmentation, model or accuracy tradeoff from that probe was adopted.

## Verification

- Deterministic actor-checked Telugu/Unicode/routing/audio gate passed, now also requiring the Apple array-downmix suite.
- Array regression: **two declarations / seven expanded cases passed**, exercising mono/stereo/three-channel input, interleaved and planar samples, every individually active channel, frame counts, drain completion and invalid samples. Before correction, the discrete multichannel cases would receive zero signal.
- Real native Apple SpeechTranscriber en-IN test passed on the public JFK recording through the production ingress and actual installed recognizer: mono, three-channel, and three-channel at 5% signal level all returned 108 UTF-8 bytes and the expected word anchor. No microphone or resource installation was used; networking was denied. The final three-condition test took 1.97 seconds overall. This is recorded-speech recognition evidence, not a physical microphone or insertion test.
- Model warmup regression passed: preparing Telugu never requests microphone access or starts capture.

The public English fixture remains outside Git at `/private/tmp/wesley-telugu-model/jfk.wav`; SHA-256 `59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e`. No user transcript/audio is committed. Opt-in native recognition uses `WESLEY_APPLE_AUDIO_FIXTURE`; the deterministic helper removes that environment flag. Evidence is under ignored `Evidence/EnglishArrayFix`, with final native and handoff outcomes appended below.


Final native CI-selected Xcode suite: **828 declarations / 1,901 expanded cases passed**, zero failures, with required-test selection verified. The four usual graphical tests remain excluded from that count. Separately reran native page rendering in both appearances: **passed**, using fixture input and no capture. Release build with complete concurrency checking: **BUILD SUCCEEDED**. CI helper tests: 15 passed; local-packaging policy tests: three passed. Real legacy Apple recognition was not exercised; its explicit mono append is covered by the conversion implementation, while the actual-recognizer test uses modern SpeechTranscriber.


Installed and reopened **45.0.6** at `/Applications/Wesley Flow.app`, preserving 45.0.5 at ignored `Evidence/EnglishArrayFix/PreviousInstalled45.0.5.app`. Normal Quit was accepted; no force quit, clipboard access or preference reset was used. The existing explicit local-ad-hoc packaging helper was used with the previously documented app-scoped signing exception. The installed signature verified, and the exact Applications process survived a 15-second launch check. Handoff metadata is in `Evidence/EnglishArrayFix/handoff.json`. Retest English with the physical microphone, then select Telugu in General and wait for “Offline Telugu ready.” before holding Fn. This readiness moves initial model loading ahead of capture; the approximately one-second decoder time is not claimed to be reduced.
