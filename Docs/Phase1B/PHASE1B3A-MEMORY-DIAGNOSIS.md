# Phase1B.3A — memory admission diagnosis

19 October2026. Reviewed checkpoint `b2f351cf1c5db772815fe10de236aae4394a1cb2`; working tree was clean at entry.

**Final outcome: B — MEMORY ACCOUNTING DEFECT CONFIRMED.** The native memory sampler double-counts speculative pages. This increases reported capacity. Removing the duplicate still leaves the measured host substantially below the unchanged admission requirements. Neither installed model has a demonstrated safe operating configuration under the measured workload. No threshold reduction, production correction, inference, model load/download, daemon change, application termination, commit or push was performed. Only this document and ignored diagnostic evidence were written.

## 1. Admission calculation and recorded rejection

`Packages/WesleyFlowCore/Sources/SystemOperations/SystemInferenceMemory.swift:17` currently computes:

```text
reportedAvailable = (Mach.free_count + Mach.inactive_count + Mach.speculative_count) × pageSize
```

`Sources/ModelProviders/OllamaProvider.swift:99–106` requires an empty resident-model list, a local completion-capable descriptor, normal pressure and:

```text
reportedAvailable >= storedModelBytes + 6,442,450,944
                                  = storedModelBytes + 2GiB estimate + 4GiB headroom
```

The2GiB is an estimate covering KV/load/scratch/runtime costs; the4GiB is reserved system headroom. Neither is an observed model allocation. Stored GGUF bytes are measured package sizes, not loaded footprint. Pressure is an independent normal/not-normal gate; swap is not added as admission capacity.

| Model | Package bytes | Package GiB | Estimated incremental bytes, package+2GiB | Total required available bytes, including4GiB headroom | Required GiB |
|---|---:|---:|---:|---:|---:|
| qwen2.5-coder:7b | 4,683,087,561 | 4.3615 | 6,830,571,209 | 11,125,538,505 | 10.3615 |
| qwen3:8b | 5,225,388,164 | 4.8665 | 7,372,871,812 | 11,667,839,108 | 10.8665 |

The earlier evaluation recorded a baseline of4,487,561,216 bytes,4.1794GiB, normal pressure, empty residency and `memoryAdmissionDenied` for both models. Their first admissions were checked sequentially; each model's remaining19 rows inherited its blocker. All40 rows were BLOCKED and chat request count was0. These were not40 separate model loads or failed model generations.

Precision limit: that4.1794GiB number is the harness baseline, not a raw-counter snapshot logged inside each individual admission decision. The provider uses a fresh sample after metadata checks. Historical per-gate counters/read statuses were not retained. Native observation failures also map to memoryAdmissionDenied, so the category alone does not uniquely distinguish a failed observation from a numeric/pressure denial. The recorded healthy baseline and large resource shortfall support insufficient headroom; the fresh measurements below independently reproduce the shortfall without invoking inference. Do not retroactively fabricate exact per-model samples or corrected historical values.

## 2. Confirmed accounting defect and reproduction

Apple's installed macOS27.0 SDK header, `usr/include/mach/vm_statistics.h:158–162`, explicitly states that speculative pages are already accounted for in free_count. The same contract appears in [Apple's XNU header](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h). The smallest correction is to remove the extra speculative term from the raw Mach calculation. It was **not implemented** in this diagnostic task.

A read-only direct `host_statistics64(HOST_VM_INFO64)` call at17:34:16UTC returned success, with16,384-byte pages:

| Counter/calculation | Result |
|---|---:|
| Raw Mach free, already including speculative | 9,078 pages |
| Inactive | 276,771 pages |
| Speculative subset | 1,144 pages |
| Current production formula | 4,702,093,312 bytes =4.3792GiB |
| Nonduplicated free+inactive proxy | 4,683,350,016 bytes =4.3617GiB |
| Duplicate amount | 18,743,296 bytes =17.875MiB |

Against the nonduplicated proxy, coder admission is short by5.9998GiB and Qwen3 by6.5048GiB. The error can create false admission close to a boundary; correcting it makes this calculation stricter. It cannot turn these rejections into admissions. Earlier fixture tests injected an already-calculated byte count, so they could not detect this native counter-composition defect. This finding supersedes the prior foundation review's absence-of-blocking-defect assessment for this specific accounting path; it should be corrected and regression-tested before accepting live admission behavior.

The direct probe read only the SDK-defined prefix fields, checked the Mach return code/count, used getpagesize and released its Mach host-port send right. No provider method or application executable was invoked. It reproduced the arithmetic against one internally consistent raw-counter sample. It was not a model benchmark.

## 3. Current host observations

Read-only observations at approximately17:33:43–17:35:00UTC,23:03–23:05IST. Tools run sequentially, so rows across tools are not an atomic global snapshot.

| Observation | Measured value |
|---|---|
| Physical RAM | 17,179,869,184 bytes,16GiB |
| OS kernel release | 27.2.0 |
| Pressure level | 1, normal, throughout sampled interval |
| memory_pressure -Q | 50% system-wide memory-free percentage; not an8GiB allocation promise |
| vm_stat Pages free, as displayed | 5,281 pages,0.0806GiB |
| Inactive | 250,123 pages,3.8166GiB |
| Speculative, as displayed separately | 2,596 pages,0.0396GiB |
| Active | 254,275 pages,3.8799GiB |
| Wired | 161,008 pages,2.4568GiB |
| Physical compressor storage | 336,587 pages,5.1359GiB |
| Uncompressed logical pages stored in compressor | 695,785 pages,10.6168GiB logical, not additional physical RAM |
| Swap used, initial system sample | 4,486.44MiB of5,120MiB, approximately4.3813GiB |
| top global summary | 15G used,126M unused; wired/compressor included in used |
| Ollama server | reachable; /api/version returned0.33.0 |
| Ollama residency | /api/ps returned an empty list |
| Ollama process | PID2117; ps RSS16,816KiB; top MEM18M |
| TCP11434 observation | only the Ollama listening process visible; no established client connection at that instant |

The raw Mach sample above is separate from vm_stat's formatted output; do not combine counters from different instants or assume every displayed utility field has the raw Mach field's formatting semantics. No units overflow or decimal-GB/GiB conversion defect was found in the production admission comparison: UInt64 bytes and binary constants are used. The confirmed duplicate is a field-semantics error.

Sanitized process observations retained PID/RSS/basename only, never arguments or environments. Highest sampled RSS included an already-running opencode process963,088KiB, Resolve786,432KiB, Codex Renderer738,224KiB and a browser renderer561,136KiB. The existing Wesley Flow process showed20,656KiB RSS. These identify competing resident workloads; RSS includes shared mappings and is not exclusive physical footprint, so do not sum these into a system-memory budget or attribute them to this task. The already-running applications were not launched, controlled or terminated. Top's Ollama MEM is an additional tool observation, not a loaded-model GPU allocation measurement.

Three samples spaced five seconds apart showed pressure1, unchanged swap occupancy4470.44MiB, and swap-out counter383,392 throughout. Swap-ins increased98,243→98,255. Thus there were12 observed swap-in events/pages in the counter and no new swap-outs in that ten-second interval. This does not establish long-term stability or predict behavior under inference. Compression and occupied swap show an existing busy-memory workload; they do not by themselves establish current critical pressure or an ongoing swap-out storm. No model-related memory was allocated by this task.

## 4. Ollama resource configuration

Used only GET `/api/version`, GET `/api/tags`, GET `/api/ps` and POST `/api/show` with the two installed model names. All returned HTTP200. No chat/generate/pull/unload/stop route was called. Both descriptors still match the checkpoint digests:

- qwen2.5-coder:7b: `dae161e27b0e90dd1856c8bb3209201fd6736d8eb66298e75ed87571486f4364`; GGUF Q4_K_M,7.6B; advertised context32,768;28 layers,28 attention heads,4 KV heads, embedding3,584.
- qwen3:8b: `500a1f067a9f782620b40bee6f7b0c89e17ae61f686b92c24933e4ca4b2b8b41`; GGUF Q4_K_M,8.2B; advertised context40,960;36 layers,32 attention heads,8 KV heads, key/value head lengths128.

Neither show result advertised a remote_host/remote_model setting; neither selected parameters list contained an explicit num_ctx override. These are service-reported metadata observations, not daemon attestation.

Read the exact [v0.33.0 envconfig source](https://raw.githubusercontent.com/ollama/ollama/v0.33.0/envconfig/config.go) and [scheduler source](https://raw.githubusercontent.com/ollama/ollama/v0.33.0/server/sched.go), with hashes retained in evidence:

| Setting | Supported source behavior | Effective running service |
|---|---|---|
| OLLAMA_NUM_PARALLEL | default1; scheduler uses at least1 | Not exposed by observed metadata APIs; unverified |
| OLLAMA_MAX_LOADED_MODELS | default0 automatic selection | Unverified; currently no loaded models |
| OLLAMA_CONTEXT_LENGTH | default0 sentinel; resource-dependent selection unless overridden | Unverified global value; WF explicitly requests4096 |
| OLLAMA_KEEP_ALIVE | default5minutes; per-request duration overrides | Unverified global value; WF requests0 |
| OLLAMA_KV_CACHE_TYPE / FLASH_ATTENTION | supported configuration controls | Effective mode/precision unverified |

Allowlisted read-only `launchctl getenv` queries for these six resource keys all returned empty values, exit0. That describes the current launch manager, not the environment inherited by a previously started daemon. No process environment dump, credentials, prompt logs or server configuration file was read. The selected APIs cannot establish the running daemon's exact global parallelism or queue ownership. No configuration issue is confirmed.

The pinned scheduler multiplies effective context by parallel count. WF's own process-wide lease admits one request at a time and rejects observed foreign residency; it cannot enforce server-wide serialization against other clients. Empty residency and one listener-only connection sample do not prove there were no earlier/queued/short-lived foreign requests. No excessive WF concurrency or residency conflict was observed in the rejected run.

Ollama documents per-request keep_alive=0 and explicit unloading support in its [lifecycle FAQ](https://docs.ollama.com/faq#how-do-i-keep-a-model-loaded-in-memory-or-make-it-unload-immediately). WF sends0 only with an admitted request. This task never requested unloading and did not stop another client's model. Cancellation closes owned HTTP; computation settlement and actual memory release remain unverified.

## 5. Resource estimates and candidate configurations

The current gate has no context-sensitive KV calculation: its2GiB reservation is constant for requests between2048 and4096 tokens. A shorter context does not change the current admission requirement. Context was4096 in the frozen evaluation, far below advertised maxima, and no context allocation occurred because admission preceded chat.

Illustrative KV-only arithmetic, **not measured runtime requirements**, assuming one sequence,128-dimensional keys/values, unquantized FP16 K and V and complete dense-layer caching:

```text
KV bytes = 2 × layers × KV-heads × head-dimension × tokens × 2bytes
```

| Candidate | KV at2048 | KV at4096 | Package+KV at2048, excluding other costs |
|---|---:|---:|---:|
| A: qwen2.5-coder:7b | 112MiB | 224MiB | about4.4708GiB |
| B: qwen3:8b | 288MiB | 576MiB | about5.1478GiB |

Qwen2's head dimension128 is inferred from3584/28; Qwen3 reports128 directly. Cache precision/layout, padding, batch/scratch, allocator/Metal buffers, mmap residency, copied/converted weights and load peaks have not been measured. These KV estimates belong inside a future calibrated incremental estimate; do not add them again on top of the existing2GiB reserve. On unified memory, CPU/GPU mappings may share physical storage: do not charge the same weights once as CPU RAM and again as a separate equal VRAM allocation. Shared mapping and runtime-copy behavior need observation; file size alone is neither a loaded footprint nor a proven upper bound.

There is no evidence establishing that2GiB is excessive or sufficient for actual peak overhead, or that4GiB headroom is unnecessary. The proxy includes inactive pages that may require writeback/reclaim and omits some other reclaimable memory. It is not a guaranteed amount immediately available to a new GPU workload. Pressure monitoring complements the proxy; it does not turn a normal-pressure sample into permission to consume the remaining memory.

A lightly loaded16GiB host could plausibly run one installed model at2048 context and one request, based on package/KV estimates, but that possibility is **not a safe-admission result**. Under the measured host condition neither is admissible using the unchanged policy. Prefer the coder candidate first in a later separately authorized experiment because its measured package and analytical KV costs are lower; this is a resource-order recommendation, not a quality ranking or successful benchmark.

Proposed future configuration, contingent on correcting the duplicate and establishing sufficient measured headroom: one explicitly selected/pinned model; one WF request; independently verified one-request service ownership/parallelism;2048 context;256 output tokens; zero tools; keep_alive0; existing120s cap,4GiB headroom and pressure/swap cancellation rules unchanged; synthetic data only. This requires a separately reviewed bounded prompt/schema small enough for2048, because the current makeRequest convenience path defaults to4096 and rejects oversized budgets. No request/prompt/corpus configuration was changed here. Do not silently alter the frozen20-task comparison or claim a2048 result from it.

Candidate C: a future approximately1–3B quantized coding model is more plausible for a constrained host, subject to actual package/runtime/context measurements and the same headroom policy. No specific smaller artifact was inspected, downloaded or benchmarked. The current Ollama adapter deliberately restricts names and package sizes to the two installed models, so a smaller model also needs separate scoped adapter/admission/test authorization. If the installed models remain inadmissible, use that path rather than forcing a load, relying on swap or changing the shared daemon.

Do not substitute an app allocation-limit API for global headroom; [Apple's os_proc_available_memory documentation](https://developer.apple.com/documentation/os/os_proc_available_memory) distinguishes changing app limits from physical device availability. No such limit was used as a replacement in this investigation.

## 6. Cause classification

| Candidate explanation | Finding |
|---|---|
| Insufficient headroom | Confirmed under the unchanged rule using fresh measurements; safe inference on this workload remains unproven |
| Excess reservation | Unverified; fixed2GiB is coarse and uncalibrated, with no evidence permitting reduction |
| Incorrect available calculation | CONFIRMED: duplicate speculative pages at SystemInferenceMemory.swift:17 |
| Existing pressure | Normal pressure readings; substantial compressed memory and occupied swap; no swap-outs during the ten-second trend |
| Residency conflict | Not observed: empty /api/ps; historical rejection category was memoryAdmissionDenied, not busy |
| Excessive context | Not the immediate gate cause; no context allocation occurred, and the current estimate is independent of context |
| Excessive concurrency | Not observed within WF; one lease, sequential first admissions; effective foreign-client/server parallelism unverified |
| Incorrect model estimate | Package bytes/units verified; relationship to runtime/load/GPU peak unmeasured |

## 7. Failure, cancellation and permission review

Read the provider lifecycle, memory-related fixtures, ProposalTaskExecutor and TaskCoordinator failure/recovery paths. Existing checkpoint evidence passed613 cases and replay; **no tests or builds were executed during this diagnosis**.

- Before admission, active request ownership and one WF lease are installed. On a thrown pre-send denial, generate's catch calls finish with sent=false, releases the lease, clears activeID and rethrows. work/monitor/chat creation is after the guard. A failed admission cannot return an InferenceResponse or PreparedProposal. The historical metadata run recorded0 chat requests and40 BLOCKED rows.
- Request IDs are consumed even when admission fails;64 unique IDs per provider lifetime bound history. There is no automatic retry/regeneration loop. The evaluation makes one actual admission attempt per model after the first resource denial, then records its other rows as blocked. Reuse/limit failures remain typed; a fresh explicitly owned provider is required after the lifetime cap.
- ProposalTaskExecutor stores a result only after prepare succeeds and its cancellation fence passes. Its thrown failure goes through TaskCoordinator.workerFailed at line376, cancellation/revocation and existing cleanup handling. Recovery clears pending approvals, begins a new policy session and never replays old queued approvals/work. No permission state is recreated by the provider.
- Existing injected tests assert typed memory denial and zero chat, foreign residency denial, pressure/sustained-swap cancellation, deadlines, caller cancellation, repeated shutdown, quarantine/reconcile and existing coordinator approval/intent/outcome. They do not provide a dedicated coordinator-plus-memory-denial terminal-state assertion or native raw-counter boundary oracle. Those gaps are proposed regressions below. No new claim of dynamically tested orphan prevention is made.
- Provider-level resource failure is typed as memoryAdmissionDenied. Coordinator currently maps generic adapter errors to execution failure rather than retaining a distinct memory-specific history reason. The app has no operational provider UI. Safe behavior is inspectable in code/evidence, but precise user-facing resource diagnostics need a bounded structured decision record before product use.

## 8. Smallest proposed corrections and regression gates

These are recommendations for a separate implementation authorization, not changes made here:

1. Remove `+ UInt64(stats.speculative_count)` from the raw Mach free+inactive calculation at SystemInferenceMemory.swift:17; update its comment and sampler documentation. Preserve every existing threshold and fail-closed observation/error behavior. This is a correctness fix that reduces claimed capacity.
2. Add a native-counter composition test using free=1000 including speculative=200, inactive=500, pageSize16384: expected24,576,000 bytes, not27,852,800. Include zero-speculative, maximum counter widths, page-size unit conversion and no independent addition of logical compressed/purgeable/CPU+GPU duplicates. A small pure arithmetic seam may be appropriate if native counters otherwise cannot be injected; do not redesign the provider.
3. Add threshold-boundary fixtures where the duplicate would change rejection into admission. Assert no chat, no success, active ownership/lease release, a subsequent explicitly requested admission after corrected sufficient input, exact-boundary acceptance only with normal pressure, and observation-error/non-normal-pressure rejection. Never load real models in these tests.
4. Add the existing-coordinator integration regression for memory-denied preparation: terminal failure/cleanup, no prepared result, no productive operation, no restored grant and no duplicate dispatch. Preserve cancellation/recovery regression coverage.
5. Retain a sanitized bounded per-decision record of raw counts/page size, pressure, model descriptor, estimated overhead/headroom, outcome and observation error category. No prompts, private paths or environment contents. Distinguish unavailable observation from numeric shortage for accurate diagnostics; retain uncertainty on provider cancellation. Calibrate a context/parallelism-aware estimate only after separately authorized measurements, without double counting cache inside the reserve.

No production patch or new regression test was written, so the confirmed defect remains in checkpoint code. Correct it before live-admission acceptance; do not reinterpret prior613 fixture passes as native accounting validation.

## 9. Evidence and source provenance

Ignored `Evidence/Phase1B3A/MemoryDiagnosis/` contains `observations.json`, `raw-mach-counter-check.json`, `ten-second-trend.json`, `sources-and-config-observations.json`, and the two version-pinned resource-source files. Measurements/metadata/source capture and the six allowlisted getenv queries completed successfully; all recorded system command exit codes were0. API failures/redirects would be recorded rather than followed. No raw process arguments, arbitrary environment, credential contents or model prompt/response was retained.

Actual diagnostic commands recorded with outputs/exits:

```sh
/usr/sbin/sysctl hw.memsize kern.osrelease vm.swapusage kern.memorystatus_vm_pressure_level
/usr/bin/vm_stat
/usr/bin/memory_pressure -Q
/usr/bin/top -l 1 -n 0
/bin/ps -A -o pid=,rss=,comm=
/usr/bin/top -l 1 -pid 2117 -stats pid,command,mem,rprvt,vsize
/usr/sbin/lsof -nP -iTCP:11434
/bin/launchctl getenv OLLAMA_NUM_PARALLEL
/bin/launchctl getenv OLLAMA_MAX_LOADED_MODELS
/bin/launchctl getenv OLLAMA_CONTEXT_LENGTH
/bin/launchctl getenv OLLAMA_KEEP_ALIVE
/bin/launchctl getenv OLLAMA_KV_CACHE_TYPE
/bin/launchctl getenv OLLAMA_FLASH_ATTENTION
```

Repeated vm_stat and swap/pressure queries supplied the three five-second-spaced trend samples. The direct Mach probe used standard-library ctypes, HOST_VM_INFO64=4, checked return0 and returned count40, and the installed SDK's field layout. HTTP metadata capture used bounded JSON reads, explicit127.0.0.1:11434, disabled proxies and rejected redirects. HTTPS source retrieval used only the exact official resource-source URLs above.

| Source | SHA256 |
|---|---|
| Installed SDK mach/vm_statistics.h | `b2b81f9e7efff57b648b4705a1ad08ffb55b99d0966b02c110f95fa454e175b7` |
| Ollama v0.33.0 envconfig/config.go | `2263acbd4a6f93607594abe5632e5dbc1e17d69a804d55aa7245613bca05b2a7` |
| Ollama v0.33.0 server/sched.go | `e4058db54c61b1af1a0c1799836731adbbf855d59c78757cce81d9d7dca3a07b` |

## 10. Recommendation and stop condition

**B — MEMORY ACCOUNTING DEFECT CONFIRMED.** Schedule the small speculative-counter correction and deterministic regressions separately. Keep the current resource thresholds. Current observations support rejection under those thresholds, with no evidence of a residency conflict or excessive WF inference concurrency. Unknown effective daemon settings, foreign clients, reclaim behavior and actual load/KV/GPU peaks prevent certifying either installed model safe on this workload. Recommend a smaller-model path if sufficient headroom cannot be established; no download or forced inference is authorized.

HEAD remains `b2f351cf1c5db772815fe10de236aae4394a1cb2`. Only this new diagnosis document is a Git change; production code, tests, settings, prior reports and thresholds are unchanged. Evidence remains ignored. No staging, commit or push. Stop after diagnosis; later-phase and live inference gates remain closed.
