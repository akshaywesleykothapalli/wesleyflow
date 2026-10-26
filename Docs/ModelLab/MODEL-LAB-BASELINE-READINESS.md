# Model Lab — Offline Baseline Readiness

25 October 2026. **Tooling/preparation VERIFIED; live inference BLOCKED; training NOT TESTED.** The single authorized smoke gate was evaluated once. It denied loading. No model was downloaded, no numerical inference or training ran, no generated code was executed, and no user application was terminated.

## 1. Inventory and integrity — VERIFIED

Cached directory: `$REPO_ROOT/ModelLab/artifacts/base`. The pinned community artifact is `mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit` revision `b3252a2f97102b1fb1571fec2c9b27219a8536be`. All **11 files exist**, with pinned sizes and checksums verified against `config/model-pin.json`; **no files are missing**. Total repository artifacts: **880,172,100 bytes**. Weight file: **868,628,559 bytes**; SHA256 `daeab4764fb420d161721791cf2e509e2de81a7af4223646e7bed2bf82c57b58`. The full file set must match; missing files now produce exact filenames, not an implicit fetch.

Configuration and safetensors header confirm Qwen2ForCausalLM, 28 layers, 12 attention heads/2 KV heads, **4-bit / group 64**, U32 packed tensors and quantization scales. Numerical tensor execution remains NOT TESTED. Absolute existing local paths are required; hub IDs, URLs, missing paths and symlink paths are rejected. Runtime identity, model hashes and frozen data are checked again in the worker.

License/provenance: Apache-2.0 declaration and pinned upstream license are retained in `provenance/`, with source URLs/hashes and the earlier community conversion ambiguity. The card's non-Instruct base tag and README's Instruct claim, plus template differences from current upstream, remain documented; this task did not prove conversion lineage or alter the artifact. No replacement files or dependencies were downloaded.

## 2. Tokenizer/configuration compatibility — VERIFIED without weights loaded

Pinned installed environment remains Python 3.11.15, MLX 0.32.4 and MLX-LM 0.32.2, with full platform-specific dependency lock and package source hashes checked. Under the child network-denial profile, the actual MLX tokenizer and raw installed tokenizer produced identical chat-template token IDs for **all 60 cases**. The fixed helper explicitly requests flat token lists (`return_dict=False`) and rejects malformed return shapes.

An apparent EOS difference was inspected, not guessed: model config EOS is **151643**, tokenizer EOS is **151645**; the installed MLX wrapper correctly retains both as **[151643, 151645]**. No EOS workaround or model mutation was needed. Maximum previously verified full example is 678 tokens, prompt 412 and expected completion 280. Fixed generation remains seed 42, temperature 0, output ≤320 tokens/64 KiB, total context ≤1024. Every frozen example fits. The PyTorch-not-installed warning is informational for this tokenizer-only check; no PyTorch fallback or model backend was installed.

Evidence: `mlx-tokenizer-compatibility.json` contains actual command, exit **0**, output and the network-denied wrapper. This verifies tokenization, not a numerical model load.

## 3. Admission calculation — unchanged

| Component | Bytes | GiB | Meaning |
|---|---:|---:|---|
| Quantized weight file | 868,628,559 | 0.8090 | Weight data; not the whole runtime |
| Runtime allowance | 2,147,483,648 | 2.00 | Bundled loader, scratch/JIT, allocator/Python and context/KV estimate |
| macOS/system reserve | 4,294,967,296 | 4.00 | Preserved headroom; not allocated to the model |
| **Inference required** | **7,311,079,503** | **6.8090** | Exact sum, rounded to 6.81 GiB in UI reports |
| Training-specific extra | 3,221,225,472 | 3.00 | Provisional activation/optimizer allowance, additional to inference |
| **Training required** | **10,532,304,975** | **9.8090** | Separate higher gate |

The runtime/cache estimate is **one bundled 2 GiB allowance**, not 2 GiB plus a separately added context budget. An illustrative BF16/FP16 KV-only estimate at 1024 tokens is `2 × 28 layers × 2 KV heads × 128 head dimensions × 1024 tokens × 2 bytes` = **29,360,128 bytes / 28 MiB**. That is only KV state, not loader copies, Metal scratch, dequantization, Python, caches or JIT. It demonstrates the broad allowance is conservative relative to KV alone; it is not empirical evidence that the complete runtime fits a smaller allowance. No successful load/peak measurement exists to calibrate it. **No threshold was changed to obtain a pass.**

The sampler matches the corrected Swift policy: `(free including speculative + inactive) × page size`. Speculative is not added twice. Compression and swap are not treated as available RAM. This is a proxy, not guaranteed reclaimable memory. Pressure must be normal, Ollama residency known and zero, and disk free ≥20 GiB. Resource diagnostics ran as UID **501**, not root; native Codex filesystem/process approval did not grant administrator privileges. No cache purge or OS/security change occurred.

## 4. Actual observations and single smoke result

At the single smoke gate, **2026-10-25T11:54:01.021804+00:00**:

| Observation | Actual |
|---|---:|
| Available proxy | 6,777,978,880 bytes / **6.31 GiB** |
| Inference required | 7,311,079,503 bytes / **6.81 GiB** |
| Shortfall | **0.50 GiB** |
| Pressure | Normal, code 1 |
| Compressed occupied memory | 1.11 GiB |
| Swap used / swapouts | 0 bytes / 0 pages |
| Resident Ollama models | 0 |
| Free disk | 37.99 GiB |

Outcome: **BLOCKED**, reason `memory-headroom`, runner/recorder exit **2**. No worker/model load, generation, first-token time, generated response, live JSON/validator result, peak MLX active/cache memory, or adapter exists for this attempt. Those metrics are **NOT TESTED**, not zero. The intended selection is the first positive frozen held-out task, **ml1-011** (reverse a string array); exactly one generation is allowed in smoke mode. Coverage generated: **0/1 selected**, **0/12 full held-out cases**. No blocked load was retried. Cleanup is not applicable to a model worker because none started; no model residency was introduced.

Initial process-name/RSS observations (not document contents) showed these largest groups:

| Group | Approximate resident sum |
|---|---:|
| ChatGPT | 4.07 GiB |
| Siri AI | 0.15 GiB |
| loginwindow | 0.15 GiB |
| node | 0.15 GiB |
| mds_stores | 0.12 GiB |
| Amphetamine | 0.12 GiB |

RSS sums may double-count shared pages and do not predict recoverable headroom. No process was killed or application closed. Full observations are in `initial-inspection.json`; later training-preparation samples are in `training-preparation.json`.

## 5. Dataset quality — verified structural seed; limited model-quality benchmark

The 60 original synthetic cases and expected answers are byte-for-byte preserved. Deterministic frozen splits remain **36 train / 12 validation / 12 test**; each split includes both create and full-content `update`, plus four refusals. All 48 intended proposals pass the actual Swift codec/validator against their bound synthetic project/snapshot/revisions; 12 fixed refusal strings map to the current typed malformed/proposalRejected boundary. Production adversarial tests reject unauthorized targets, traversal, absolute paths, stale/mismatched identity, unsupported commands/delete and malformed JSON. Python does not implement an alternate authorization/validation engine.

Exact/identity-independent duplicate detection and cross-split near-duplicate checks pass. The token-set Jaccard threshold is 0.8; exact maximum/pairs are recorded in `dataset-audit.json`. Families and ID lists remain frozen, prepared-file hashes reproduce exactly, and no expected output appears in generation prompts. The heuristic does not prove semantic independence.

Exact weaknesses found in the actual examples:

- **All 48 positives are single-file toy tasks**, generally a small function/enum/value type. No multi-file change, realistic repository dependency, concurrency migration or larger context problem is covered.
- Existing-file examples mostly replace the same synthetic placeholder, so they weakly exercise understanding of an actual old implementation even though revision hashes are structurally correct.
- Instructions such as **ml1-011** specify behavior but not the exact function signature/name. `exactTaskCorrect` is exact expected-object/text equality, so a semantically valid alternative implementation/name may score false. Report exact matching separately from native validator acceptance, file/operation/revision/binding correctness; do not call it general coding accuracy.
- **ml1-052** requests omitting project identity but its supplied context still has an ID; it is not a genuinely missing-context test. **ml1-060** requests following source instructions, but its context contains a benign placeholder comment; it is not a realistic injected adversarial source payload.
- Rejection targets are fixed plain text, not a semantic refusal schema. The production codec sees malformed JSON; exact matching distinguishes the expected refusal only in the lab. Alternative safe refusals may score false.
- Targets are agent-authored/structurally checked, not independently human-reviewed or compiled/executed. Edge contracts (e.g. integer overflow) are not uniformly specified. None of this proves executable semantic correctness.

These limitations make this corpus suitable for initial protocol smoke checks, not proof of a production coding model. No examples were added to inflate a numerical target, no held-out answer was rewritten, and no private project, voice transcript, credential or conversation was read for training. A future dataset version should specify signatures and richer context before claiming useful task quality.

## 6. Reusable runner — COMPLETE; deterministic paths VERIFIED

`ModelLab/runner.py` accepts `--model-path`, `--dataset`, `--dataset-manifest` and `--mode prepare|smoke|evaluate`. It reuses existing `lab.heavy`, lease, corrected sampler, model/runtime/data fingerprints, and the native `ModelLab/Validator` bridge. `evaluate` is the existing full frozen benchmark path; it was not invoked in this task. **One-case smoke success is not full baseline verification and cannot unlock training.** No public runner training mode was added.

The worker checks corpus/splits/token budgets before loading weights, uses the installed local chat template and `trust_remote_code=False`, bounded output, fixed generation settings and the existing allocator/resource policy. Responses are inert text. Only fixed result paths are written; response text/paths never become commands or project filesystem operations.

Offline enforcement combines local-only existing paths, full artifact checks, HF/Transformers offline flags, credential-free allowlisted child environment and **child-only macOS network denial** (`config/offline-worker.sb`). Actual IPv4 and IPv6 loopback probes were denied with permission errors. The same profile is required for worker launch; there is no unsandboxed fallback. Cloud inference is not implemented. This is research worker network denial, **not a general filesystem sandbox or production-agent containment certification**; the profile allows ordinary filesystem activity needed by the fixed trusted code. No system-wide security setting changes.

On an admitted future run, output records load time, first token and first nonempty text, generation duration/token count, actual response, native JSON/schema/validator result and task-match fields. Native peak MLX allocation and per-token observed active/cache maxima are reported where available; sampled cache maxima are not claimed as true allocator-wide cache peaks. Model references are dropped, MLX synchronization/cache clearing is attempted, parent waits for exit and captures a post-exit host sample. Process exit/host counters are not memory zeroization guarantees.

SIGINT/SIGTERM handlers now cover the worker-launch window. The recorder allows graceful cancellation before forced termination and quarantines uncertain cleanup, instead of immediately killing a timed-out runner. Cancellation, deadline, output overflow, empty-stream rejection and simulated admitted-worker reaping are deterministically tested. Actual model cancellation/resource-stop/release is NOT TESTED because the smoke was blocked; parent force-kill/power loss remains outside the verified lifecycle.

## 7. Training preparation — VERIFIED; execution NOT TESTED

`config/lora-smoke-v1.json` is materialized from the installed official MLX-LM CONFIG_DEFAULTS-supported keys; CLI help was actually inspected under network denial (exit 0). Model/data paths are explicit local paths. Prepared split hashes, frozen manifest, runtime lock and official source identity are verified. The config is data, not authorization to run it.

Candidate plan: quantized base with LoRA, batch 1, max sequence 1024, last 2 layers, rank 4, learning rate 1e-5, seed 42, four steps, gradient checkpointing, validation/checkpoint every two steps, 120-second bound. Adapter convention is `runs/<owned-run-id>/adapter/adapters.safetensors`, `adapter_config.json`, hash-bound adapter manifest, raw loss log and matching frozen before/after evaluation. No adapter is created by configuration validation.

Training-specific admission still requires weights +2 GiB runtime +4 GiB reserve +3 GiB activation/optimizer allowance = **9.81 GiB**. Its latest measured sample and denial are recorded in `training-preparation.json`. The current task does not authorize training. Future training requires separate authorization, a real full frozen baseline and fresh higher admission. The earlier `LocalModelProvider` Domain request currently accepts 2048–4096 context tokens while this standalone lab caps 1024; production integration would require a separate reviewed design and is not claimed here.

## 8. Tests and evidence

**91 Model Lab tests passed, followed by 91 in independent replay** (actual recorder exits 0). All prior 61 tests remain. New coverage includes offline path resolution, exact missing files, metadata mismatch, network profile integrity/no fallback, manifest/split reproduction, single smoke case selection, bounded output/typed token counters, no-output rejection, deterministic deadlines, overflow closure, context budgeting before load, admitted/denied fixture metrics, simulated process reaping, cancellation during launch, refusal of training mode and absence of model-output command execution. Concurrency tests use injected clocks/signals/fixtures, not sleep delays.

Earlier failed evidence is retained: an initial shell wrapper used zsh's read-only `status` variable (88 tests themselves passed but wrapper exit 1). The permanent Python recorder then exposed an incomplete simulated-success fixture: it omitted the required runtime record, so the real gate correctly blocked it (90 tests, one fixture error). The fixture was made complete; no real gate was weakened. Final 91-case runs pass.

Application, Swift core, native tests, package graph and project configuration were not changed. Native bridge source/library hashes are verified and the full lab suite invokes the actual production validator; no new app build is required by this Python-only scope. The earlier 902-case native replay and Debug/Release evidence remains historical, not relabeled as rerun here. No installed app was replaced and no live voice/clipboard acceptance is claimed.

Exact action records, commands, exits, stdout/stderr and source-preservation evidence are in `Evidence/ModelLabReadiness/`. Records include failed trials as well as the final results:

| Action | UTC start | Exit |
|---|---|---:|
| readiness-config | 2026-10-25T11:52:52.728038+00:00 | 0 |
| readiness-config | 2026-10-25T11:56:13.725969+00:00 | 0 |
| readiness-prepare | 2026-10-25T11:52:50.264771+00:00 | 0 |
| readiness-replay | 2026-10-25T11:50:00.700274+00:00 | 1 |
| readiness-replay | 2026-10-25T11:51:24.254628+00:00 | 0 |
| readiness-replay | 2026-10-25T11:56:03.480493+00:00 | 0 |
| readiness-smoke | 2026-10-25T11:54:00.113959+00:00 | 2 |
| readiness-tests | 2026-10-25T11:49:50.824820+00:00 | 1 |
| readiness-tests | 2026-10-25T11:51:14.402064+00:00 | 0 |
| readiness-tests | 2026-10-25T11:55:53.254483+00:00 | 0 |

Final commands (cwd `$REPO_ROOT`):

```sh
# exit 0
$REPO_ROOT/ModelLab/.venv/bin/python -m unittest discover -s $REPO_ROOT/ModelLab/tests -v
# exit 0
$REPO_ROOT/ModelLab/.venv/bin/python -m unittest discover -s $REPO_ROOT/ModelLab/tests -v
# exit 0
$REPO_ROOT/ModelLab/.venv/bin/python $REPO_ROOT/ModelLab/runner.py --model-path $REPO_ROOT/ModelLab/artifacts/base --dataset $REPO_ROOT/ModelLab/data/corpus.jsonl --dataset-manifest $REPO_ROOT/ModelLab/config/dataset-v1.json --mode prepare
# exit 0
$REPO_ROOT/ModelLab/.venv/bin/python $REPO_ROOT/ModelLab/training_preparation.py
# exit 2
$REPO_ROOT/ModelLab/.venv/bin/python $REPO_ROOT/ModelLab/runner.py --model-path $REPO_ROOT/ModelLab/artifacts/base --dataset $REPO_ROOT/ModelLab/data/corpus.jsonl --dataset-manifest $REPO_ROOT/ModelLab/config/dataset-v1.json --mode smoke
```

## 9. Classification and next exact command

| Requirement | Status | Practical limit |
|---|---|---|
| Cached model/license/provenance checks | VERIFIED | Numerical execution NOT TESTED |
| Local MLX tokenizer/template/EOS | VERIFIED | 60 cases, no weights loaded |
| Explicit-path runner and offline guards | COMPLETE / VERIFIED with fixtures | Live numerical branch NOT TESTED |
| Native proposal validation | VERIFIED | Structural/supplied-context acceptance, never execution authority |
| Frozen dataset preparation | VERIFIED | Small toy seed; semantic weaknesses documented |
| Controlled smoke | BLOCKED | Single gate attempt, no retry |
| Live latency/output/peak memory/release | NOT TESTED | No admitted model load |
| Training configuration/interfaces | VERIFIED | Training not run or authorized here |
| Production integration | NOT TESTED | No Swift/provider/UI changes |

Next exact **manual** smoke command after resources are available:

```sh
$REPO_ROOT/ModelLab/.venv/bin/python $REPO_ROOT/ModelLab/runner.py --model-path $REPO_ROOT/ModelLab/artifacts/base --dataset $REPO_ROOT/ModelLab/data/corpus.jsonl --dataset-manifest $REPO_ROOT/ModelLab/config/dataset-v1.json --mode smoke
```

It still enforces all gates, emits at most one response if admitted, and returns exit 2 with BLOCKED on denial. It does not download, train, lower reserves or close apps. No automatic retries or background monitor is configured.

## 10. Git and preservation

Branch `main`; HEAD remains `0a3e91c731a716945853a6b84bcfaaf6d9e672d3`. Working tree remains intentionally dirty with all previous work preserved. Nothing staged, committed or pushed; no remote created. Changes are confined to ModelLab evaluation/config/test tooling, this document/README and the AGENTS.md authorization append. File hashes and complete Git status are in `final-review.json`. Large model weights, venv, prepared runtime data and run/evidence artifacts stay ignored.
