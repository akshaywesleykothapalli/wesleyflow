> **Current follow-up:** The pinned artifact has since been acquired and tokenizer checks verified. See [MODEL-LAB1-BASELINE-FOLLOWUP.md](MODEL-LAB1-BASELINE-FOLLOWUP.md) for the current state. The preparation checkpoint below is historical; its pending-download statements describe that earlier checkpoint.

# Model Lab 1 — preparation verified; live model work blocked

25 October 2026 · MacBook Air M4, 16 GiB unified memory. No commit or push.

The standalone lab and deterministic validation path ran successfully. **Offline inference is NOT VERIFIED. Adapter training is NOT VERIFIED.** No model weights were acquired, no model was loaded, no generated code was executed, no adapter was produced, and no model accuracy or latency exists. The requested end-to-end working trainable model remains incomplete.

## Implementation and environment

- Added only `ModelLab/`, this documentation, and an authorization append to `AGENTS.md`. Every other one of 163 pre-existing versionable files retains its pre-task hash; no file is missing. All existing voice, UI, clipboard, permission, persistence and provider work remains intact. No production package dependency was added.
- Isolated Python 3.11.15 venv; installed MLX 0.32.4, mlx-metal 0.32.4 and MLX-LM 0.32.2. `pip check` exited 0. Full resolved versions and wheel SHA256 hashes are in `ModelLab/requirements.lock`; this lock is specific to macOS arm64/Python 3.11. The venv occupies about 478 MiB. Global Python packages were not changed.
- Actual installed `python -m mlx_lm lora --help` exited 0. CLI output is captured in `ModelLab/provenance/installed-cli.json`; 202 installed MLX-LM source hashes are checked before a heavy worker starts. Official local-JSONL loader, `train_model`, callback keys and configuration defaults were inspected in installed source. CLI help availability does not establish training compatibility with this particular model.
- Xcode 27.0 beta (27A5237l), Apple Swift 6.4, SDK 27.0, host macOS 27.2 (26B5112a), explicit developer directory `/Applications/Xcode-beta.app/Contents/Developer`. The bridge freshly compiles unchanged production Domain and Workspace sources with Swift 6, complete strict concurrency, warnings as errors and arm64 macOS 26.0 deployment target. macOS 26 runtime compatibility was not newly tested.
- Separate lab components: pinned model/catalog inventory; strict JSONL validation; production Swift validator bridge; synthetic preparation; distinct inference/training admission; owned bounded worker; fixed evaluation scoring; adapter manifests and guarded post-training comparison. These are developer research tools, not a second production task coordinator or an application feature.

## Selected candidate and acquisition proposal — not approved

The proposed artifact is [mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit/tree/b3252a2f97102b1fb1571fec2c9b27219a8536be), pinned to `b3252a2f97102b1fb1571fec2c9b27219a8536be`. All 11 repository files total **880,172,100 bytes** (0.820 GiB); the safetensors weight file is **868,628,559 bytes**. Its published LFS SHA256 is `daeab4764fb420d161721791cf2e509e2de81a7af4223646e7bed2bf82c57b58`. Exact file sizes and content hashes are recorded in `config/model-pin.json`.

Upstream [Qwen2.5-Coder-1.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct/tree/2e1fd397ee46e1388853d2af2c993145b0f1098a) is pinned to `2e1fd397ee46e1388853d2af2c993145b0f1098a`. Its [Apache 2.0 license](https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct/blob/2e1fd397ee46e1388853d2af2c993145b0f1098a/LICENSE) was captured and hashed. The community artifact declares Apache 2.0; its README identifies conversion from Instruct with MLX-LM 0.18.1. This is a community conversion, not a first-party Qwen MLX release.

Important provenance limitations: the community metadata names the non-Instruct base while its README names Instruct; its chat template differs from the pinned current upstream template. These are documented, not silently reconciled. Config specifies Qwen2, 28 layers, hidden size 1536, 12 attention heads/2 KV heads and 4-bit group size 64. MLX supports quantized adapter tuning, but exact artifact/tokenizer loading and numerical compatibility remain NOT TESTED. Source snapshots and SHA256 records are under `provenance/`; no remote Python code is trusted.

Acquisition would add about 0.820 GiB of repository artifacts, plus bounded adapters/checkpoints and temporary/runtime files. Maintain at least 20 GiB free disk after setup; do not count weights as the entire inference/training footprint. No acquisition command is included or executed. A separate explicit approval is still required for this exact source/revision/size/license/disk impact. No larger fallback, conversion, Ollama adapter import or cloud inference is enabled.

## Dataset, schema and quality

Actual corpus: **60 synthetic seed examples**, with 48 positive targets and 12 unsupported requests. Train **36**, validation **12**, held-out test **12**. Each split contains both create and full-content update operations; each also has four refusal examples. Families are frozen into one split and all inputs are independently authored synthetic text. No private project, transcript, credential or conversation was used.

This falls short of the requested 200–500 target. Quality is agent review plus structural-validator checking, not independent human review or proof that every proposed Swift function is behaviorally correct. Generated snippets were never compiled or executed. Do not inflate the corpus with renamed examples; expand only after a separately versioned review.

Actual existing v1 wire uses `create` and **`update`**, not `replace`. IDs, snapshot digest and revisions come from production `ProposalHashing`; strict decoding and validation use the unchanged `CodingProposalCodec` and `CodingProposalValidator`, with synthetic snapshots and an explicit editable-target allowlist. The bridge returns data only and has no effect port.

There is no first-class semantic model-refusal object in the current production schema. Unsupported targets use the fixed text `Cannot propose this request: unsupported or unauthorized operation.` It maps to existing malformed/proposalRejected behavior. The scorer counts that exact refusal only when refusal is expected; arbitrary malformed output does not earn a correct-refusal score. A typed refusal integration would require separate Domain design approval.

Validation rejects malformed JSONL, duplicate keys/nonfinite values, missing/extra fields, invalid identities/types, duplicate IDs/content, unsupported targets, inconsistent target JSON, family leakage and cross-split token-set Jaccard similarity ≥0.8. This heuristic is not proof of semantic independence. Production target checking accepted all 48 intended proposals and rejected all 12 refusal strings. Ten separate adversarial proposals—unauthorized path, traversal, absolute path, mismatched project binding, stale revision, wrong snapshot, command field, deletion, empty changes and duplicate key variants—were rejected in regression tests. The actual test defines ten mutations; no unsafe proposal is a desired training output.

Corpus fingerprint: `abf23fcff91b782691691bf8eaf9bcce71f41681d799d13b44af9d0ca91d6065`.

Evaluation fingerprint: `a54ad20e1714038515e6af090b286929e1a810b5bc5de7663256a7c8f0d9ef6c`.

`config/dataset-v1.json` records fixed IDs and prepared-file hashes. Preparation is deterministic and excludes expected answers from generation prompts. Full corpus, prepared splits, held-out identity, production validator sources/libraries and model/runtime artifacts are verified before use. Preparation holds an exclusive lab lease so it cannot race an active run. Tokenizer sequence lengths and generation-budget coverage remain NOT TESTED because the tokenizer artifacts have not been acquired; the worker rejects rather than silently truncates examples that exceed the 1024-token limit.

## Resource admission and actual measurements

Measured at 2026-10-25T10:10:15.690712+00:00 (15:40 IST), after native builds finished:

| Observation | Actual |
|---|---:|
| Physical unified memory | 16.00 GiB |
| Available proxy | 4,908,367,872 bytes / 4.57 GiB |
| Compressor occupied memory | 3.83 GiB |
| Swap used | 1.07 GiB |
| Swapouts counter | 774,481 pages |
| Pressure | Normal, code 1 |
| Resident Ollama models | 0 |
| Free disk | 26.35 GiB |
| Inference admission required | 7,311,079,503 bytes / 6.81 GiB |
| Training admission required | 10,532,304,975 bytes / 9.81 GiB |

Available is `(free including speculative + inactive) × page size`, matching corrected application accounting. Speculative is not added twice; compressed memory and swap are not added as available RAM. This is a headroom proxy, not guaranteed reclaimability. Swap figures use the native displayed counter's precision.

Preserved inference allowance: weight bytes + 2 GiB runtime + 4 GiB system reserve. Provisional training additionally reserves **3 GiB** for activations/optimizer. Both require normal pressure, known zero Ollama residency and ≥20 GiB free disk. These planning allowances are not measured peak footprints and have not been calibrated by a successful run.

Disk now passes following the separately authorized 59-folder obsolete build-cache cleanup. The cleanup freed about 27.5 GiB; current lab environment/build/evidence consumes some of that space. Existing installed `qwen3:8b` and `qwen2.5-coder:7b` were catalogued through read-only localhost metadata; neither was loaded or altered. Both have zero resident instances.

Inference and training **fail memory-headroom admission**. Model acquisition is also unapproved and the artifact is absent. No threshold, compression setting, daemon setting or system security setting was changed. No unrelated application was terminated.

## What actually ran and outcome states

| Component | Classification | Actual result |
|---|---|---|
| Isolated runtime/CLI/source inspection | COMPLETE | Installed help and package checks passed; no model load |
| Dataset validation/preparation | SIMULATED / COMPLETE for seed corpus | 60 targets through actual production validator; 200–500 target PARTIAL |
| Expected-output oracle replay | SIMULATED | 60/60 expected targets scored correctly; this is **not model accuracy** |
| Config/data dry run | PARTIAL | Config, structural data and installed CLI verified; tokenizer/numerical run NOT TESTED |
| Baseline inference | BLOCKED | 0/12 held-out cases generated; accuracy null, latency/peak MLX memory unavailable |
| Four-step adapter smoke | BLOCKED | No training iterations, loss, checkpoints or trained weights |
| Post-training adapter comparison | BLOCKED / NOT TESTED live | No adapter; comparison scoring has deterministic tests only |
| Production integration | NOT TESTED / deferred | No MLX provider activated; no effects |

The baseline/train/compare **gate-check commands exited 0 because they successfully evaluated the guards**. Their JSON state is BLOCKED. Exit 0 must not be reported as successful inference or training.

Candidate smoke remains capped at seed 42, batch 1, sequence 1024, rank 4, last 2 layers, learning rate 1e-5, **4 steps**, validation and checkpoint every 2 steps, 120-second deadline. The exact installed official training entry is used directly to preserve the finite-loss callback; the CLI wrapper replaces its callback. No smoke command was run after admission denial.

The official trainer adjusts its own process's MLX wired allowance to the device recommendation. The lab does not alter OS sysctls and retains its independent allocator cap and parent monitor. This live interaction remains NOT TESTED. The monitor cancels/reaps only its own fixed child process group on SIGINT/SIGTERM, deadline, unknown observations, reserve/pressure failure, foreign residency, excess compression growth or sustained swap growth >256 MiB in two samples. Unknown cleanup writes a quarantine record; there is no automatic retry or quarantine clearing. Power loss/parent force-kill and operating-system containment are not proven by fixtures.

If training later succeeds, manifests bind actual adapter bytes, adapter configuration, model revision, config, corpus, evaluation, environment and finite-loss steps. Comparison requires the same baseline identity/settings/held-out coverage and fresh inference admission. It reports correctness, invalid/schema failures, unsafe attempts, false rejections, latency and MLX peak allocation. No automatic promotion or publication occurs.

## Verification evidence and issues corrected

- **58 deterministic lab tests passed**, then **58 passed in independent replay**. These include strict parsing, split leakage, balanced operation coverage, actual production target/rejection behavior, model identity/path/symlink checks, bounded adapter manifest extents, separate training admission, cancellation/deadline/shutdown races, no launch when blocked, full-corpus tamper detection, exclusive preparation, scoring and comparison. No arbitrary sleeps are used in concurrency tests.
- **902 expanded native cases passed** (406 test declarations) in a fresh Debug build/test, then **902 passed in independent replay**; zero failures/skips. App/voice/clipboard source and existing tests are unchanged.
- Debug build **exit 0**; Release build **exit 0**. Build products are isolated under `DerivedData/ModelLab1`; the canonical `Run` app was not replaced. Strict-concurrency bridge compilation **exit 0**, no warnings under warnings-as-errors.
- The first Python run exposed an eager dictionary fallback lookup for a SHA256-only artifact. It failed one test, was corrected, and the same regression test passes. Later review added full-corpus binding and exclusive preparation before final verification; no existing test was removed or weakened.
- An initial `test-without-building` against UI4 cache exited **65** because its app test bundle was absent. Source tests that could load ran, but that invocation is recorded as FAILED. Fresh isolated native build/test and replay resolved this verification issue. A normal app-only build prunes hosted test products; do not treat an app build directory as a permanent test bundle.
- Xcode beta emitted its diagnostics-handler warnings. `xcresulttool` summary initially required native filesystem permission to construct its result database; authorized extraction subsequently succeeded. No source fix or safety workaround was applied for those tool messages.

Exact commands, exit codes, stdout/stderr, timestamps and `.xcresult` bundles are in `Evidence/ModelLab1/`. The following table is generated from the actual command records (all paths relative to repository root unless absolute):

| Record | Exit | Outcome |
|---|---:|---|
| lab-tests | 0 | Executed successfully |
| lab-replay | 0 | Executed successfully |
| validate | 0 | Executed successfully |
| prepare | 0 | Executed successfully |
| oracle-replay | 0 | Executed successfully |
| pip-check | 0 | Executed successfully |
| swift-tests | 65 | Initial cached-product failure |
| native-full | 0 | Executed successfully |
| native-replay | 0 | Executed successfully |
| debug | 0 | Executed successfully |
| release | 0 | Executed successfully |
| inventory | 0 | Executed successfully |
| sample | 0 | Executed successfully |
| dry-run | 0 | Executed successfully |
| baseline | 0 | BLOCKED gate check |
| train | 0 | BLOCKED gate check |
| compare | 0 | BLOCKED gate check |

```sh
# cwd: $REPO_ROOT
# DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
# lab-tests: exit 0
$REPO_ROOT/ModelLab/.venv/bin/python -m unittest discover -s ModelLab/tests -v
# lab-replay: exit 0
$REPO_ROOT/ModelLab/.venv/bin/python -m unittest discover -s ModelLab/tests -v
# validate: exit 0
$REPO_ROOT/ModelLab/.venv/bin/python ModelLab/lab.py validate
# prepare: exit 0
$REPO_ROOT/ModelLab/.venv/bin/python ModelLab/lab.py prepare
# oracle-replay: exit 0
$REPO_ROOT/ModelLab/.venv/bin/python ModelLab/lab.py oracle-replay
# pip-check: exit 0
$REPO_ROOT/ModelLab/.venv/bin/python -m pip check
# swift-tests: exit 65
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/UIRefinement4 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/ModelLab1/swift-tests.xcresult test-without-building
# native-full: exit 0
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/ModelLab1 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/ModelLab1/native-full.xcresult test
# native-replay: exit 0
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/ModelLab1 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/ModelLab1/native-replay.xcresult test-without-building
# debug: exit 0
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/ModelLab1 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug build
# release: exit 0
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/ModelLab1 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release build
# inventory: exit 0
$REPO_ROOT/ModelLab/.venv/bin/python ModelLab/lab.py inventory
# sample: exit 0
$REPO_ROOT/ModelLab/.venv/bin/python ModelLab/lab.py sample
# dry-run: exit 0
$REPO_ROOT/ModelLab/.venv/bin/python ModelLab/lab.py dry-run
# baseline: exit 0
$REPO_ROOT/ModelLab/.venv/bin/python ModelLab/lab.py baseline
# train: exit 0
$REPO_ROOT/ModelLab/.venv/bin/python ModelLab/lab.py train
# compare: exit 0
$REPO_ROOT/ModelLab/.venv/bin/python ModelLab/lab.py compare
```

Bridge compiler invocations/toolchain/source hashes are in `ModelLab/artifacts/validator-build.json`; installed CLI invocation/help and package hashes are in `artifacts/runtime-verification.json`; resolved download hashes are recorded in `requirements.lock` and the local install report. Install, CLI help, `pip check`, bridge compilation and environment version inspection all exited 0. `git diff --check` exited 0; credential-pattern scan found no matches (rg exit 1 means no match).

## Production integration boundary and remaining work

A future separately reviewed MLX provider can implement the existing Domain local-provider port using a validated model/context identity and explicit lease. It must preserve task cancellation/deadline propagation, proposal-only responses, strict codec/validator/snapshot checks, and user approval before effects. A Python worker result or adapter manifest is not an execution capability. No UI is changed and no production Swift dependency on Python/MLX was introduced. Existing Ollama guards, OpenCode-disabled state, Terminal manual-copy rule and declined accessibility-tree activation remain unchanged.

Readiness: preparation foundation is verified, **end-to-end Model Lab 1 remains PARTIAL/BLOCKED**. Recommended next functional milestone is an approved pinned-artifact acquisition followed by one guarded offline baseline only after sufficient memory headroom is available. No user app should be automatically closed to achieve admission. Tokenizer/token-budget conformance must then pass before model loading. Training still needs its separate higher admission and a verified matching baseline. Expand and independently review the corpus toward 200–500 before treating smoke results as useful model-quality evidence. No model should be promoted from four steps or loss alone.

## Git and preservation

Branch `main`; HEAD remains `0a3e91c731a716945853a6b84bcfaaf6d9e672d3`. Existing dirty work is preserved; working tree is intentionally not clean. Nothing staged, committed or pushed; no remote created. Only existing-file edit in this milestone is the Model Lab authorization appended to AGENTS.md; new lab source/data/config/reference files and this report remain untracked. venv, weights, artifacts, prepared runtime data, runs, build products and evidence are ignored. No private dataset or credential is included.

Detailed pre-task preservation hashes and current status are saved in `Evidence/ModelLab1/preservation.json` and `final-review.json`. The initial comparison checked 163 existing files, with only the expected AGENTS.md append changed and no missing files. This report is the stopping point for Model Lab 1; UI work and production AI remain paused.

Actual final status (preserved pre-existing changes plus the new lab/docs):

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
