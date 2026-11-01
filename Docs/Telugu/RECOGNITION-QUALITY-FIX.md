# Telugu recognition quality fix — 2026-11-01

Follow-ups: [language settings and installed-build mismatch](SETTINGS-REFINEMENT.md); [English microphone-array correction and Telugu timing](ENGLISH-ARRAY-AUDIO-FIX.md).

The reported Apple Notes receipt confirms that 110 UTF-16 units were inserted and read back. `EDITOR_REPLACEMENT_UNSUPPORTED` concerns optional subsequent AI replacement; it does not explain the Kannada transcript. The stock multilingual Small recognizer generated unsupported script and a repeated syllable loop, which the Telugu romaniser correctly left unchanged. The saved recognition preference was already Telugu-only. The same class of failure reproduced on public Telugu speech with the stock model, including CPU inference.

## Current pipeline

English mode still uses the existing Apple speech/insertion path. Telugu (Romanised) now uses a Telugu-specific Small model through the existing pinned whisper.cpp 1.8.2 C API. Telugu-only decodes directly with the specialist, forced to `te`. Auto uses multilingual Small for language identification and English output; Telugu or rejected generic output goes through the specialist with `te`. A successful empty generic result is not retried. Auto requires both models; Telugu-only requires only the specialist.

Contexts persist in serial actors; preparation and checksum verification finish before microphone capture. Input remains 16 kHz mono Float32. Specialist decoding uses nonoverlapping windows of at most six seconds, preferring quiet boundaries between four and six seconds. This avoids the decoder-token exhaustion observed with longer Telugu windows. Windows can still divide a word. There is no initial prompt, translation, LLM or runtime network request. The existing bounded capture/energy segmentation remains; this is not a new neural VAD.

Strict UTF-8 decoding, unexpected-script detection, token-budget checks and repeated-output checks reject bad candidates. The coordinator checks Telugu output again before romanisation or insertion, preventing the reported Kannada loop from reaching the editor. These checks detect failure patterns, not all incorrect words. User replacements and conservative loanword restoration still run after recognition through the existing romaniser/insertion path. Diagnostics expose model revision, route and timings, without transcript content, with marker `asrRevision=te-quality-r2`.

## Models and setup

The installer defaults to both models and verifies size and SHA-256 before atomic installation. Existing mismatched files are preserved. Both models are already installed on the development machine; the original generic model was preserved.

```sh
python3 Tools/Telugu/install_model.py
# Offline installation from an already acquired file:
python3 Tools/Telugu/install_model.py --model telugu --source /absolute/path/to/ggml-telugu-small-q8_0.bin
```

Location: `~/Library/Application Support/WesleyFlow/Models/`.

| Model | Revision | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `ggml-small.bin`, MIT, `ggerganov/whisper.cpp` | `5359861c739e955e79d9a303bcbc70fb988958b1` | 487601967 | `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b` |
| `ggml-telugu-small-q8_0.bin`, Apache-2.0, `jacobsamas/shorts-studio-models` | `bd01ed7929666163b173b826e56d6dcdf8afb8ce` | 264464607 | `355cef20a0d433ca6ffae35d414c817e0aeecfce21b934d68203efee1e72dcba` |

The specialist is a Q8_0 format conversion of [vasista22/whisper-telugu-small](https://huggingface.co/vasista22/whisper-telugu-small), published in [shorts-studio-models](https://huggingface.co/jacobsamas/shorts-studio-models/tree/bd01ed7929666163b173b826e56d6dcdf8afb8ce). Model attribution and the Apache license are bundled in VoiceInput/Notices. The XCFramework/source pin is unchanged; both Debug and Release application signatures verified locally. No new entitlement or signing exception was added. Auto may retain two Small contexts, so memory use exceeds the original single-model path; peak app memory was not measured.

## Actual verification

Verified on Apple M4 / 16 GB, macOS 27.2, Xcode 27.0 beta / Swift 6.4:

- Native CI-selected Xcode tests: **827 declarations / 1,894 expanded cases, zero failures**, including existing English/insertion regressions and new rejection-before-insertion cases. Required-test validation passed. The normal four graphical tests remain excluded.
- Release build with complete concurrency checking: **BUILD SUCCEEDED**. Debug and Release strict signature verification passed.
- Actor-checked deterministic romanisation, quality, audio/callback and routing suites passed. CI helper tests: **15 passed**. Real model tests are opt-in and excluded from deterministic CI.
- Real production pipeline, networking denied: three pinned held-out FLEURS Telugu test recordings (6.72–10.08 seconds) passed beginning/end word-anchor, valid UTF-8, quality and Romanised-output assertions. Decode times in the earlier passing run were approximately **2.54–4.12 seconds** per clip. This is a three-clip functional check, not a WER benchmark. Provenance/hashes are in `Tools/Telugu/ASR-FIXTURES.json`; no corpus audio is committed.
- A local synthetic Telugu voice saying “తెలుగులో మాట్లాడుతున్నాను. నేను రేపు ఆఫీసుకి వెళ్తాను.” passed in Telugu-only and Auto, including the expected Romanised phrase `telugulo maatlaadutunnaanu`. This is not the user's recording.
- English-only public JFK audio passed in Auto using the multilingual route. Both specialist and generic real inference cancellation/reuse tests passed. The final specialist test completed in 16.98 seconds; the separate generic test completed in 6.32 seconds. All these inference tests ran with network access denied.

Evidence is retained locally under ignored `Evidence/TeluguQuality/VerifiedNative` and `Evidence/TeluguQuality/Recognition`, with package output under `Evidence/Telugu/package-tests.log`. Xcode products are under `Evidence/TeluguCallbackFix/Native/DerivedData/Build/Products/`. Hosted CI has not run.

Failures found during development included the stock model's wrong-script loops, token exhaustion on long Telugu windows, and a protocol default implementation masking actor report metadata; these were corrected. Experimental timestamp/prompt changes were discarded. The native test selection, final real-audio assertions and cancellation checks passed after the fixes.

## Live acceptance still required

Stop the existing Xcode run and Run again to load the new executable. Select Telugu (Romanised), initially Telugu-only. Hold Fn through “Preparing Telugu…”, speak after the waveform appears, and release to finish. Confirm one Romanised insertion in an ordinary draft. Diagnostics should include `asrRevision=te-quality-r2`. Then check Auto with English-only and mixed Telugu/English speech, silence, cancellation and repeated gestures.

The user's voice, physical microphone, live Fn gesture and physical cross-app insertion were not exercised in this fix. The installed/running app and paused debugger were not replaced or resumed. Word accuracy, noisy-room behavior, dialects and code-switching remain imperfect and need live acceptance. The quality guard cannot establish semantic correctness; it deliberately reports an error instead of inserting known failure patterns.
