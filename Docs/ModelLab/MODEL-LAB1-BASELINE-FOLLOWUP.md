# Model Lab 1 — verified acquisition and tokenizer follow-up

25 October 2026. Current status: **artifact acquisition and tokenizer preflight verified; inference/training remain BLOCKED**. This supersedes the preparation report's pending-acquisition statements. No model weights were loaded into an inference runtime, no generated code was executed, no adapter exists, and no accuracy is claimed.

## What completed

- The user's go-ahead following the pinned-download proposal was treated as approval for this exact artifact. Native Codex approval was requested before acquisition. Downloaded **880,172,100 bytes** from `mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit`, revision `b3252a2f97102b1fb1571fec2c9b27219a8536be`, Apache-2.0; all 11 files passed pinned size and content-hash checks. Weight SHA256 is `daeab4764fb420d161721791cf2e509e2de81a7af4223646e7bed2bf82c57b58`. Original provenance discrepancies remain disclosed in MODEL-LAB1-REPORT.md and config/model-pin.json; no stronger upstream-lineage claim is made.
- The model resides only in ignored `ModelLab/artifacts/base/`. Exact source URLs, per-file actual SHA256 values and sizes are in `ModelLab/provenance/acquisition.json`. No credentials were read, no hub authentication token supplied, no larger model or fallback acquired. Native MLX remains the selected runtime; no Ollama conversion/import.
- Verified full dependency lock and pinned MLX-LM source identity. Local tokenizer loaded using offline mode and `trust_remote_code=False`. No PyTorch installation was added. Its informational warning does not prevent tokenizer use; numerical MLX inference remains unverified.
- All **60 unchanged synthetic examples** were tokenized successfully. Maximum full example: **678 tokens**; maximum generation prompt: **412**; maximum expected completion including template termination: **280**. Every full example and every prompt plus generation allowance fits the existing **1024-token** context cap.
- **61 deterministic lab tests passed**, and an independent **61-test replay passed**. No original test was removed/weakened. The corpus and evaluation fingerprints remain unchanged.

## Confirmed compatibility defect fixed before any load

The installed Transformers version returns a mapping from `apply_chat_template` by default. The initial draft preflight incorrectly counted two dictionary fields as two tokens. This implausible result was investigated and was not used to authorize a model load. `lab.chat_tokens` now explicitly requests `return_dict=False` and rejects dictionaries, empty output, nested arrays, Boolean/noninteger or negative token IDs. Worker and preflight both use this helper. Three regression tests cover the actual return-shape failure.

The corrected token counts also revealed that some unchanged expected answers exceed the provisional 256-token generation cap (up to 280). **Before the first model generation**, the generation cap was corrected to **320**. The context cap remains 1024; system reserve 4 GiB, runtime allowance 2 GiB, training extra 3 GiB, disk reserve 20 GiB, deadline 120 seconds and four-step training cap are unchanged. No task or expected answer was changed to improve a score. Any future before/after comparison must use this same setting fingerprint.

The first attempt to use the old temporary verification script found it absent after restart; no model ran. Added permanent `ModelLab/verify.py` and `tokenizer_preflight.py` so verification no longer depends on `/tmp`. `acquire.py` similarly preserves the fixed bounded downloader, requires the recorded exact-artifact approval, refuses to overwrite an existing base, verifies every file and never launches a model.

## Actual guarded attempt

| Check | Outcome |
|---|---|
| Baseline command | Exited 0; JSON state **BLOCKED** |
| Headroom at baseline gate | 6.35 GiB |
| Required inference headroom | 6.81 GiB |
| Inference shortfall | 0.46 GiB |
| Held-out coverage generated | **0 / 12** |
| Accuracy, latency, peak MLX allocation | Unavailable; not measured |
| Training command | Exited 0; JSON state **BLOCKED** |
| Required training headroom | 9.81 GiB |
| Swap | Zero in both gate samples |
| Memory pressure | Normal in both samples |
| Resident Ollama models | Zero |
| Free disk at training gate | 38.00 GiB |

A separate bounded 40-second observation window sampled headroom between 6.38 and 6.41 GiB. It never passed admission, so no retry loaded the model. Earlier passing measurements were snapshots, not reservations of RAM. No application was closed and no thresholds were weakened. The sole remaining gate reason for both commands is `memory-headroom`, not missing/unapproved artifacts.

Exit 0 means the control-plane guard completed successfully; it is **not inference or training success**. No model worker started, no resource-stop quarantine was generated, no training loss/checkpoint/adapter exists. Post-training comparison is consequently NOT TESTED.

## Reproduction and evidence

From `$REPO_ROOT`:

```sh
ModelLab/.venv/bin/python ModelLab/verify.py tokenizer
ModelLab/.venv/bin/python ModelLab/verify.py tests
ModelLab/.venv/bin/python ModelLab/verify.py replay
ModelLab/.venv/bin/python ModelLab/verify.py baseline
ModelLab/.venv/bin/python ModelLab/verify.py train
```

The final two commands always recheck the applicable safety gate and remain safe to invoke when blocked. They are not instructions to bypass admission. Exact invocations, timestamps, exit codes and stdout/stderr are preserved under `Evidence/ModelLab1/continuation-*`. Acquisition and tokenizer/prepared manifests remain local/ignored except reviewed public provenance. The frozen corpus is `abf23fcff91b782691691bf8eaf9bcce71f41681d799d13b44af9d0ca91d6065`; held-out fingerprint is `a54ad20e1714038515e6af090b286929e1a810b5bc5de7663256a7c8f0d9ef6c`.

| Action | Actual exit | Timestamp UTC |
|---|---:|---|
| baseline | 0 | 2026-10-25T11:30:04.797630+00:00 |
| replay | 0 | 2026-10-25T11:29:33.461073+00:00 |
| tests | 0 | 2026-10-25T11:29:28.155326+00:00 |
| tokenizer | 0 | 2026-10-25T11:29:20.125624+00:00 |
| train | 0 | 2026-10-25T11:32:10.962115+00:00 |

The earlier native Debug/Release builds and 902-case native suite/replay evidence remain in the preparation report. They were not rerun for these Python-only fixes: every application/core/test/project file is unchanged, and the lab tests exercise the same production Swift validator. Current native/clipboard/voice state was not modified; the installed Run app was not replaced. This is not a new live dictation or macOS 26 compatibility verification.

## Files and readiness

Existing lab edits: `lab.py`, `mlx_worker.py`, `tests/test_lab.py`, `config/smoke.json`, `config/model-pin.json`, README; AGENTS.md records the narrow continuation authorization. New reviewed tools: `acquire.py`, `tokenizer_preflight.py`, `verify.py`, public acquisition provenance and this follow-up. Generated weights, caches, runtime outputs and environment remain ignored.

Practical outcome: all feasible acquisition/tokenizer preparation is complete, but the end-to-end milestone remains PARTIAL/BLOCKED. A future fresh inference gate can use the already verified local artifact without another download. A 16 GB machine's inability to pass this provisional admission snapshot does not establish that small-model inference is inherently impossible. No claim is made that training fits. Training requires its separate higher gate and matching verified baseline; model promotion or production UI integration is not authorized.

No commit, staging, push, remote creation, UI redesign, OpenCode activation, generated-code execution, private-data training, larger model download or automatic app termination occurred.
