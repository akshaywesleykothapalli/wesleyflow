# Offline macOS speaker evaluation

The evaluator compares **ReDimNet2 B3 VoxCeleb2-LM**, the bundled **ResNet34**, **WeSpeaker ECAPA-TDNN512-LM**, and **ReDimNet2 B6 VoxCeleb2-LM**. It uses explicit local model files, checks their size and SHA-256, and loads one model per process. It does not record audio, access voice profiles, download weights, or modify the installed app.

## Setup

Use an isolated Python environment on arm64 macOS. The smoke run used Python 3.11, NumPy 2.4.6, ONNX Runtime 1.23.2, PyTorch 2.15.0, and torchaudio 2.11.1. PyTorch and torchaudio are used only for the ECAPA frontend.

Put these files in a local model directory outside Git.

- `b3-vox2-lm.onnx` and `b6-vox2-lm.onnx` from the [versioned ReDimNet2 exports](https://github.com/mediainbox/redimnet2-onnx/releases/tag/models-v1). The 72-bin frontend follows the [exporter's documented input](https://github.com/mediainbox/redimnet2-onnx/tree/8e7bfecfca2d9964d582cb07cb02cdc868a2dab0#mel-features). Official checkpoint export parity and redistribution review are required before app integration.
- `voxceleb_ECAPA512_LM.onnx` from the [pinned WeSpeaker checkpoint](https://huggingface.co/Wespeaker/wespeaker-ecapa-tdnn512-LM/blob/a2f3dcb1c8702caccc7a55ceb57f5e8d1842112b/voxceleb_ECAPA512_LM.onnx). It uses the [WeSpeaker Hamming filterbank and mean normalization](https://github.com/wenet-e2e/wespeaker/blob/master/wespeaker/cli/speaker.py).
- The current speaker-enabled app bundle supplies its pinned ResNet34 and sherpa-onnx libraries. Pass `--app` to use a bundle at a different path.

From the repository root, build the same C wrapper used by the app into a temporary folder.

```sh
bench_dir="$(mktemp -d)"
runtime=Packages/WesleyFlowCore/Sources/CSpeakerRuntime
xcrun clang -O2 -dynamiclib -I "$runtime/include" "$runtime/Runtime.c" \
  -o "$bench_dir/libspeaker.dylib"
OPENBLAS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 python Experiments/OfflineSpeaker/evaluate.py \
  /path/to/corpus.json --models-dir /path/to/models --wrapper "$bench_dir/libspeaker.dylib"
```

Pass `--model b3` for a single model. Run the scorer tests with `python -m unittest discover -s Experiments/OfflineSpeaker -p 'test_evaluate.py'`.

## Corpus and decision

Use only consented recordings and keep them and their manifest outside Git. The manifest is a JSON object with `kind` (`human` or `synthetic`) and a `clips` array. Each clip has `path` (relative to the manifest, or absolute), `speaker` (a pseudonymous ID), `session`, `split` (`calibration` or `test`), and `role` (`enroll` or `query`). Use mono 16-bit PCM WAV at 16 kHz with at least one second of audio. The harness uses up to the first 14 seconds. Prepare comparable voiced windows in advance when testing a duration bucket.

Each split needs enrolled and unenrolled speakers. Give each enrolled speaker exactly three enrollment clips and one or more queries from a different session. Mark speakers with no profile as query-only. Calibration and test speakers must be disjoint. Duplicate evaluated PCM is rejected. Compare identical audio and profile counts across models.

The evaluator fits one cutoff per model using the top score of unknown calibration queries and the same false-identification budget (default 1%). It freezes that cutoff before test scoring. Results count correct names, wrong enrolled names, rejected enrolled clips, and unknown clips incorrectly given a name. `observed_improvement` means more correctly named enrolled clips than ResNet34 with no increase in false names and with the observed target met. It is a descriptive count comparison, including on synthetic data. The baseline here uses the production embedding model with the same calibrated scoring as the candidates. The app's per-profile cutoff and short-utterance fallback need separate end-to-end validation.

A replacement requires held-out human recordings, enough independent unknown-speaker trials to estimate the false-identification rate, checks by duration and microphone, and signed-app latency and memory tests on an 8 GB M1 with dictation running. Validate macOS 15 and M2 separately. The evaluator does not select or deploy a production model.

## Initial smoke run

On an Apple M4 with macOS 27.2, each model processed the same synthetic recordings. Calibration had eight enrolled and four unknown queries. The disjoint test had eight enrolled and eight unknown queries, with two profiles per split.

| Model | Correct enrolled names | Unknown clips incorrectly named | Test p95 |
|---|---:|---:|---:|
| ReDimNet2 B3 | 8/8 | 5/8 | 214 ms |
| Bundled ResNet34 | 8/8 | 6/8 | 77 ms |
| ECAPA-TDNN512-LM | 8/8 | 8/8 | 60 ms |
| ReDimNet2 B6 | 8/8 | 4/8 | 841 ms |

These are exploratory counts from synthetic voices. Four unknown calibration queries cannot support a 1% false-identification claim. The high held-out false-name counts illustrate why a low calibration error on this fixture is insufficient. These figures also do not describe the installed app's matching policy. No candidate qualified for promotion. The installed app, voice profiles and dictation path were outside this experiment.
