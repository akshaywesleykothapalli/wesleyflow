# Phase1B.3A — memory accounting remediation

20 October2026, Asia/Kolkata. Parent checkpoint `b2f351cf1c5db772815fe10de236aae4394a1cb2`.

**Accounting correction verified; live inference remains unverified and resource-blocked.** All629 automated cases and independent replay passed; Debug/Release builds passed. No resource threshold, model selection/allowlist, shared daemon configuration or inference feature was changed. No model was downloaded, loaded or run. The prior [diagnosis](PHASE1B3A-MEMORY-DIAGNOSIS.md) is preserved byte-for-byte and included in this checkpoint as a historical investigation, not rewritten as a current measurement.

## Root cause and exact correction

Apple's Mach `free_count` already contains speculative pages. The old SystemInferenceMemory implementation added speculative_count again. See the installed macOS27.0 SDK `mach/vm_statistics.h:158–162` and [Apple's XNU contract](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h). The previous17.875MiB discrepancy was a sample-dependent duplicate, not a fixed correction to apply to every observation.

`Packages/WesleyFlowCore/Sources/SystemOperations/SystemInferenceMemory.swift` now calculates:

```text
correctedProxyBytes = (rawMachFreeIncludingSpeculative + inactivePages) × actualPageSize
```

An internal pure arithmetic helper makes the native category/byte conversion independently testable. It accepts UInt64 page counts, rejects zero page size, uses addingReportingOverflow and multipliedReportingOverflow, and throws the existing typed memoryAdmissionDenied on invalid/overflowing arithmetic. The native path validates getpagesize()>0 before conversion. It never saturates, wraps, subtracts speculative pages from raw free, or adds compressed/swap capacity. Host-port ownership, Mach/sysctl error behavior, pressure interpretation and swap observation remain unchanged.

Only this native sampler's arithmetic/comment and its test seam were changed in production Swift. Domain/provider/orchestrator/persistence code is unchanged. ModelProviders still compares the resulting proxy with stored package bytes +2GiB estimated runtime allowance +4GiB system headroom. The method's existing conservativeAvailableBytes property name is retained for compatibility; the value is a proxy, not a promise that all inactive pages are immediately reclaimable.

## Regression tests and observed evidence

Nine new MemoryAccountingTests functions produce16 expanded cases. They join the existing provider/proposal tests in ProviderTests.swift, with @testable SystemOperations access to the internal helper; no Xcode target, dependency or public authority was added. Existing tests were not deleted or weakened.

| Coverage | Assertion |
|---|---|
| Duplicate speculative accounting | Historical raw free9078, inactive276771, page16384 produces4,683,350,016 bytes, not the old4,702,093,312 |
| Zero speculative/free pages | Zero free with inactive capacity converts correctly; all-zero counts return0 |
| Units | Page sizes1,4096,16384,65536 preserve exact byte results |
| Large counts | Two UInt32.max counters convert without narrowing; the valid UInt64.max×1 boundary is preserved |
| Invalid/overflow input | Zero unit, addition overflow and three multiplication-overflow combinations throw typed denial |
| Stability | Repeating the frozen raw-count calculation100 times yields the same known oracle |
| Admission boundary | A duplicate-inclusive count would cross the existing threshold; the corrected count rejects twice, with no chat and no result |
| Lease/pressure | Exact-threshold input with nonnormal pressure rejects; a subsequent explicit normal-pressure fixture request succeeds once, proving ownership was released |
| Observation failure | Unavailable counters fail closed before chat |
| Existing coordinator | Approved synthetic preparation denied for memory reaches terminal failure, clears pending approval, yields no prepared proposal and sends no chat, including after shutdown |

All transports in these tests are deterministic actor-owned fixtures. A fixture generation response is not a live AI/model run. Existing cancellation, timeout, pressure, sustained swap-growth, quarantine/reconciliation, recovery, revocation and no-duplicate tests remain in the full suite. No new claim of OS containment or guaranteed model-compute cancellation follows from these passes.

## Updated resource observations and policy consistency

Fresh read-only samples were taken after all builds finished, at04:51:19–04:51:30UTC,10:21IST. Three raw Mach observations five seconds apart gave corrected proxies **4.8035,4.8234,4.8430GiB**. This report uses the minimum **5,157,666,816 bytes (4.8035GiB)** for comparison, without treating the short sample window as a future guarantee.

The first sample had16,384-byte pages, raw free52,864 including10,253 speculative, inactive261,935. Corrected result5,157,666,816 bytes; old formula5,325,651,968 bytes, a160.2031MiB overstatement. The regression's historical17.875MiB and this larger current discrepancy both follow from the same corrected category rule.

Physical memory was17,179,869,184 bytes (16GiB); pressure level1, normal. Initial swap occupancy2313.38MiB; memory_pressure reported57%, which is not a claim of9.12GiB safely allocatable headroom. Adjacent vm_stat data showed232,660 physical compressor pages and560,729 logical uncompressed pages stored in it. Those are separate physical/logical descriptions, not additive spare capacity. Sequential tool samples are not atomic with raw Mach reads. Full counters and command outputs/exits are in ignored evidence. Current data replace neither the historical4.36GiB diagnosis sample nor the earlier blocked evaluation's4.18GiB baseline.

| Accounting category | Interpretation retained |
|---|---|
| Physical RAM | Total shared CPU/GPU system capacity; not free capacity |
| Raw free | Includes speculative subset exactly once |
| Inactive/reclaimable | Used as a proxy component; reclaim can require writeback and is not guaranteed |
| Wired | Already occupied system RAM; not added as capacity or charged again on top of global occupancy |
| Compressed | Physical compressor storage is used RAM; logical compressed contents are not additional physical RAM or spare capacity |
| Swap | Not admission capacity; existing occupancy differs from current swap activity; monitor compares growth with request baseline |
| Package size | Quantized artifact estimate for weight cost, not measured loaded/peak inference footprint |
| KV/runtime allowance | Fixed2GiB estimate includes KV/load/scratch/runtime costs; analytical KV below is not added again |
| System reserve | Separate unchanged4GiB required headroom, not runtime overhead |
| Unified GPU memory | CPU/GPU mappings may share physical pages; do not charge the same weights twice as separate RAM and VRAM |

No additional definite duplicate in the current admission formula was found. It does not separately add the analytical KV estimate, wired memory, compressor logical size, swap or a second GPU copy of weights. Actual mmap residency, converted/copied buffers, batch scratch and load peaks may differ from the package estimate;2GiB is uncalibrated and is not a proven upper bound. No evidence supports reducing it or the4GiB reserve. A pressure-normal observation complements the proxy; it does not permit bypassing a byte-capacity denial. No app-allocation-limit API was substituted for system headroom.

## Candidate-model metadata and admission analysis

Official Ollama metadata was inspected without executing its displayed example commands. Only small public registry manifest JSON was retrieved; no weight/config/template/license layer blob was fetched, and no local pull/install operation occurred. Manifest package totals include model layers plus config/metadata, matching local tags-size accounting. Network transfer with caching/deduplication may differ. All four candidates use **GGUF Q4_K_M** mixed quantization, not uniformly four bits for every tensor.

| Candidate | Model-weight bytes | Complete package bytes | Installed now | Advertised context | FP16 KV at2048 /4096, analytical | Estimated required available, package+6GiB |
|---|---:|---:|---|---:|---:|---:|
| A qwen2.5-coder:1.5b | 986,048,576 | 986,062,089 (about986MB decimal) | No | 32,768 | 56 /112MiB | 7,428,513,033 bytes =6.9183GiB |
| B qwen2.5-coder:3b | 1,929,903,072 | 1,929,912,626 (about1.93GB decimal) | No | 32,768 | 72 /144MiB | 8,372,363,570 bytes =7.7974GiB |
| C qwen2.5-coder:7b | 4,683,074,048 | 4,683,087,561 | Yes | 32,768 | 112 /224MiB | 11,125,538,505 bytes =10.3615GiB |
| D qwen3:8b | 5,225,374,496 | 5,225,388,164 | Yes | 40,960 | 288 /576MiB | 11,667,839,108 bytes =10.8665GiB |

Sizes/format/quantization come from [official1.5b](https://ollama.com/library/qwen2.5-coder:1.5b), [official3b](https://ollama.com/library/qwen2.5-coder:3b), [official7b](https://ollama.com/library/qwen2.5-coder:7b), [official8b](https://ollama.com/library/qwen3:8b) and the registry manifests listed below. Exact totals are not rounded display-size arithmetic. GET-only local /api/tags currently lists just the7b/8b artifacts with the same package sizes/digests, /api/version reports0.33.0, and /api/ps is empty. This is momentary shared-service metadata, not proof of exclusive use or binary identity.

The KV estimates assume one sequence, equal128-dimensional K/V heads, two bytes each, and `2 × layers × KV-heads ×128 × tokens ×2` bytes. Official [1.5b GGUF metadata](https://ollama.com/library/qwen2.5-coder:1.5b/blobs/29d8c98fa6b0) reports28 layers,12 attention heads,2 KV heads,1536 embedding; [3b metadata](https://ollama.com/library/qwen2.5-coder:3b/blobs/4a188102020e) reports36 layers,16 heads,2 KV heads,2048 embedding. The7b/8b architecture inputs were observed in the preserved diagnosis. These are idealized KV calculations, not loaded-memory measurements; actual cache precision/layout and parallelism remain unverified.

Ollama's [structured-output interface](https://docs.ollama.com/capabilities/structured-outputs) accepts a JSON schema; pinned0.33.0 request/source contracts were inspected in the foundation work. Schema-constrained generation is therefore a plausible interface for these text models, **not verified schema conformance or correct proposals from any candidate**. Templates, tokenizer overhead,2048-budget fit, latency and quality require future conformance tests. Qwen3's thinking behavior must remain explicitly disabled/verified. Published larger-model benchmarks do not establish these candidates' results.

| Candidate | Gap from4.8035GiB minimum observation | Current feasibility | Possible lower-occupancy state |
|---|---:|---|---|
| 1.5b | 2.1149GiB more proxy capacity needed | Ineligible numerically; also absent and not adapter-allowed | Potential candidate after sufficient headroom plus separate download/adapter authorization; peak/quality unverified |
| 3b | 2.9939GiB | Ineligible numerically; also absent and not adapter-allowed | Potentially eligible numerically at7.7974GiB; no safe-run evidence |
| 7b | 5.5580GiB | Ineligible under unchanged policy | Potentially eligible at10.3615GiB; actual peak unknown |
| 8b | 6.0631GiB | Ineligible under unchanged policy | Potentially eligible at10.8665GiB; actual peak unknown |

**None is currently eligible.** Current pressure is already normal: “lower pressure” here means a genuinely lower background-memory workload yielding more corrected headroom, not merely changing a pressure label. All numerical requirements are below16GiB physical RAM, which alone proves no practical operating point. Effective daemon parallelism, independent peak footprint and service ownership remain insufficient evidence for certifying a run.

The adapter's two-name allowlist and4–6GiB package band remain unchanged. The1.5b/3b numerical entries are policy projections, not implemented admission support. Enabling either smaller model requires separately scoped exact-digest/size/capability changes and tests; no smaller model was silently added to Domain/provider discovery. Package sizes do not establish total inference cost.

Registry metadata provenance, captured20October2026; URLs have the form `https://registry.ollama.ai/v2/library/<family>/manifests/<tag>`:

| family/tag | Manifest SHA256 |
|---|---|
| qwen2.5-coder/1.5b | `d7372fd828518a4d38b1eb196c673c31a85f2ed302b3d1e406c4c2d1b64a0668` |
| qwen2.5-coder/3b | `f72c60cabf6237b07f6e632b2c48d533cef25eda2efbd34bed21c5e9c01e6225` |
| qwen2.5-coder/7b | `dae161e27b0e90dd1856c8bb3209201fd6736d8eb66298e75ed87571486f4364` |
| qwen3/8b | `500a1f067a9f782620b40bee6f7b0c89e17ae61f686b92c24933e4ca4b2b8b41` |

Tag mutability means these captured digests must be rechecked before a separately authorized download/use. Full manifests, source URLs and exact layer sizes are retained as ignored metadata evidence. No model layers were downloaded.

## Proposed safe runtime configuration — not applied

Prefer **1.5b as the first resource-conservative research candidate**, contingent on at least6.9183GiB corrected proxy, normal pressure, independently bounded peak overhead and separately authorized acquisition/adapter support. This is a memory-order recommendation, not a quality/performance winner.3b is the next candidate if quality evaluation later justifies its higher cost. No installed model is recommended for forced inference under current conditions.

Proposed settings: one loaded artifact and one request;2048 total context initially;256 output tokens; temperature0/seed42 where supported;120s request cap; no tools, cloud fallback, pulls or automatic retry/regeneration; keep_alive0 and an explicit owned-model unload/settlement procedure after evaluation. Preserve the4GiB headroom,2GiB allowance, residency gate and existing pressure/swap cancellation rules. Do not apply global/shared-daemon configuration changes.

Compatibility gates remain open: InferenceRequest supports2048 and256, but ProposalGenerator.makeRequest and the current evaluation convenience path default to4096/768. The closed schema/instructions must actually fit the smaller budget without deleting security requirements. Shared-server parallelism/ownership cannot be guaranteed by WF's own lease; global settings and low-level cache behavior must be verified in an authorized isolated/owned setup. An unload command must never evict another client's model; if ownership/settlement cannot be established, quarantine and stop. Empty /api/ps is not proof of memory release or stopped computation. None of these candidate settings was applied here.

## Controlled future benchmark — design only

1. Obtain separate authorization for artifact acquisition, adapter support and a bounded synthetic-only experiment. Recheck pinned metadata/version and collect an idle-window baseline; do not terminate/reconfigure unrelated applications or the shared daemon. Reject admission or foreign residency, observation failure, nonnormal pressure or inadequate headroom before any load.
2. Reuse the existing20-task corpus, SHA256 `d9c2365ebfa1f7dc5b2a72ef46dfaf5ecf869b5a6f43dbe5d76af6326ff04a5e`:10 normal,5 modification/conflict,5 adversarial. Preserve task/expected-outcome data. Freeze any common2048-compatible prompt/schema/settings change as a separately versioned benchmark manifest before running all candidates; do not tune individual prompts to favor one model. Zero productive operations or generated-code execution; only inert proposals and existing strict validation.
3. Evaluate one pinned model at a time, one request at a time. Bound each request120s and each run30minutes; mark remaining cases blocked if the budget is reached. Separate cold load, warm requests and explicitly owned unload observations. Never deliberately force an OOM or create a swap storm. Record failures, rejections, skipped/blocked cases and missing metrics rather than treating them as successes.
4. Record model-reported load_duration if present/credible, wall-clock total latency, valid JSON/schema/validator rates, correct file/operation/revision and expected outcomes. Check known synthetic content semantics with static oracles; no shell/compilation of generated code. Valid JSON with wrong file/operation is failure. Rejection cases' empty target policy tests application enforcement, not model understanding. Retain current acceptance gates, including16/20 correct outcomes and zero forbidden dispatch for hostile cases; do not select a model by speed alone.
5. **Time to first token is unavailable from the current nonstreaming adapter.** A future separately authorized bounded streaming/NDJSON observer or provider instrumentation is required. Record first nonempty content-chunk latency as an explicitly labeled observable TTFT proxy; do not substitute total latency or model load time, or claim knowledge of internal first-token timing from a buffered response. No streaming feature was implemented in this remediation.
6. Sample pressure, corrected page proxy, physical compressor use, swap occupancy and swap-in/out deltas alongside independently observed Ollama/runner footprint at baseline/load/prefill/generation/settlement. Distinguish process RSS from physical footprint and avoid summing shared CPU/GPU mappings twice. Measure peak and uncertainty; do not infer consumed RAM from a disk package or released RAM from HTTP completion.
7. Include controlled before-send, in-generation and shutdown cancellation trials under the same admission safeguards. Record HTTP cancellation latency separately from positive provider settlement/residency disappearance and observed footprint recovery. Keep keep_alive0 and, only with ownership, request unload after evaluation. If settlement/unload cannot be established, report uncertain and admit no subsequent heavy work.
8. Stop/cancel at the existing policy conditions: nonnormal pressure; corrected available proxy below4GiB; swap growth over256MiB above request baseline for two successive one-second samples; deadline; foreign residency; identity/transport/protocol failure or uncertain cleanup. Reconcile only explicitly and safely; no automatic repair loop, model substitution, threshold reduction, private-source disclosure, tools, model download or cloud inference during the benchmark. Fixture tests cover injected pressure paths; natural host measurements establish actual resource behavior.

No benchmark, model load, cancellation of real computation or unload was performed now. The next immediate experiment should be a **read-only lower-occupancy headroom survey**, not inference: determine whether the user-prepared workload can sustain at least6.9183GiB plus credible operational stability while leaving the policy unchanged. If it cannot, even1.5b remains blocked. Any download and live conformance run must be separately requested.

## Actual verification and commands

Full Xcode toolchain selected explicitly with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` and inherited SDKROOT removed. Swift6.4/Xcode27beta, SDK27.0, arm64/macOS26 deployment; Swift6 language mode and complete strict concurrency retained. No global developer-directory setting changed. These runs do not establish actual Swift6.2.3 compilation or macOS26 runtime compatibility.

| Check | Exit/result | Functions /expanded cases |
|---|---|---:|
| Memory + provider + proposal focused | 0, passed; no failures/skips | 38 /64 |
| Complete suite | 0, passed; no failures/skips | 232 /629 |
| Independent test-without-building replay | 0, passed; no failures/skips | 232 /629 |
| Debug build | 0, BUILD SUCCEEDED | — |
| Release build | 0, BUILD SUCCEEDED | — |
| Optimized Release test compilation | 0, TEST BUILD SUCCEEDED | Compilation only, not a Release test execution |
| Git diff/source preservation and staged review | Recorded before checkpoint | No provider threshold or dependency changes |

All test bundles' structured summaries report zero runtime warnings. Logs retain AppIntents metadata-extraction warnings and existing hosted-app linkd.autoShortcut connection messages; no Swift concurrency diagnostic remains. No test failed in this remediation run. The earlier five native HTTP probes are historical foundation evidence, not rerun or presented as new live-provider proof.

Exact command composition, run from `$REPO_ROOT`, with the explicit environment above:

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DERIVED -disableAutomaticPackageResolution -skipPackageUpdates -configuration CONFIG -resultBundlePath $REPO_ROOT/Evidence/Phase1B3A/MemoryRemediation/NAME.xcresult TAIL
```

| NAME | DERIVED | CONFIG | TAIL | Exit |
|---|---|---|---|---:|
| accepted-focused | DerivedData/MemoryRemediation-Accepted | Debug | test -only-testing:WorkspaceTests/MemoryAccountingTests -only-testing:WorkspaceTests/ProviderTests -only-testing:WorkspaceTests/ProviderBoundaryTests -only-testing:WorkspaceTests/ProposalGenerationTests | 0 |
| accepted-full | DerivedData/MemoryRemediation-Accepted | Debug | test | 0 |
| accepted-replay | DerivedData/MemoryRemediation-Accepted | Debug | test-without-building | 0 |
| accepted-debug | DerivedData/MemoryRemediation-Accepted | Debug | build | 0 |
| accepted-release | DerivedData/MemoryRemediation-Accepted | Release | build | 0 |
| accepted-optimized-release-tests | DerivedData/MemoryRemediation-Accepted-ReleaseTests | Release | build-for-testing ENABLE_TESTABILITY=YES | 0 |

For each test bundle `/usr/bin/xcrun xcresulttool get test-results summary --path <bundle>` and the corresponding `tests` subcommand extracted counts, exit0. Structured counts include parameterized arguments; console output lists test functions. Source hashes in command records bind the evidence to the reviewed code. The original diagnosis SHA256 remains `273d9f86b55bb71ccbbf4c0887b4ba8500a8157a9935510139f401c07568a840`.

Read-only observations used direct HOST_VM_INFO64 counters with checked Mach status/count, actual getpagesize and released host-port send rights; `/usr/bin/vm_stat`; `/usr/sbin/sysctl hw.memsize vm.swapusage kern.memorystatus_vm_pressure_level`; `/usr/bin/memory_pressure -Q`, each recorded system command exit0. Local HTTP was GET-only version/tags/ps with bounded JSON, no proxies and redirect rejection, status200. Public registry calls fetched only manifest JSON, each under64KiB. No app arguments, private environment, credentials or actual prompt/response was collected.

Ignored evidence directory: `Evidence/Phase1B3A/MemoryRemediation/`, containing command argv/exits/logs/source hashes/xcresult bundles, extracted test-counts.json, official-model-manifests.json, four manifest JSON documents and fresh-resource-observations.json. No build/evidence artifact or credential is part of the commit.

## Changed files, checkpoint and remaining gates

Reviewed checkpoint contents:

- AGENTS.md — current remediation scope and one-commit authorization.
- Packages/WesleyFlowCore/Sources/SystemOperations/SystemInferenceMemory.swift — corrected native arithmetic and internal checked helper.
- Packages/WesleyFlowCore/Tests/WorkspaceTests/ProviderTests.swift — new arithmetic/admission/coordinator regressions; earlier tests preserved.
- Docs/Phase1B/MODEL-PROVIDER.md — current accounting description and report link; limits unchanged.
- Docs/Phase1B/PHASE1B3A-MEMORY-DIAGNOSIS.md — preserved prior diagnosis, previously uncommitted.
- Docs/Phase1B/PHASE1B3A-MEMORY-REMEDIATION.md — this report.

The user authorized one local commit, `fix(models): correct macOS memory admission accounting`, only after passing verification and staged review. Its resulting hash and clean working-tree status are reported after creation; no push or remote creation. No unrelated changes existed at entry beyond the known diagnosis, and no old source/test functionality was removed.

**Recommendation:** accept the accounting remediation, preserve the existing policy, and keep live inference and Phase1B.4 on HOLD. No candidate passes current numerical headroom;1.5b is the smallest researched option for a separately authorized future experiment after resource/adapter/ownership gates close. Remaining unknowns include actual peak memory/load/latency/quality, strict schema behavior,2048 prompt fit, effective shared-daemon parallelism, GPU/cache overhead, positive cancellation settlement/unload, isolation/privacy and older-platform/toolchain compatibility. These are not resolved by629 fixture cases or a smaller disk artifact.
