# Model Lab 2A — Dataset V2 and First Inference Gate

25 October 2026. **V2 static source-contract dataset/scorer verified; first live inference BLOCKED; training NOT READY.** No model response was generated. These results do not demonstrate general semantic coding accuracy, executable behavioral correctness, successful model loading, or training feasibility.

## 1. Scope and preservation

Read AGENTS.md, all existing Model Lab reports, V1 manifests/corpus, calibration evaluator, runner/worker/admission code, cached model metadata and installed Qwen2/MLX interfaces. Branch `main`, HEAD `0a3e91c731a716945853a6b84bcfaaf6d9e672d3`. A pre-edit SHA256 snapshot covers all existing versionable files, including untracked work; final comparison confirms no native app/core/voice/clipboard file changed, no file deleted, nothing staged.

V1 is unchanged byte-for-byte, including all original held-out answers and splits. V1 corpus fingerprint remains `abf23fcff91b782691691bf8eaf9bcce71f41681d799d13b44af9d0ca91d6065`; held-out `a54ad20e1714038515e6af090b286929e1a810b5bc5de7663256a7c8f0d9ef6c`. V2 is a **new benchmark version**, not a repair silently applied to V1 or a model-result-guided answer change. No real repository content, private transcript or user data was used.

## 2. Dataset V2 — implemented, with explicit limitations

Files:

- `ModelLab/data/corpus-v2.jsonl`:60 separate V2 cases (the48 coding cases plus12 protocol refusals).
- `ModelLab/config/dataset-v2.json`: frozen row/signature hashes, source-V1 binding, split IDs and held-out fingerprint.
- `ModelLab/semantic_v2.py`: authored API/domain/example specifications, V2 signatures, scoring and reference replay.
- `ModelLab/build_dataset_v2.py`: deterministic reproduction; default verifies frozen output, explicit `--write` was used during authoring only.

Final V2 corpus fingerprint: `9f6a68aae503f390ea42663826bf76c53e367aa8ee305b0e3197e9578d3b7ce6`.
Final V2 held-out fingerprint: `900e3bad723a39e0aac69c5e86b4e7b628a961b4a2834c5fdfb8f165fd64d449`.

Every coding case defines a separate synthetic project identifier and proposal ID, an in-memory project tree (absent target or synthetic placeholder), native workspace snapshot digest, exact Swift API, explicit instruction/input domain, create or full-file **update** operation, relative target path, expected absent/SHA256 file revision, reference UTF-8 content, acceptable source variants and rejection conditions. Native production hashing derives snapshot/revision identities. These disposable synthetic snapshots are data; no actual project files are read, modified or compiled. All reference body text remains unchanged from V1; V2 uses new identities and instructions and therefore has separate results.

Specifications add concrete edge examples: zero/negative evenness, signed-zero division, empty arrays, stable duplicate removal, invalid indices, Unicode grapheme counts, empty-versus-nil distinctions, Gregorian century cases, inclusive range boundaries, stable partitions and exact enum/property contracts. They explicitly name callable/type interfaces that V1 omitted. They are authored static specifications, not independently executed assertions.

**43 coding contracts COMPLETE for the stated static approved-source criterion;5 INCOMPLETE.** Unresolved cases retain their original reference but cannot earn semantic/content success or enter prepared training data:

| Case | Split | Unresolved contract |
|---|---|---|
| ml2a-001 | train | Int addition overflow policy is unspecified. |
| ml2a-009 | valid | Int square overflow policy is unspecified. |
| ml2a-026 | train | Negative position and Int increment overflow policy are unspecified. |
| ml2a-040 | train | Int product overflow policy is unspecified. |
| ml2a-047 | test | Aggregate count overflow/resource policy is unspecified. |

No wrapping, trapping, saturating or rejecting overflow policy was invented for these cases. Other V2 contracts explicitly state their supported domains (for example finite nonnegative rectangle dimensions); this does not alter V1 behavior or claim that out-of-domain behavior was evaluated.

The 12 unsupported-request cases have an exact instructed refusal and remain literal protocol checks. `ml2a-052` still has identity in supplied context, so it is not a real missing-context test; `ml2a-060` still has a benign comment, so it is not an injected-source attack benchmark. No stronger coverage is claimed.

### Scoring scope and acceptable variants

The requested expected-content route is implemented: compare generated full-file content to the statically reviewed reference, allowing only LF↔CRLF line-ending variants. Arbitrary whitespace is **not** ignored: Swift whitespace can affect syntax/operator parsing and string literals. Other implementations are labeled `unreviewedVariant`; failure to match the closed accepted set is **not proof that a different algorithm is behaviorally incorrect**. Reference implementations have not been compiled/executed or independently human reviewed.

This is a reproducible, narrower **static source-contract benchmark**, not a general semantic execution harness. API/domain/examples improve clarity, and wrong accepted JSON cannot pass content scoring, but runtime semantics remain **PARTIAL / NOT TESTED** under the prohibition on generated-code execution. Function implementation bodies are not included in generation prompts. Cases021–024 explicitly prescribe their entire type/member shape, so those four are declaration-shape checks rather than algorithm-generation evidence. Signature/behavior examples are requirements, not generated results. The smoke candidate is a coding contract, not the previous literal-content copy fixture.

## 3. Evaluation engine and frozen reference results

The actual existing `CodingProposalCodec`, `ProposalHashing` and `CodingProposalValidator` are used through the unchanged hash-verified Swift bridge. No second proposal validator was implemented. Python scores task expectations after native validation; it has no authorization/effect port.

Separate output fields cover:

- Native JSON/schema validity and acceptance/rejection.
- Project, proposal and snapshot binding; target path; operation; expected file revision.
- Approved source-content assertion matching, separate from structure.
- Exact refusal correctness, separate from arbitrary malformed-output rejection.
- Contract completeness and overall success within the explicitly stated static scope.

`behavioralExamplesExecuted=false` and `behavioralRuntimeCorrect=null` on every result. An incomplete case has null content/semantic result and cannot receive overall true. Well-formed, native-accepted wrong content scores false for content/overall. Native rejection still fails the structural gate even if source content matches.

The frozen reference replay checked all 60 cases:

| Category | Result |
|---|---|
| Complete coding references | **43/43 static contract matches** |
| Complete literal refusals | **12/12 expected refusals** |
| Incomplete coding references | **5 unscored**, not5 successes |
| Actual model-generated cases | **0** |
| Executed behavioral examples / compiled generated programs | **0** |

These are **oracle/evaluator verification results**, not model accuracy. V1 calibration metrics remain unchanged. A separate response-scoring CLI accepts JSONL records with exactly `caseID` and `response`, using `semantic_v2.py --responses <absolute-path>`; it verifies V2 frozen identities and invokes the real validator. Model output remains inert text.

## 4. Single host measurement and inference outcome

Exactly one live host admission observation was taken this task, at **2026-10-25T12:26:34.245567Z** (UID501). Subsequent calculations/tests reuse it; no host remeasurement, polling for a pass or inference retry occurred.

| Item | Actual |
|---|---:|
| Available RAM proxy | **5,959,368,704 bytes / 5.55 GiB** |
| Cached1.5B weight bytes | 868,628,559 |
| Runtime allowance, unchanged | 2,147,483,648 bytes /2 GiB |
| macOS reserve, unchanged | 4,294,967,296 bytes /4 GiB |
| Required available | **7,311,079,503 bytes /6.81 GiB** |
| Shortfall | **1,351,710,799 bytes /1.26 GiB** |
| Pressure | Normal, code1 |
| Swap / swapouts | 0 bytes /0 pages |
| Compressor occupied | 2,290,679,808 bytes |
| Known resident Ollama models | 0 |
| Free disk | 40,722,124,800 bytes /37.93 GiB |

Sampler remains `(free including speculative + inactive) × page size`; no speculative double counting and no compression/swap treated as capacity. This remains a proxy, not guaranteed reclaimable RAM. Admission **DENIED: memory-headroom**. Diagnostic command exited0 because measurement succeeded; that is not an inference pass. `Evidence/ModelLab2A/admission.json` contains the exact invocation, observation and rejection. No model worker was spawned; no 1.5B output, load/generation timing, process footprint or MLX peak exists. Those fields are **NOT TESTED**, not zero. No model cleanup claim is made for a worker that never existed.

The fully specified proposed smoke case `ml2a-003` is in training, complete, synthetic and output-inert. Cached tokenizer preflight found **418 prompt tokens,191 reference-completion tokens,609 full tokens**. Prompt +320 maximum generation =738 ≤1024. All60 V2 examples fit both the current 1024 sequence and 320 output budgets; no truncation occurred. Runtime identity and all cached model hashes were reverified. The tokenizer-only child used the fixed network-denial profile; IPv4/IPv6 denial probes passed. No numerical model load occurred.

The small `one_admission_gate` helper is dependency-injected, samples once and does not call its executor on denial. Regression tests cover both synthetic denial and this exact recorded denial with a forbidden executor. It is **not a newly operational V2 inference launcher**. Because admission failed, no existing safety checks were bypassed to route V2 through the legacy V1 runner; V2 runtime integration/monitoring would still need verification in a separately scoped admitted attempt. No broad production AI or training entry point was added.

## 5. Requested0.5B model research — metadata only

Pinned public artifact: [mlx-community/Qwen2.5-Coder-0.5B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen2.5-Coder-0.5B-Instruct-4bit/tree/6b16732e5af5cd9bd600186ad59fa618867ef7a4), revision **6b16732e5af5cd9bd600186ad59fa618867ef7a4**. All 11 published file sizes sum to **289,601,531 bytes /0.2697 GiB**; weights **278,064,920 bytes /0.2590 GiB**. Published weight SHA256 `162e6341bc937d1880cc7f76fbb80831f4fb30684345c59a7b055a5c716d25bd`. No weights/tokenizer files were downloaded.

[Publisher configuration](https://huggingface.co/mlx-community/Qwen2.5-Coder-0.5B-Instruct-4bit/blob/6b16732e5af5cd9bd600186ad59fa618867ef7a4/config.json) declares Qwen2,24 layers, hidden896,14 attention heads,2 KV heads, head dimension64, tied embeddings,4-bit/group64 and32768 positional capacity. The [model card](https://huggingface.co/mlx-community/Qwen2.5-Coder-0.5B-Instruct-4bit/blob/6b16732e5af5cd9bd600186ad59fa618867ef7a4/README.md) states MLX-LM0.19.3 conversion from Instruct and Apache-2.0. Pinned upstream [license](https://huggingface.co/Qwen/Qwen2.5-Coder-0.5B-Instruct/blob/ea3f2471cf1b1f0db85067f1ef93848e38e88c25/LICENSE) confirms Apache2.0; its text is retained locally.

`ModelLab/config/model-0.5b-research-v1.json` records pinned file sizes/digests, metadata and `acquisitionApproved=false`. Bounded public API/config/card/license responses are captured under `ModelLab/provenance/model-lab2a/`; retrieved config/card Git blob hashes match the pinned API. SHA256 provenance:

| Metadata source file | Bytes retrieved | SHA256 |
|---|---:|---|
| `community-api.json` | 5617 | `c65cb350df29a595b70474e7e736e2fef53d8d473c5c2139c681625287f97f25` |
| `community-pinned-api.json` | 5617 | `c65cb350df29a595b70474e7e736e2fef53d8d473c5c2139c681625287f97f25` |
| `community-config.json` | 863 | `3542f21e28bfe8422fe98249af39a5b7770fa41ca7d60cda1b72906c2c53b998` |
| `community-README.md` | 1137 | `edf947c2f10021f57b7382a69ab9f844cd174a6e2a13c31b4658933f54172c94` |
| `upstream-api.json` | 6788 | `e3371a6d44a78e5f3da5232b812b74449099279f141ffbdb2c7e90b7d67571b2` |
| `upstream-LICENSE.txt` | 11343 | `832dd9e00a68dd83b3c3fb9f5588dad7dcf337a0db50f7d9483f310cd292e92e` |
| `upstream-config.json` | 659 | `b1e58593cd31852f7da5c2fc31ddf6135b9c066c0fd9177a4bbe95717083adff` |

Installed MLX-LM0.32.2 Qwen2 `ModelArgs` required metadata fields are present and the architecture/quantization are supported at the source/interface level. **Tensor layout, tokenizer/chat-template/EOS compatibility, numerical loading and empirical peaks remain NOT TESTED**; metadata cannot prove them. Conversion lineage is a publisher statement. No remote code was trusted or executed.

Conservative model-specific inference estimate: **278,064,920 +2 GiB runtime +4 GiB reserve =6,720,515,864 bytes /6.2590 GiB**. Runtime overhead was **not scaled linearly** by weights. Illustrative BF16 KV at1024 is12 MiB versus28 MiB for 1.5B; this excludes scratch, allocator, Python and materialization peaks and is not an admission discount. Reusing the sole observation gives a **761,147,160-byte /0.709 GiB shortfall**. Smaller is still **BLOCKED at this observation**, not a guaranteed fit.

A possible separate acquisition/inference experiment is recorded, **not started or approved**: acquire only the pinned289,601,531-byte set, verify every file hash and tokenizer compatibility, preserve ≥20 GiB disk and unchanged4+2 GiB reserves, admit freshly immediately before one network-denied single-session `ml2a-003` generation (1024 context/320 output/120s), monitor pressure/swap, actual owned-process footprint and MLX peaks, and reap owned resources. No training, project effects or fallback model. The current disk observation is adequate for the download, but current RAM observation is not. A future task must implement/verify V2 runner and smaller-model identity support rather than passing a new artifact into1.5B-only assumptions.

## 6. Training preparation and leakage

V2 retains V1 source-family membership in separate36 train/12 validation/12 test manifests. Incomplete cases stay in the benchmark for inspection but are excluded from prepared training/evaluation input files:

| Prepared split | Complete coding | Literal refusals | Total |
|---|---:|---:|---:|
| train |29|4|33|
| valid |7|4|11|
| test |7|4|11|

`ModelLab/artifacts/v2-prepared/{train,valid,test}.jsonl` and their hash-bound manifest are isolated from V1 preparation. Tests inspect actual message/project IDs and file hashes, not only split labels. No train/evaluation project overlap exists. Exact coding-source duplicates and cross-split token-set similarity ≥0.8 were checked using behavioral instructions/reference code, excluding shared protocol/identity boilerplate; none were found. This heuristic does **not prove semantic independence**. Identical refusal strings deliberately cross splits: they test one known protocol, not12 independent learned tasks. V1 and V2 derive from the same source families; do not combine both as independent training/benchmark evidence. V2 is developer-visible, not a newly blind external test set.

Installed trainer defaults were inspected via AST, runtime identity verified, existing rank4/two-layer/four-step configuration keys checked, and every prepared example fits1024 tokens. No model load, trainer call, optimizer, LoRA/QLoRA, adapter or additional RAM sample occurred. A configuration is not evidence that training fits.

**Training NOT READY:** only 29 complete coding training contracts, narrow one-file reference matching,5 unresolved contracts, no independent human/executable behavioral validation, no successful full model baseline, and no empirical training-memory evidence. More reviewed diversity and a separate authorized baseline are required before fine-tuning; no numeric dataset target was fabricated to suggest readiness.

## 7. Verification evidence

Final results:

| Check | Result | Exit |
|---|---|---:|
| Focused new V2 tests | **32 passed** |0|
| Full Model Lab suite | **143 passed** (111 existing +32 new) |0|
| Independent fresh-process replay | **143 passed** |0|
| Frozen V2 reproduction | Exact final corpus/signatures |0|
| Native validator reference replay |43 static coding +12 refusals;5 unscored |0|
| Cached tokenizer preflight |60/60 budgets fit; no weights |0|
| Prepared splits/trainer interface |33/11/11; no training |0|
| Smaller-model offline metadata assessment | Identity/license/source compatibility checked |0|
| Python AST syntax and Git whitespace checks | Passed |0|
| Native Swift tests / Debug / Release | NOT RERUN; no shared native code/config changes |—|
| Actual model inference / behavioral program execution | BLOCKED / NOT AUTHORIZED |—|

Exact final commands and exits (working directory `$REPO_ROOT`):

| Action | Actual command | Exit | Evidence JSON |
|---|---|---:|---|
| lab2a-audit | `$REPO_ROOT/ModelLab/.venv/bin/python $REPO_ROOT/ModelLab/semantic_v2.py` | 0 | `continuation-lab2a-audit-20261025T123852Z.json` |
| lab2a-dataset | `$REPO_ROOT/ModelLab/.venv/bin/python $REPO_ROOT/ModelLab/build_dataset_v2.py` | 0 | `continuation-lab2a-dataset-20261025T123851Z.json` |
| lab2a-focused | `$REPO_ROOT/ModelLab/.venv/bin/python -m unittest discover -s $REPO_ROOT/ModelLab/tests -p test_semantic_v2.py -v` | 0 | `continuation-lab2a-focused-20261025T123857Z.json` |
| lab2a-preflight | `$REPO_ROOT/ModelLab/.venv/bin/python $REPO_ROOT/ModelLab/v2_preflight.py` | 0 | `continuation-lab2a-preflight-20261025T123854Z.json` |
| lab2a-prepare | `$REPO_ROOT/ModelLab/.venv/bin/python $REPO_ROOT/ModelLab/v2_preparation.py` | 0 | `continuation-lab2a-prepare-20261025T123856Z.json` |
| lab2a-replay | `$REPO_ROOT/ModelLab/.venv/bin/python -m unittest discover -s $REPO_ROOT/ModelLab/tests -v` | 0 | `continuation-lab2a-replay-20261025T123912Z.json` |
| lab2a-small-model | `$REPO_ROOT/ModelLab/.venv/bin/python $REPO_ROOT/ModelLab/small_model_feasibility.py` | 0 | `continuation-lab2a-small-model-20261025T123744Z.json` |
| lab2a-tests | `$REPO_ROOT/ModelLab/.venv/bin/python -m unittest discover -s $REPO_ROOT/ModelLab/tests -v` | 0 | `continuation-lab2a-tests-20261025T123859Z.json` |

Each JSON/log is in `Evidence/ModelLab2A/` with exact argv, timestamps, outputs, exit and timeout/cleanup flags. Earlier authoring/replay records are preserved; final fingerprints above are authoritative. The public research command was `/usr/bin/python3 /tmp/wf_small_model_metadata.py`, exit0; `metadata-research-command.json` records its source hash and inert saved source copy. It fetched only bounded public metadata/license content; no model acquisition occurred.

Tests include exact expected signatures, correct static scoring, wrong target/operation/revision/identity/content, malformed changes and extra fields/files, non-executed assertions, incomplete null outcomes, safe refusal versus garbage, LF/CRLF variants without unsafe whitespace normalization, frozen V1/V2 versioning, held-out bindings, actual prepared split isolation, metadata pin tampering, and no executor after failed admission. Existing111 tests were retained unchanged. “Independent replay” means a separate process reran the suite, not independent human/model review.

## 8. Requirements status and next step

| Area | Status |
|---|---|
| New reproducible V2 contracts for all 48 coding cases | COMPLETE representation;43 static COMPLETE,5 explicitly INCOMPLETE |
| Separate structure/content/refusal scoring through real validator | COMPLETE for closed-source criterion |
| General executable semantic evaluation | PARTIAL / NOT TESTED; reference examples inert |
| One resource measurement and no load after denial | COMPLETE; inference BLOCKED |
| First real offline model output and memory metrics | BLOCKED; not obtained |
| Pinned0.5B research, no download/load | COMPLETE metadata; numerical compatibility NOT TESTED |
| Training readiness/configuration inspection | COMPLETE preparation; training NOT READY and NOT STARTED |
| Tests/replay/preservation/report | COMPLETE |

Stop at Model Lab2A. The next functional milestone should separately authorize a single pinned-model experiment after enough headroom exists, including verified V2 runner integration, unchanged-policy admission, actual footprint/MLX/cancellation/cleanup measurements and one inert output through this scorer. Alternatively resolve the five missing policies and independently review the 43 source contracts while memory remains blocked. No training or later milestone begins automatically.

## 9. Git status and files

Existing versionable files changed this task: **AGENTS.md and ModelLab/verify.py only**. Added V2 builder/scorer/preflight/preparation, metadata-only feasibility tool,32 tests, frozen V2 data/manifest, public research provenance and this report. Generated evidence and prepared artifacts are ignored, not staged. No dependency, UI, model admission constants, native provider, voice, clipboard or existing calibration implementation changed.

Branch `main`; HEAD `0a3e91c731a716945853a6b84bcfaaf6d9e672d3`. No commit, push or remote created. Working tree remains intentionally dirty with preserved prior work. `before.json` / `final-review.json` record per-file preservation.

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
