# Milestone 30 — Custom offline model roadmap

26 October 2026. Hardware: M4 MacBook Air, 16 GiB unified memory. **Research and contract refinement completed; training NOT READY and NOT STARTED. No custom trained model is claimed.**

## Recommendation

Keep Apple's system on-device model as the current preview provider. For a future independently owned coding model, retain the cached **Qwen2.5-Coder-1.5B-Instruct, MLX 4-bit dense decoder**, and first obtain a resource-admitted unmodified baseline. If that cannot be made practical, the previously pinned **Qwen2.5-Coder-0.5B-Instruct MLX 4-bit** is the best next acquisition candidate to *test*, not an established quality winner. Do not acquire it automatically. Favor a small task-specific LoRA adapter over pretraining or full fine-tuning.

Personalization should target stable output conventions, constrained prompt organization and explicitly reviewed style preferences. It cannot compensate for missing permission checks, weak task specifications, a blocked inference runtime or the current rewrite validator rejecting broad paraphrases. Do not spend training time teaching a model to bypass those boundaries.

Current decision: **no training run, model load, new model acquisition or production integration**. Use the existing Mac for data review, deterministic validation and bounded admitted inference; consider external training only after evaluation and data gates pass.

## Reinspection and preservation

Inspected AGENTS.md; Model Lab reports, V1/V2 data/manifests, preparation/scoring/runner/admission code, current smoke configuration, cached artifact pin, installed MLX model/trainer source, current preview/provider constraints and recent real-inference reports. Preserved all outstanding UI, voice, clipboard and milestone28/29 work.

Cached model was reverified by **streaming file hashes only**, with no MLX import or model materialization:

- Repository: `mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit`.
- Revision: `b3252a2f97102b1fb1571fec2c9b27219a8536be`.
- Weight bytes: 868,628,559; total pinned files: 880,172,100 bytes.
- Weight SHA256: `daeab4764fb420d161721791cf2e509e2de81a7af4223646e7bed2bf82c57b58`.
- Manifest fingerprint: `30c8f6ade14e037f9e001c95ef377e62d59cdbbd23e3d48e99e1e05d997403ac`.

All 265 pre-existing versionable files match task-start hashes. Frozen V1/V2 corpora, manifests, prepared splits and existing settings/source remain intact. Model-cache identity is separately verified; derived validator build products were refreshed, not model artifacts. No fresh host-memory observation was taken because this milestone schedules no model execution.

Historical evidence must remain distinct: Apple's standalone rewrite succeeded on 25 October in about 2.21 seconds (`FIRST-LIVE-OFFLINE-AI.md`); subsequent production-contract attempts have been resource-blocked, including milestone28. This proves one native inference pathway, not an MLX baseline, reliable tone differentiation or custom training.

## Five incomplete contracts: separate research revisions

V1 and V2 answers/splits remain frozen. V2 still reports **43 complete coding contracts, five incomplete coding contracts and 12 literal refusal checks**. New `ModelLab/data/research-contracts-v3.json` is a five-case **research supplement**, not a replacement benchmark or prepared training corpus.

Each revision has fresh project/proposal identities, four-file synthetic repository context (README, input-domain documentation, supporting source comment and target), one approved editable target, production snapshot/file revision hashes, the inherited operation and original approved reference source. Supporting files are inert JSON strings; no repository tree is materialized, generated code executed or proposed source change applied.

| V2 source / inherited split | New explicitly bounded specification | Policy consequence |
|---|---|---|
| 001 / train | Both signed operands in ±1,000,000; exact sum | Maximum absolute result 2,000,000; no overflow on 64-bit Int |
| 009 / validation | ≤1,024 integers, each in ±1,000,000; ordered squares | Maximum square 10^12; empty remains empty |
| 026 / train | Position 0…999,999; plain one-based decimal string | No negative input; maximum incremented value 1,000,000 |
| 040 / train | Equal-length arrays ≤1,024; elements in ±1,000,000; ordered products | Maximum absolute product 10^12; unequal lengths excluded |
| 047 / held-out | ≤1,024 strings, aggregate UTF-8 ≤1 MiB; Swift Character counts | Grapheme total ≤1,048,576; bounded resource domain |

These are **new bounded-domain tasks**, not invented wrapping/trapping policies retroactively attributed to the old tasks. Unsupported inputs are outside the new benchmark; the unchanged reference functions are not claimed to enforce those preconditions themselves. The text-count contract still requires independent Swift/Unicode behavioral validation.

All five revised reference proposals pass the **existing production Swift structural validator**. Arithmetic bounds are checked with Python integer arithmetic. This is not independent proof of the Swift implementations' behavior. Every revision is marked `SPECIFIED_PENDING_INDEPENDENT_REVIEW`, `trainingEligible=false`, `referenceSwiftExecuted=false`, `independentHumanReviewed=false`.

Supplement fingerprint: `bf27f82fd841c750bd2bac5933a135f0c34af56c8f240e4f82ab0b137091052c`. Reproduce with `python3 ModelLab/research_contracts_v3.py`; the default verifies frozen content/provenance and does not rewrite it. The builder invokes only the hash-bound data validator, not an agent or model.

**Additional independently validated training pairs created: zero.** No bulk examples, renamed duplicates or model-generated answers were promoted to increase the count. Independent review has not occurred; training remains gated.

## Dataset readiness and separation

Existing complete-only V2 prepared data:

| Split | Coding | Literal refusals | Total |
|---|---:|---:|---:|
| Training | 29 | 4 | 33 |
| Validation | 7 | 4 | 11 |
| Held-out evaluation | 7 | 4 | 11 |

V3 research membership is 3 train / 1 validation / 1 held-out, inherited by source family. **None are added to those prepared counts.** V1, V2 and V3 descendants must never be concatenated as independent examples. A held-out repair stays held-out in its new version; its revised score cannot replace an older result. These developer-visible benchmarks are not blind independent evaluation.

Readiness gaps:

- Too few distinct coding training families for a credible personalized coding-model claim; most are small single-file exercises, not realistic integration work.
- Static source equality permits only the reviewed LF/CRLF variants. A different correct algorithm is unreviewed, not automatically semantically wrong.
- Realistic multi-file *context* is now represented for five revisions; multi-file edit correctness is not implemented or validated.
- No independent human/behavioral validation; V3 tokenizer/sequence budgets have not been measured. Existing V2 budget evidence cannot be reused for the larger V3 contexts.
- Repeated refusal text tests a shared literal protocol. Existing cases052/060 are not genuine missing-context/source-injection benchmarks; do not advertise them as such.
- Exact/near-duplicate heuristics help but do not establish semantic independence. Keep every paraphrase/template descendant in one split. Freeze a new family-level split before collecting a future corpus; exclude held-out examples from prompts, tuning and checkpoint selection.

For future additions, require independently reviewed specification, expected behavior, authorized path/revision, a trusted test oracle, provenance and split-family assignment before counting a pair. For rewrite personalization, collect only explicit opt-in synthetic or authorized input/accepted-output pairs; do not mine dictation history, private documents or clipboard contents. Obtain separate consent before any external upload.

## Tasks that may benefit from personalization

| Task | Potential value | Better baseline / limit |
|---|---|---|
| Proposal JSON conventions and concise rationale style | Consistent project-specific output patterns | Real codec/validator still rejects malformed or unauthorized proposals; never learn authority |
| Prompt section classification | Stable concise organization of supplied requests | Existing extractive planner may suffice; compare without adding requirements |
| Preferred rewrite tone | Repeated user-approved phrasing patterns | Establish real tone quality first; current lexical gate rejects most paraphrases |
| Domain vocabulary | Some style/context familiarity | Exact names, numbers, identifiers, URLs and paths belong in deterministic protection/context |
| Coding micro-edits | Narrow formatting/API conventions | Tiny models cannot be assumed to learn general engineering competence from 29 exercises |
| Permissions, source effects, shell/app automation | **Not a fine-tuning task** | Deterministic permission/execution boundaries, never model self-approval |
| Changing project facts | Little benefit from storing in weights | Explicit authorized context/retrieval, not memorization or private-data training |

Use separate rewrite and coding evaluations/adapters if both are pursued. Do not merge unrelated objectives just to enlarge a dataset. Personalization is justified only by a repeated measured baseline failure that prompting/deterministic formatting cannot solve safely.

## Candidate comparison and licensing

All open candidates below are dense causal Transformer decoders. Quality rankings and M4 tokens/second are **unmeasured**; family marketing or parameter count is not evidence of Wesley Flow task quality. Sources checked 26 October 2026.

| Candidate | Quality hypothesis to test | Memory/speed implication | Training/integration | License |
|---|---|---|---|---|
| Cached Qwen2.5-Coder1.5B MLX4bit | Retain as coding control; no successful local baseline | 0.809 GiB weights; 28 MiB illustrative KV; no measured speed | Existing pinned Qwen2 worker/codec bridge; lowest acquisition effort | Apache2.0 pinned upstream |
| Qwen2.5-Coder0.5B MLX4bit | First smaller coding candidate, not proven adequate | 0.259 GiB weights; 12 MiB KV; lower weight traffic does not guarantee latency | Qwen2 interface present; smaller artifact/pin/tokenizer/runner support still needs verification | Apache2.0 upstream; community conversion provenance recorded |
| Qwen3-0.6B BF16 publisher artifact | Alternative instruction/multilingual candidate | 1.400 GiB stored weights, 112 MiB KV; reasoning can increase output/latency | Qwen3 implementation present; non-thinking chat-template/EOS/output behavior must be tested; no pinned MLX4bit conversion approved | Apache2.0 card and pinned LICENSE |
| SmolLM2-360M-Instruct BF16 | Tiny English-oriented instruction baseline; coding fit unknown | 0.674 GiB weights, 40 MiB KV; size alone cannot predict quality/speed | Llama-compatible configuration present; tokenizer/template/conversion untested | Publisher card declares Apache2.0; no standalone LICENSE file listed at pin |
| Apple system model | Existing native preview control with historical rewrite success | System managed; recent memory failures; do not apply MLX weight accounting | Existing FoundationModels provider, separate adapter constraints below | Apple SDK/toolkit terms, not open weights |

Publisher sources: [Qwen2.5-Coder0.5B card](https://huggingface.co/Qwen/Qwen2.5-Coder-0.5B-Instruct), [pinned MLX0.5B configuration](https://huggingface.co/mlx-community/Qwen2.5-Coder-0.5B-Instruct-4bit/blob/6b16732e5af5cd9bd600186ad59fa618867ef7a4/config.json), [Qwen3 card](https://huggingface.co/Qwen/Qwen3-0.6B), [SmolLM2 card](https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct). The Qwen3 card documents a non-thinking mode; it must be explicitly tested rather than assuming the existing Qwen2 template accepts it. Publisher benchmarks use different settings and are not substituted for paired local tests.

New research pins (metadata/config/card/license only):

- Qwen3: `c1899de289a04d12100db370d81485cdf75e47ca`; published safetensors total 1,503,300,328 bytes.
- SmolLM2: `a10cc1512eabd3dde888204e902eca88bddb4951`; published safetensors total 723,674,912 bytes.
- Previously researched MLX0.5B: `6b16732e5af5cd9bd600186ad59fa618867ef7a4`; 278,064,920 weight bytes / 289,601,531 total pinned bytes; acquisition still unapproved.

`ModelLab/provenance/milestone30/SOURCES.json` records URLs, revisions, sizes and SHA256 for the new public metadata. No weights/tokenizers downloaded. Installed MLX-LM0.32.2 source was inspected with AST/text only: Qwen2, Qwen3 and Llama required ModelArgs are present in the candidate configurations. Tensor layout, numerical loading, tokenizer/EOS and quantization compatibility remain unverified. Keep original license notices/provenance and review redistribution requirements before packaging an adapter/base model. No remote model code is trusted.

### Apple adapter route

Apple's current adapter page requires Apple Silicon with at least32GB or Linux GPUs, plus Python3.11. Its listed26.0.0 toolkit is incompatible with macOS27+. This Mac is16GB/macOS27.2, so neither local training capacity nor toolkit compatibility passes. Adapters are system-model-version-specific; toolkit download needs Developer Program membership/terms, and deployment needs an entitlement. No toolkit, account or setting was accessed. A larger machine alone does not resolve the OS-version blocker. [Apple adapter requirements](https://developer.apple.com/apple-intelligence/foundation-models-adapter)

## Memory requirements: planning, not a fit claim

The existing Lab policy is unchanged:

- Inference: pinned weight bytes + **2 GiB runtime allowance + 4 GiB system reserve** available before load.
- Training: that requirement + **3 GiB training allowance**.
- Existing pressure, swap, disk reserve, monitoring, timeout, cleanup/quarantine and no-retry rules remain authoritative. These constants are planning guards, **not experimentally established peak bounds**.

| Artifact/dtype actually researched | Stored weights GiB | BF16 KV at 1,024 total tokens | Inference policy available GiB | Training policy available GiB |
|---|---:|---:|---:|---:|
| Cached Qwen1.5B4bit | 0.8090 | 28 MiB | 6.8090 | 9.8090 |
| Pinned Qwen0.5B4bit | 0.2590 | 12 MiB | 6.2590 | 9.2590 |
| Qwen3 publisher BF16 | 1.4001 | 112 MiB | 7.4001 | 10.4001 |
| SmolLM2 publisher BF16 | 0.6740 | 40 MiB | 6.6740 | 9.6740 |

KV illustration is `2 × layers × KV-heads × head-dimension × tokens × 2 bytes`, batch1, excluding allocator structures. Qwen3 has8 KV heads/head dimension128; Qwen0.5B has2/64. Thus the nominally similar small models have very different cache needs. KV is already within the runtime allowance in the table, not added twice. These are metadata calculations, not observed resident memory, and do not reserve fewer resources for smaller weights.

Other memory includes quantization scales/zeros, embeddings/output projection, lazy materialization/dequantization, attention/MLP scratch, Python/Metal runtime, prompt prefill, retained training activations, gradients and optimizer state. Quantization is not file-size-to-RAM equivalence. Batch/sequence length, targeted layers, checkpointing and kernels affect peaks. Even a hypothetical zero-byte model still needs6GiB under the unchanged inference policy.

The historical ModelLab2A available observation was5.55GiB, below both pinned Qwen inference requirements. It is **not a current observation**. Do not repeatedly sample/load until it passes. Apple provider admission remains separate; its historical success cannot certify any MLX requirement.

LoRA reduces trainable parameters, not the cost of backpropagating through the frozen base. For illustration, rank4 on all seven linear projections in the last two Qwen blocks would give approximately183,296 adapter parameters for0.5B and329,728 for1.5B. At an illustrative16bytes/parameter for adapter/gradient/optimizer/master storage, those account for only2.8/5.0MiB; base/runtime/activations can still dominate. Actual selected modules, dtypes and optimizer allocations must be logged after an admitted run. No measured training peak exists.

The [MLX-LM LoRA guide](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/LORA.md) supports adapter training on quantized bases and recommends batch/layer/sequence reductions for memory. Its implementation is not automatically identical to CUDA NF4/paged-optimizer [QLoRA](https://arxiv.org/abs/2305.14314). Do not infer a Mac fit from the paper's GPU results.

## Small training plan — not executed

Retain the existing `ModelLab/config/smoke.json` unchanged. Its rank4 / last2 layers / batch1 / sequence1024 / four-step configuration is a proposed **feasibility smoke**, not a quality-training recipe.

| Stage | Required evidence before proceeding |
|---|---|
| Independent dataset gate | Reviewer approves domain policies, expected outputs, split/family isolation and trusted behavioral tests. V3 remains excluded until then. No independently verified extras means no enlarged training set. |
| Independent methodology gate | Freeze metric definitions, baseline/adapter comparison, allowed variants, error taxonomy and held-out access policy; independently review the evaluator. |
| Baseline gate | Real admitted unmodified-model outputs scored through the existing validator; separate structural, semantic, refusal and resource outcomes. A static reference replay is insufficient. |
| Resource gate | Fresh admission immediately before load, independently reviewed monitoring/cleanup behavior, no threshold reductions; reject before model import/load on failure. |
| Separately authorized smoke | Cached pinned base, frozen reviewed train/validation only, batch1, sequence≤1024 without truncation, rank4, last2 layers, checkpointing, prompt masking, seed42, LR1e-5, dropout0, four optimizer steps,120-second bound. Stop on guard failure; no auto-retry. |
| Artifact gate | Genuine nonempty adapter tensors, hash-bound base/tokenizer/config/data/runtime identity, real loss/step logs, memory/swap/pressure/cleanup results; fixture/simulated adapters never count. |
| Quality pilot | Only after smoke fits and a larger reviewed task-specific corpus exists: preregister a small step budget/checkpoint selection using validation only. Do not invent an optimal epoch count from60 cases. |
| Held-out gate | Compare the selected adapter and base on untouched eligible families once; report paired wins/regressions and uncertainty. Do not train on benchmark failures or use test loss to select checkpoints. |

Installed source inspection found that default target keys include supported linear modules in the selected last layers, not just q/v. Record the actual trainable module names/count; do not quote q/v-only memory estimates for the current config. MLX's `scale=8` is a direct multiplier in the inspected LoRA layer. It is not interchangeable with PEFT's `lora_alpha` convention without conversion/scaling checks. [PEFT configuration reference](https://huggingface.co/docs/peft/package_reference/lora)

All these gates remain closed for training now. A four-step artifact, if eventually produced, would prove a smoke ran—not that the model is useful, personalized or safe.

## Evaluation design

Keep separate tracks:

1. **Proposal structure/authorization:** real Swift codec/validator; exact identities, snapshot, path, operation, revision and one-target constraints. Do not implement a second incompatible validator. A valid proposal remains inert text.
2. **Coding behavior:** independent trusted tests over explicit bounded domains, edge/Unicode cases and untouched supporting files. Until a separately authorized contained harness exists, source matching remains static and behavioral results remain unavailable. Never execute model-generated code in this milestone or alter real repositories.
3. **Rewrite quality:** synthetic/authorized pairs, blind paired base/adapter review of meaning, grammar, requested tone, conciseness and unsupported additions; exact protected-span checks. Distinguish appropriate unchanged from missed improvement. The20-case milestone28 rubric is a separate rewrite set, not coding training data.
4. **Safety:** refusal precision/recall on real unsupported/unauthorized requests, literal injection treated as data, no extra fields or authority creation, no effect ports. Redesign deficient refusal fixtures in a new version before claiming coverage.
5. **Performance:** identical pinned engine/context/output budgets on this M4: load latency, prefill/TTFT, decoding tokens/sec, wall latency, process footprint/MLX peak, pressure/swap, cancellation/cleanup. Report cold/warm separately. Context is total prompt+output, not1024 plus unbounded generation.

Report admission/resource blocks separately from invalid outputs and semantic errors; exclude unattempted generations from quality denominators while reporting completion/blocked rates. On eligible behaviorally scored tasks, report paired case results, not just a single aggregate. No local speed figure or quality improvement was measured here. Promotion requires no critical protected-span/authorization regressions and independently approved quality/latency margins set **before** testing. Current tiny/non-blind held-out sets cannot establish broad reliability.

## External hardware and cost tradeoffs

| Option | Benefit | Cost/limits |
|---|---|---|
| Keep this16GiB Mac | No new purchase; local/private review, validator work, eventual guarded small inference | Training feasibility unproven; competing apps and sustained memory use remain bottlenecks |
| Access an existing32–64GiB Apple Silicon machine | More headroom, same MLX stack and simpler adapter-format continuity | Best if available to borrow; no hardware guarantees data quality, speed or OS compatibility |
| Rent a24GiB CUDA GPU for a bounded pilot | Separates training VRAM from this Mac; likely enough capacity for a small adapter experiment, subject to its own gate | Different trainer/quantization/backend; conversion/logit-equivalence and local revalidation required; data upload/spend need separate approval |
| Buy higher-memory hardware | Helpful for frequent sustained offline iteration | Defer until admitted baseline and training pilot identify the bottleneck; do not buy merely to fix unvalidated data |
| External SSD | Stores models, checkpoints and logs | Does not increase unified-memory headroom or justify relaxed admission |

Apple lists M4 Air configurations up to32GB; a higher-memory system is a different hardware configuration, not disk expansion. [M4 Air specifications](https://support.apple.com/en-gb/122209)

For a concrete **illustrative compute budget**, Runpod's public pricing page checked26October lists24GB RTX A5000 at$0.27/hour and RTX4090 at$0.89/hour. Two billed GPU-hours would be$0.54/$1.78 **compute only**, not a quote or measured end-to-end training cost. Storage, transfer, availability, provisioning, tax and engineering/review time are additional. No instance/account was accessed or purchased. Recheck prices before separately authorizing a job. [Provider pricing](https://www.runpod.io/pricing)

External hardware materially reduces the *training-memory obstacle* but does not fix this Mac's inference budget, missing independent semantic review or format-conversion work. For a one-off pilot, borrowing a suitable Mac or a small capped GPU rental is a better experiment than an immediate machine purchase. For repeated private offline development, a higher-memory Apple Silicon machine may reduce operational complexity; benchmark first. CUDA-produced adapters cannot be assumed drop-in compatible with MLX or Apple's system model.

## Integration plan

No production provider wiring changes now. If a base+adapter eventually passes gates:

- Package exact base revision, tokenizer/template/EOS, quantization, adapter hashes/config, license/provenance and evaluation report as one model identity. Reject mismatched adapters; do not silently load a substitute.
- Keep the worker behind the current proposal-only provider boundary with explicit input authorization, bounded context/output, admission, one session/lease, deadline, cancellation and uncertain-cleanup quarantine.
- Pass all proposal JSON through the existing validator; pass rewrites through current protected-span/fidelity checks. User review/copy remains explicit; automatic insertion stays disabled.
- No OpenCode activation, tools, arbitrary shell, source writes, cloud fallback or automatic downloads. Any future effect broker or evaluation executor needs separate authorization/containment.
- Keep deterministic original-text fallback and the existing Apple provider as a separately evaluated option. A trained model must not silently expand the kinds of transformations accepted by production.

## Verification and limitations

| Check | Actual result | Exit |
|---|---|---:|
| Cached model streaming hash verification | Pinned files verified; no load |0|
| Existing production validator rebuild |21 production source files, Swift6 complete concurrency, SDK27; no source edits |0|
| Five V3 proposal references |5/5 structurally accepted; semantics pending |0|
| New focused research tests |9 passed |0|
| Full Model Lab suite |152 passed,143 existing +9 new |0|
| Independent fresh-process replay |152 passed |0|
| Preservation |265 pre-existing versionable files unchanged |0|
| Model inference / training / generated Swift execution |NOT RUN |—|
| App full suite/Debug/Release |NOT RERUN: research-only additions; no app source change |—|

Evidence: `Evidence/Milestone30/{cached-model-verification,validator-build,focused-final,full-final,replay-final,preservation,memory-planning,installed-source-inspection}.json`, associated logs and task-start hashes. Full/replay commands: `/opt/homebrew/bin/python3.11 -m unittest discover -s ModelLab/tests -v`; focused adds `-p test_research_contracts_v3.py`. Validator command: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 ModelLab/build_validator.py`. No existing test or assertion was weakened.

Initial checks correctly refused the stale validator source hash; rebuilding refreshed only derived artifacts. An initial new-test import failure (`ModuleNotFoundError: lab`, exit1) was fixed by using the existing module-path pattern; final checks above passed. The failures were not converted to passing results by disabling fingerprint checks.

Public metadata provenance is pinned/checksummed; web/metadata research is not model acquisition. Source-only MLX interface presence is not numerical compatibility. V3 arithmetic checks are not independent Swift behavioral proof. No new observed peak RAM, inference speed, adapter weights or model accuracy exists.

## Explicit blockers and next justified experiment

1. Independent review of V2/V3 behavioral contracts/evaluation is missing. V3 remains ineligible; no training can start on this milestone's evidence.
2. No real MLX baseline or empirical loading/training peaks; current headroom is not remeasured. Smaller artifacts do not bypass the fixed allowances.
3. Rewrite tone quality and broad paraphrase acceptance remain separate unresolved product constraints.
4. Apple adapter toolkit is incompatible with the current host/16GiB training capacity.
5. New model acquisition, external compute/upload, behavioral code execution and training have no authorization here.

**Next experiment, separately scoped:** first obtain independent review of the five revised specifications and evaluation method. Then, after safely reducing competing memory use, take one fresh admission observation for the **already cached1.5B model**. If it passes, run one network-denied bounded `ml2a-003` baseline (previous tokenizer evidence418 prompt tokens + maximum320 generation =738≤1024; batch1;120-second deadline), collect actual output/peak/pressure/swap/cancellation/cleanup evidence and score the inert output with the production validator. If it fails, do not load or retry. No downloads or training belong in that experiment.

Only if preserving sufficient headroom for the cached baseline is impractical should a separate request approve the pinned289,601,531-byte0.5B acquisition and identity/runner/tokenizer verification before its own admitted test. External training follows a proven baseline, reviewed data/methodology and an explicit capped authorization—not a failed local guard.

## Git state

Branch `ci/milestone-27`, HEAD `3befcf20ff60220c5f678aa1c3c1a137064b4ea3` unchanged. Nothing staged, committed or pushed. All prior work preserved. New research files only: this roadmap, `research_contracts_v3.py`, its nine-test module, the V3 research JSON supplement and eight public metadata/provenance files. Derived evidence/build products remain ignored. Working tree remains intentionally dirty with the earlier application work.

**CUSTOM MODEL TRAINING: NOT STARTED. NO CUSTOM TRAINED MODEL PRODUCED.** Stop after milestone30.
