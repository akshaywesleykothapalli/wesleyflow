# Model Lab — Resource and Evaluation Calibration

25 October 2026. **Calibration tooling and deterministic verification complete. Offline inference BLOCKED. Training NOT STARTED.** This is not a successful model baseline or a coding-quality result. No model was loaded; the one admission check failed and was not retried.

## Memory reconstruction and outcome

The existing requirement is **7,311,079,503 bytes = 6.8090 GiB**:

| Component | Bytes | Interpretation |
|---|---:|---|
| Quantized weight file | 868,628,559 | 0.8090 GiB; complete artifact set is 880,172,100 bytes |
| Bundled runtime allowance | 2,147,483,648 | Loader/materialization, Python, allocator/JIT, Metal scratch, KV/context, prefill and generation overhead; provisional, not measured |
| Separate macOS headroom reserve | 4,294,967,296 | Preserved 4 GiB; never an allocation budget for the model |
| Training extra, excluded from inference | 3,221,225,472 | Training requirement remains 10,532,304,975 bytes / 9.8090 GiB |

KV, prefill and generation have **no separate added charges** in the current formula. Their individual runtime peaks cannot be reconstructed numerically because the 2 GiB is one uncalibrated planning allowance. No confirmed double counting, speculative-page duplication, or binary/decimal unit error was found. Do not interpret absence of measured component peaks as evidence to lower the allowance. No safety constant or model allocation limit changed.

The single current inference admission observation at **2026-10-25T12:15:13.385163Z**, UID501:

- Available proxy: **6,333,382,656 bytes / 5.90 GiB**.
- Requirement: **7,311,079,503 bytes / 6.81 GiB**; shortfall **977,696,847 bytes / 0.91 GiB**.
- Normal pressure (1), swap use **0**, swapouts **0**; compressor occupied **1,635,811,328 bytes**.
- Free disk **40,726,437,888 bytes / 37.93 GiB**, above unchanged 20 GiB minimum.
- Known resident Ollama models **0**. The owned lab lease prevents concurrent lab workers; Ollama observation does not prove absence of every possible third-party ML process.
- Admission: **DENIED — memory-headroom**. Diagnostic process exit **0** means observation succeeded, not admission success. No smoke runner/model worker was started, no retry or alternative load attempted.

Evidence: `Evidence/ModelLabCalibration/admission.json` records exact diagnostic invocation and returned observation. `lab.sample` uses `(free including speculative + inactive) × page size`; it does not add speculative twice, compressed memory or swap. This is a reclaimability proxy, not guaranteed allocatable physical RAM. The later training-preparation check sampled its separate higher gate; it was not an inference retry.

## Installed source and lower-memory profiles

Full cached-model file identity and runtime source hashes passed again. Model: `mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit`, revision `b3252a2f97102b1fb1571fec2c9b27219a8536be`, 4-bit/group64, 28 layers, 2 KV heads, head dimension128. Weight SHA256 `daeab4764fb420d161721791cf2e509e2de81a7af4223646e7bed2bf82c57b58`. Python3.11.15, MLX0.32.4, MLX-LM0.32.2 and locked runtime hashes remain verified. Existing community conversion-lineage and tokenizer provenance limitations in BASELINE-READINESS remain; no artifact replacement occurred.

Actual installed primary sources inspected:

- `.venv/lib/python3.11/site-packages/mlx_lm/generate.py`: SHA256 `9d46803799f99d6fc7c35fff2d4357c79b1a25ae98cc63efeaaebeb50a7b5f33`.
- `.venv/lib/python3.11/site-packages/mlx_lm/models/cache.py`: SHA256 `c96cb169fd5e0ec4584a162dd61dc62ab08ccdca03a9850f8a491ce6809145e6`.

`generate_step` supports `max_kv_size`, `prefill_step_size`, `prompt_cache`; `stream_generate` passes them to non-speculative generation. With `draft_model=None`, no speculative model is used. Speculation removes `max_kv_size` in the installed code; it must stay disabled for a bounded cache. `make_prompt_cache` creates RotatingKVCache for a non-null cap. Cache allocation grows in 256-token steps. Multi-token rotating prefill may temporarily retain up to **cap + chunk size − 1** tokens; concatenation can temporarily coexist with prior buffers. A logical payload estimate is not a physical peak bound.

`config/inference-profiles-v1.json` freezes three **assessment-only** candidates:

| Profile | Context / output | KV cap / prefill chunk | BF16/FP16 logical KV payload | Original cases fitting both caps | Fully specified fixture fits? | Admission |
|---|---|---|---|---:|---|---|
| historical-v1 | 1024 / 320 | unbounded / 2048 | 28 MiB at declared context | 60/60 | Yes | BLOCKED |
| compact-v1 | 768 / 256 | 768 / 64 | 21 MiB | 43/60 | Yes | BLOCKED |
| minimal-v1 | 512 / 128 | 512 / 32 | 14 MiB | 6/60 | No | INELIGIBLE; also insufficient headroom |

All use one session/model, seed42, temperature0, deadline120s, no draft model, no persistent prompt cache, unchanged 2 GiB runtime allowance and 4 GiB reserve. The historical profile describes existing generation settings; the reduced candidates **are not wired into the execution runner or represented as operationally verified configurations**. No runner was reconfigured to silently truncate the frozen corpus. Runtime integration of a reduced profile remains deferred until a safe admitted experiment is possible.

KV illustration: `2 × 28 × 2 × 128 × tokens × 2 bytes` =28,672 bytes/token. Actual dtype, backing allocation, temporaries and peak remain unmeasured; FP32 would double this payload. Compact rotating theoretical token bound is831; minimal543 before the total-session token cap, with allocator granularity and transient copies additional. The prior max prompt412 plus output320 is732 tokens, so real historical workloads already use less than the declared1024 upper cap. One cannot claim a measured7 MiB saving for all actual cases.

Shorter context/output limits bound retained state and work, not weight memory. Smaller prefill chunks can reduce activation/scratch demand at the cost of more steps; no empirical scratch coefficient exists here. No persistent prompt cache avoids cross-request retention but does not eliminate necessary per-generation KV or the separate allocator cache. None of these observations justify discounting the bundled allowance by0.91 GiB. All candidates retain the same conservative **6.81 GiB** admission requirement. There is no demonstrated approved lower-memory configuration that passes current policy.

Tokenizer-only assessment ran with network access denied in an owned child and local-only/trust-remote-code-disabled loading. IPv4 and IPv6 denial probes passed. No model weights/tensors were loaded. The fully specified fixture requires **354 prompt tokens +190 expected completion tokens** (544 total); compact reserves354+256=610 ≤768. Minimal cannot hold its190-token expected response in128 output tokens. Original expected completions reach280, explaining compact's incomplete corpus coverage. Counts are token-budget checks, not generated successes.

## Dataset audit and signatures

All **60 original rows, answers, 36/12/12 splits, and held-out fingerprint remain unchanged**. Corpus fingerprint `abf23fcff91b782691691bf8eaf9bcce71f41681d799d13b44af9d0ca91d6065`; held-out `a54ad20e1714038515e6af090b286929e1a810b5bc5de7663256a7c8f0d9ef6c`.

`config/evaluation-signatures-v1.json` records each case's source-row hash, split, project/proposal/snapshot identity, exact path, create/update operation, expected absent/SHA256 revision, UTF-8 byte count/content hash or exact refusal hash, contract coverage and ambiguity. Production Swift hashing/codec/validator checks every original reference. All48 proposals are accepted; all12 fixed refusals are rejected as malformed proposal input, as intended by this lab protocol. These are reference-oracle replays, not model outputs.

- **48 positives:** exact target and project identity are supplied by the single editable target/context; operation is explicit create/full replacement; snapshot/revision are deterministically supplied from native hashing. All have expected reference content. However, none specifies the exact callable/type interface or executable behavioral assertions in its original prompt. Thus **0 qualify as strict semantic coding benchmark cases** under this audit. Each signature lists the missing contract, rather than inventing missing IDs or pretending the answer was part of the prompt.
- **12 negatives:** exact safe refusal is supplied by the system contract. These are evaluable literal protocol-rejection cases, not semantic coding cases. Other safe wording can score false. Rejected garbage is not an expected refusal. The codec cannot itself distinguish safe natural-language refusal from malformed text.
- `ml1-052` asks to omit identity while context already supplies it; not a genuine missing-context test. `ml1-060` has a benign placeholder source comment; not a realistic injected command payload.
- All positives are small, one-file, independently authored synthetic tasks; updates replace a generic placeholder. No realistic multi-file dependencies, compiled behavior, concurrency correctness or independent human review is proven. Generalization and edge semantics remain untested.

`config/calibration-fixture-v1.json` derives **only from training case ml1-001**, retaining its answer and bindings while explicitly supplying required literal UTF-8 content in a separate prompt. This is one fully specified copy/protocol calibration task, **not a novel coding-ability test or an added training row**. No held-out answer was modified, no training data expanded, no result-guided answer tuning occurred. It was tokenized but never generated.

## Evaluator implementation

`ModelLab/calibration.py` adds a reusable local response scorer (`--responses <absolute JSONL path>`, each record exactly `caseID` and `response`). It verifies frozen data and calls the **existing actual Swift production validator**, not a Python replacement. Worker lab results now attach `calibratedMetrics` from the same native validation result. Outputs remain inert; no paths or text are executed/applied.

Separate metrics cover JSON validity, schema validity, project/proposal/snapshot identity, target path, operation, revision, exact content-reference agreement, native acceptance/rejection, literal unauthorized-request refusal and overall task success. Behavioral assertion correctness and semantic coding correctness remain **null/unverified**. Nonapplicable proposal fields for refusal cases are null, not misleading passes.

For original positive cases, an exact accepted reference match yields `overallTaskSuccess=null`, because coding semantics are not established. Reference/structure mismatch yields false; this is failure against this exact contract, not proof a different implementation is semantically wrong. Refusal success requires the exact instructed refusal plus native rejection; malformed JSON alone cannot pass. A well-formed, native-accepted proposal containing wrong content explicitly fails content and overall scoring.

Historical `accuracy`/`exactTaskCorrect` fields are preserved for compatibility and now explicitly labeled **legacy exact-reference rate, not semantic coding correctness** in worker summaries; `semanticCodingAccuracy` is null. No new accuracy result exists for this task. Do not aggregate null/unverified positives as successful coding tasks or zero errors.

## Verification and commands

All command paths below are actual invocations in the repository. Recorder JSON files and stdout/stderr are in `Evidence/ModelLabCalibration/`; they retain timestamps, actual argv, exits and timeout/cleanup flags. The first full run passed111; after completing per-case coverage metadata, final focused/full/replay ran again. No tests were removed or weakened.

| Check | Result | Exit |
|---|---|---:|
| New focused regression suite | **20 passed** | 0 |
| Complete Model Lab suite | **111 passed** (91 existing +20 new) | 0 |
| Independent fresh-process replay | **111 passed** | 0 |
| Frozen dataset/native-reference checks | 60 rows,48 accepted references,12 intended refusals | 0 |
| Offline profile tokenizer assessment | all60 originals +1 derived fixture; no weights | 0 |
| Training configuration compatibility | verified installed defaults/CLI and unchanged prepared split hashes; no training | 0 |
| Python AST syntax checks | calibration, worker, recorder, new tests | 0 |
| Git diff whitespace check | passed | 0 |
| Native app tests / Debug / Release | NOT RERUN: no shared native source/configuration changed in this task | — |
| Real model load/generation/footprint/MLX peaks/cleanup | NOT TESTED: admission denied | — |

Actual commands (including repeated static audit, which does **not** recheck or retry inference admission):

| Action | Command | Exit | Evidence record |
|---|---|---:|---|
| calibration-audit | `$REPO_ROOT/ModelLab/.venv/bin/python $REPO_ROOT/ModelLab/calibration.py` | 0 | `continuation-calibration-audit-20261025T121756Z.json` |
| calibration-audit | `$REPO_ROOT/ModelLab/.venv/bin/python $REPO_ROOT/ModelLab/calibration.py` | 0 | `continuation-calibration-audit-20261025T121901Z.json` |
| calibration-focused | `$REPO_ROOT/ModelLab/.venv/bin/python -m unittest discover -s $REPO_ROOT/ModelLab/tests -p test_calibration.py -v` | 0 | `continuation-calibration-focused-20261025T121816Z.json` |
| calibration-focused | `$REPO_ROOT/ModelLab/.venv/bin/python -m unittest discover -s $REPO_ROOT/ModelLab/tests -p test_calibration.py -v` | 0 | `continuation-calibration-focused-20261025T121940Z.json` |
| calibration-replay | `$REPO_ROOT/ModelLab/.venv/bin/python -m unittest discover -s $REPO_ROOT/ModelLab/tests -v` | 0 | `continuation-calibration-replay-20261025T121956Z.json` |
| calibration-tests | `$REPO_ROOT/ModelLab/.venv/bin/python -m unittest discover -s $REPO_ROOT/ModelLab/tests -v` | 0 | `continuation-calibration-tests-20261025T121840Z.json` |
| calibration-tests | `$REPO_ROOT/ModelLab/.venv/bin/python -m unittest discover -s $REPO_ROOT/ModelLab/tests -v` | 0 | `continuation-calibration-tests-20261025T121943Z.json` |
| calibration-training-config | `$REPO_ROOT/ModelLab/.venv/bin/python $REPO_ROOT/ModelLab/training_preparation.py` | 0 | `continuation-calibration-training-config-20261025T121911Z.json` |

The training preparation interface is compatible with installed MLX-LM0.32.2, retains existing two-layer rank4/four-step smoke settings and hash-bound frozen prepared splits. Its training-only admission check was also denied (9.8090 GiB required). No LoRA/QLoRA, gradient, adapter or model numerical operation was started. A successful full baseline remains mandatory before any separately authorized training attempt.

Tests cover all60 reference signatures, deterministic hashes/splits, wrong content despite valid JSON/native acceptance, each binding/path/operation/revision mismatch, garbage versus safe refusal, duplicate keys, null semantic outcomes, train-only fixture derivation, unchanged reserves, KV limits and no admission discount. Existing cancellation/monitor/lease/fail-closed/no-network-fallback tests remain passing. Source hashes also confirm no application or shared core change, so prior native build evidence is historical, not relabeled as a new build.

## Blockers, status and next milestone

**Inference BLOCKED.** Actual load latency, process physical footprint, MLX active/cache/peak, first-token latency, generation result and numerical cleanup remain unavailable, not zero. No model process existed to reap. Do not claim the denied run verified GPU/runtime cleanup. No download, forced app termination, cache purge, cloud request, host-reserve reduction, UI work or production AI activation occurred. Child-only network denial is not a claim of production filesystem/process containment.

**Training NOT READY.** Compatible configuration and a structurally valid seed corpus are insufficient:0 strict coding cases, no successful baseline, no empirical memory calibration, and higher training admission blocked. More independently reviewed tasks/contracts are needed before fine-tuning. A new version should specify callable interfaces, edge cases and inert checkable assertions, preserve reviewed held-out isolation, and review all36 existing training rows before reuse; do not inflate counts automatically.

**Proposed next functional milestone:** a separately scoped single admitted literal-content offline smoke, with explicit reduced-profile runner integration, fresh unchanged-policy admission, owned-process footprint measurement and actual MLX peak/cleanup monitoring. If headroom is still inadequate, stop before loading. Only after measured safe loading should runtime components be calibrated; no reduced allowance is justified by the present results. Then run a reviewed semantic dataset baseline before considering training. This report does not authorize or begin that next milestone.

Calibration files added: `ModelLab/calibration.py`, `ModelLab/tests/test_calibration.py`, `ModelLab/config/evaluation-signatures-v1.json`, `ModelLab/config/inference-profiles-v1.json`, `ModelLab/config/calibration-fixture-v1.json`, this report. Existing files modified only `AGENTS.md`, `ModelLab/mlx_worker.py` (separate metric attachment/label), `ModelLab/verify.py` (fixed evidence commands). Generated evidence is ignored, not staged. Prepared training/config reproduction retained identical versionable content.

Branch **main**, HEAD **0a3e91c731a716945853a6b84bcfaaf6d9e672d3**, nothing staged, no commit/push. The prior extensive uncommitted application/UI/voice/clipboard and Model Lab work is preserved. `before.json` plus `final-review.json` bind the preservation comparison. Only the three listed existing files changed during this milestone; no prior file was deleted.

Final working tree (many entries predate this milestone):

```text
 M .gitignore
 M AGENTS.md
 M App/AppComposition.swift
 M App/FoundationView.swift
 M App/WesleyFlowApp.swift
 M Docs/Phase1B/MODEL-PROVIDER.md
 M Docs/Phase1B/SECURITY-BOUNDARIES.md
 M Packages/WesleyFlowCore/Package.swift
 M Packages/WesleyFlowCore/Tools/OllamaEvaluation/EvaluationMain.swift
 M WesleyFlow.xcodeproj/project.pbxproj
?? App/ClickableDictationPill.swift
?? App/DictationModel.swift
?? App/DictationPreferences.swift
?? App/GlobalDictationView.swift
?? App/SystemWideDictationCoordinator.swift
?? AppTests/DictationTests.swift
?? AppTests/GlobalDictationTests.swift
?? Docs/ModelLab/
?? Docs/Phase1C/
?? ModelLab/
?? Packages/WesleyFlowCore/Sources/Domain/AppOpeningCommand.swift
?? Packages/WesleyFlowCore/Sources/Domain/Dictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/LocalPromptRewriter.swift
?? Packages/WesleyFlowCore/Sources/Persistence/SwiftDataDictationHistoryStore.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeAppOpening.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/
```
