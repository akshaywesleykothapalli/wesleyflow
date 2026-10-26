# Phase1B.3A — local provider and structured proposals

19 October 2026. **Implementation verified with fixtures; milestone PARTIALLY VERIFIED. Live model evaluation BLOCKED by memory admission. Hold the next milestone.** The original implementation run performed no commit, staging, push, remote creation or later-phase implementation. The authorized foundation checkpoint review below supersedes its historical Git-status statements; live acceptance remains blocked.

## Implementation and authority

Added a replaceable Sendable `LocalModelProvider` port, inert model/request/response/error/metrics/cancellation contracts, a populated ModelProviders target, loopback-only Ollama transport/provider, native memory observations, Workspace ProposalGenerator, and a single-use TaskExecution ProposalTaskExecutor. Existing application/core/test source files were preserved byte-for-byte against clean-start hashes. No legacy implementation was inspected or reused.

The production dependency arrows remain Domain-only for Workspace, ModelProviders, SystemOperations, TaskExecution, Persistence and CodingAgents. Domain has no vendor/framework imports or model-name allowlist. Ollama's adapter restricts discovery to the two approved models, validates artifact sizes and binds the selected descriptor/digest before and after generation. There are zero external package dependencies. The developer-only OllamaEvaluation executable is a concrete leaf composition root with a frozen synthetic corpus, not an application runtime or agent launcher. The Xcode changes link the new tests/products into the existing WorkspaceTests bundle. The app shell and its composition remain unchanged and expose no operational inference feature.

ProposalTaskExecutor accepts only inspection operations, binds task/operation/generation, rejects reuse and stale cancellation, and calls the existing preparation port. The real TaskCoordinator test proves approval precedes durable intent and outcome. A successful task means **proposal prepared**, with the original revision unchanged; it does not mean an edit was applied, code compiled or generated code verified. Prepared proposals are transient, one-time-take data, not persisted approvals. Existing persistence/CAS/recovery/cancellation behavior is unchanged and exercised by the full suite. No second orchestrator or new history schema was introduced. Interrupted generation is not automatically resumed or replayed.

## Structured output and limits

The provider sends one explicit system/user message pair and a closed JSON-schema `format`. The schema pins proposal/project/base identities, limits paths to injected snapshot entries, permits only `create`/`update` and requires absent/SHA256 revisions. The model has no tools. Every response passes the existing bounded strict CodingProposalCodec and CodingProposalValidator with a refreshed clock/deadline and unchanged policy/generation scope. Unsupported operations, malformed JSON, unknown proposal fields, wrong identities/revisions/paths and unauthorized targets are rejected. There is no repair loop or regeneration attempt.

Operational limits are one active WF inference lease across provider instances, 64 nonreusable request IDs per provider lifetime, request deadline at most120s, context2048–4096, output64–1024, request body16KiB, HTTP response128KiB, assistant content64KiB, and existing proposal file/content limits. Evaluation uses context4096/output768, temperature0, seed42, nonstreaming, `think=false`, `truncate=false`, `shift=false`, `keep_alive=0`. The conservative byte-based prompt/schema/output reserve rejects oversize inputs; it is not a model-specific tokenizer. Model-declared context limits are also enforced. Nonempty thinking/tool/image output, nonterminal/length endings, changed model identity and invalid token metrics are rejected. No runtime-specific SSE machinery or empty targets were added.

## Verified API sources and compatibility

Read the official [chat API](https://docs.ollama.com/api/chat), [tags API](https://docs.ollama.com/api/tags), [residency API](https://docs.ollama.com/api/ps), and [structured-output documentation](https://docs.ollama.com/capabilities/structured-outputs). Current documentation alone was not treated as exact-version evidence. Retrieved official version-tagged source:

| Source | SHA256 |
|---|---|
| [v0.33.0/api/types.go](https://raw.githubusercontent.com/ollama/ollama/v0.33.0/api/types.go) | `032fe8c044429afd42fd9f898c6bbd6efc5977ffeeec4dd3c5a04035e9c3d0b1` |
| [v0.33.0/server/routes.go](https://raw.githubusercontent.com/ollama/ollama/v0.33.0/server/routes.go) | `c2ebab461d0f258340152e9207d35a4d72113a57c46043121d5b6798d8c770fa` |

Source types/routes support chat messages, schema format, stream selection, context/output options, thinking, truncate/shift flags, keep_alive, metadata and residency routes. This is source-contract evidence, not observed successful inference. Raw retrieved source is retained in ignored `Evidence/Phase1B3A/API/`; source/binary hashes and sanitized observed metadata are in [provenance.json](Contracts/Ollama-0.33.0/provenance.json). The installed binary resolves to Homebrew Ollama0.33.0 and has SHA256 `e9104e224bd12435301f2d52d67762e608b79660e9439396d23e4178262d56ba`. A local service reporting that version is not proof that this binary owns its socket.

Observed actual local requests: GET `/api/version` returned `{"version":"0.33.0"}`; GET `/api/tags` matched both installed descriptors; POST `/api/show` returned local capabilities/model metadata; GET `/api/ps` was empty. Neither model was loaded by this task. Templates/modelfile contents, credential contents and unrestricted environment values are not in the tracked provenance.

| Contract/behavior | Status and evidence |
|---|---|
| Version, installed names/digests/sizes, show capabilities, empty residency | TESTED against installed service; sanitized provenance and final native evaluation |
| Request options/schema/nonstreaming encoding; response decoding and typed failures | TESTED with injected deterministic transports; supported by version-pinned source |
| Actual schema-constrained generation and metrics from both installed models | BLOCKED before chat by memory admission |
| Streaming API behavior | UNVERIFIED against service; source supports it, adapter intentionally implements nonstreaming only |
| Actual cancellation, model stop, keep_alive unload and released footprint | UNVERIFIED; no generation was admitted |

## Security and cancellation

Only canonical explicit `http://127.0.0.1:<1024...65535>` endpoints are accepted; default11434. Five closed routes exist: version/tags/ps/show/chat. No pull/delete/config/gateway/daemon-start route exists. Native ephemeral URLSession disables configured proxies, cookies, caches and credential storage, cancels authentication challenges, refuses redirects, bounds streamed-in response bytes, and enforces resource/deadline limits. Provider errors expose typed categories rather than raw request bodies. No cloud fallback, automatic application retry, subprocess, tool dispatcher, file effect or grant issuer is supplied.

Native loopback fixtures independently exercised success, rejected remote redirect, oversize, real resource timeout and connection drop. All five final probes passed. The drop probe observed **three local metadata GET attempts by CFNetwork**. The original fixture incorrectly required exactly one and failed; its count assertion was corrected for bounded idempotent GET retries while retaining one-request redirect checks and checking every observed path/auth header. No production transport change was needed. There is no application retry, but exactly-once network delivery is not claimed. Inference POST retry behavior is not live-verified.

An actor owns request state, owned HTTP task and resource monitor. Cancellation before send sends no chat. Caller cancellation, explicit cancellation, timeout, pressure and shutdown cancel owned HTTP. Any post-send failure quarantines the process-wide WF lease, even with empty sampled residency. A completed response with nonempty/unavailable residency also quarantines new work. Explicit reconciliation after the owned request settles can observe residencyAbsent; it does not establish global idleness or zero memory. Shutdown is idempotent and prevents new requests. No unrelated process or shared daemon is killed or reconfigured. Tests use controlled clocks/actor handshakes, not sleep-based concurrency ordering; the native HTTP timeout fixture deliberately stalls its synthetic server.

The lease coordinates this WF process only. The shared unauthenticated service may receive foreign requests between residency checks, change tags, retain prompts, or have network behavior WF cannot attest. Localhost plus metadata checks is not OS containment, authentication, no-egress proof, confirmed compute termination or memory zeroization. The provider cannot certify arbitrary input is synthetic; only the developer harness supplies frozen synthetic bytes, and real-source app disclosure remains unwired. Native injected transports must cooperate with cancellation; a noncooperating injected transport cannot be forcibly joined, and active ownership prevents replacement work. Provider uncertainty is in-memory, not a durable isolated-daemon lease across app restarts. Production isolation/authentication, real-source consent, durable unresolved-provider recovery and measured cleanup remain open gates.

## Memory admission and actual model comparison

Admission requires normal pressure, no resident models and conservative available pages at least **stored artifact bytes +2GiB KV/load/scratch estimate +4GiB headroom**. The estimate is deliberately conservative and not a measured footprint. Available pages are free+inactive+speculative; compressed/swap capacity is excluded. During admitted work, one-second samples cancel on nonnormal pressure, less than4GiB headroom, deadline, or two successive samples with swap growth greater than256MiB. The earlier measured aggregate8GiB acceptance limit is not established by this estimate or these page samples.

The final native run took place after builds finished. Physical RAM16GiB; baseline available **4,487,561,216 bytes (4.1794GiB)**, final **4,471,275,520 (4.1642GiB)**. Swap used **3,783,196,672 bytes (3.5234GiB)** before/after, delta0. All three recorded pressure-level observations were1 (normal), all residency observations were `{"models":[]}`, and all nonprivileged sampling commands exited0. The0.577s harness duration measured metadata/admission, **not generation latency**. Initial earlier observations are preserved separately under `initial-local-observation/` and are not substituted for the final run.

| Model | Pinned digest | Stored bytes | Required available bytes | Outcome |
|---|---|---:|---:|---|
| qwen3:8b | `500a1f067a9f782620b40bee6f7b0c89e17ae61f686b92c24933e4ca4b2b8b41` | 5,225,388,164 | 11,667,839,108 | 20 BLOCKED, zero evaluated |
| qwen2.5-coder:7b | `dae161e27b0e90dd1856c8bb3209201fd6736d8eb66298e75ed87571486f4364` | 4,683,087,561 | 11,125,538,505 | 20 BLOCKED, zero evaluated |

Each model's first admission was actually checked sequentially; subsequent rows inherited that model's resource blocker. Final provider route counts: version3, tags3, show2, ps2, **chat0**. Exit0 means the harness recorded a safe blocked run, not that inference passed. No admission setting was relaxed. Existing swap is reported, not attributed to a model this task did not load. This does not prove the models can never fit a16GiB Mac; it establishes rejection under this host workload and the chosen policy.

The frozen corpus contains10 normal,5 modification/conflict and5 adversarial tasks, SHA256 `d9c2365ebfa1f7dc5b2a72ef46dfaf5ecf869b5a6f43dbe5d76af6326ff04a5e`. Both models use identical tasks, schema construction, prompt, seed and generation settings, with model/request IDs as the necessary differences. Each normal case includes a decoy path so wrong-file choices can fail independently of syntactic validity. The evaluator separates JSON parsing, strict schema/scope, validation, expected file/operation/revision and expected outcomes. Rejection cases intentionally have no editable targets: that measures application policy enforcement, not proof the model understood the attack. It does not compile generated code or prove semantic implementation correctness.

**No winner selected.** Valid JSON rate, schema/validation rates, file/operation/revision accuracy, unauthorized-operation rejection rate, hallucinated-file rate, latency, load time, loaded footprint, peak inference pressure, tokens/s, live cancellation response and unload behavior are all **unmeasured**, not zero or100%. There are no actual generated model responses to present. Forty rows in `results.json` are BLOCKED. The prior cold/warm/repeated load-unload/cancellation/30-minute acceptance workload remains open.

## Automated verification

Environment: M4/16GiB, macOS27.2, Xcode27.0 beta27A5237l at `/Applications/Xcode-beta.app/Contents/Developer`, Swift6.4, macOS27.0 SDK. Swift6 language mode, complete strict concurrency, arm64 and deployment26.0 were verified. Global Command Line Tools selection was not changed; inherited SDKROOT was removed for every Xcode/Swift build. These results do not establish macOS26 runtime or Swift6.2.3 compiler compatibility.

| Final check | Result | Functions / expanded cases |
|---|---|---:|
| Workspace + proposal/provider focused | exit0; zero failures/skips | 110 /262 |
| Complete suite | exit0; zero failures/skips | 223 /613 |
| Independent test-without-building replay | exit0; zero failures/skips | 223 /613 |
| Debug build | exit0 | BUILD SUCCEEDED |
| Release build | exit0 | BUILD SUCCEEDED |
| Optimized Release build-for-testing, ENABLE_TESTABILITY=YES | exit0 | TEST BUILD SUCCEEDED; compilation, not a Release test execution |
| Native developer evaluation executable build | exit0; source/binary hashes recorded | Built |
| Five native loopback HTTP probes | exit0 | 5 /5 |
| Real local metadata/admission evaluation | exit0; no chat sent | 0 evaluated /40 BLOCKED |
| Dependencies/concurrency/settings/preservation/Git diff checks | exit0 | no external dependencies; prior source/tests unchanged |

The new file contributes29 test functions/48 expanded cases above the previously verified565 cases. The full suite includes existing proposal validation, descriptor filesystem security, Phase1A cancellation/recovery/revocation/shutdown/no-duplicate regressions and disabled OpenCode fixtures. New coverage includes request encoding/no tools, endpoint/redirect/status/version/model/metric bounds, model replacement after response, response limits, memory/foreign-residency denial, serialized providers, caller and explicit cancellation, quarantine/reconcile/another request, timeout, sustained swap growth, pressure, repeated shutdown, strict proposal rejection, real coordinator approval/intent/outcome, stale-generation fencing and productive-operation refusal. These are application/fixture guarantees, not proof that an arbitrary local daemon is contained.

All final bundles' source hashes match current app/core/test/tool sources. `xcresulttool` extraction counts parameterized arguments as expanded cases; Xcode's console reports functions. Final bundles show zero runtime warnings in their structured summaries. Build logs contain AppIntents metadata-extraction warnings because there is no AppIntents dependency; hosted app test logs also contain the existing linkd.autoShortcut connection message. No Swift concurrency diagnostic remains.

Development failures are retained: initial compiler exit65 from accessing mutable `vm_kernel_page_size` was fixed by native `getpagesize()`; test compile exit65 from continuation inference/nested Testing macros was fixed with explicit continuation types and separated assertions. An additional optimized test compilation exited65 because the invocation omitted ENABLE_TESTABILITY=YES, leaving Domain built without testing support; the corrected invocation passed without changing source or weakening tests. Earlier successful runs predate final regression additions; only the frozen runs above are accepted final proof. The original native drop fixture assertion failure is documented above, not hidden by its shell wrapper's later successful command.

## Commands and evidence

All paths below are relative to `$REPO_ROOT`. Full argv arrays, exit codes, timestamps, source hashes and logs are in ignored `Evidence/Phase1B3A/`; tests also have xcresult bundles. Use the explicit environment:

```sh
unset SDKROOT
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

The following common invocation plus each table row is the exact Xcode command composition used (replace NAME, DERIVED, CONFIG and TAIL with that row):

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DERIVED -disableAutomaticPackageResolution -skipPackageUpdates -configuration CONFIG -resultBundlePath $REPO_ROOT/Evidence/Phase1B3A/NAME.xcresult TAIL
```

| NAME | DERIVED | CONFIG | TAIL | Exit |
|---|---|---|---|---:|
| accepted-frozen-focused | DerivedData/Phase1B3A-Accepted | Debug | test -only-testing:WorkspaceTests | 0 |
| accepted-frozen-full | DerivedData/Phase1B3A-Accepted | Debug | test | 0 |
| accepted-frozen-replay | DerivedData/Phase1B3A-Accepted | Debug | test-without-building | 0 |
| accepted-frozen-debug | DerivedData/Phase1B3A-Accepted | Debug | build | 0 |
| accepted-frozen-release | DerivedData/Phase1B3A-Accepted | Release | build | 0 |
| accepted-frozen-release-tests | DerivedData/Phase1B3A-Accepted-ReleaseTests | Release | build-for-testing | 65 |
| accepted-optimized-release-tests | DerivedData/Phase1B3A-Accepted-ReleaseTests | Release | build-for-testing ENABLE_TESTABILITY=YES | 0 |

Other actual final commands (each exit0; evaluation completion remains BLOCKED):

```sh
/usr/bin/xcrun swift build --package-path Packages/WesleyFlowCore --product OllamaEvaluation
python3 Scripts/Phase1B3A/verify-native-transport.py Packages/WesleyFlowCore/.build/debug/OllamaEvaluation Evidence/Phase1B3A
python3 Scripts/Phase1B3A/run-local-evaluation.py
/usr/bin/xcrun swift --version
/usr/bin/xcodebuild -version
/usr/bin/xcrun --sdk macosx --show-sdk-version
/usr/bin/xcrun swift package --package-path Packages/WesleyFlowCore dump-package
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -configuration Debug -showBuildSettings -json
git branch --show-current
git rev-parse HEAD
git diff --check
git diff --cached --name-only
git ls-files --others --exclude-standard
git status --short
```

The native probe script invokes the executable's `--probe-transport http://127.0.0.1:<ephemeral-fixture-port>` once per case; exact ports/argv/status are in `native-transport-tests.json`. The evaluation script invokes the executable with the absolute `Evidence/Phase1B3A/local-evaluation` output directory. It samples `/usr/bin/memory_pressure -Q`, `/usr/sbin/sysctl vm.swapusage`, `/usr/sbin/sysctl -n kern.memorystatus_vm_pressure_level`, `/usr/bin/vm_stat` and bounded no-proxy curl GET `/api/ps` before/during/after. Every sample records its argv/output/exit. It can interrupt only its owned evaluation process, never the daemon. Raw source capture used HTTPS GET for the two exact version URLs above; metadata used only the four enumerated local routes. No credentials were read.

For each frozen test bundle, extraction ran `/usr/bin/xcrun xcresulttool get test-results summary --path <absolute-bundle>` and the corresponding `tests` subcommand, each exit0. Key evidence: `test-results.json`, `accepted-frozen-*.json/.log/.xcresult`, `accepted-optimized-release-tests.*`, `accepted-native-evaluation-build.*`, `accepted-local-commands.json`, `native-transport-tests.json`, `local-evaluation-command.json`, `local-evaluation/{summary,results}.json`, `environment-commands.json`, `selected-settings.json`, `scope-review.json`, and `API/`. Evidence/build outputs remain ignored and unstaged.

## Files and Git status

Started clean on `main` at `8d77088a2bf1e043ad752213d76bd9834b8224ba`. HEAD/branch remain unchanged. Six tracked files modified:

- AGENTS.md — current authorization scope.
- Docs/Phase1B/ARCHITECTURE.md — current implementation/module status.
- Docs/Phase1B/MODEL-PROVIDER.md — provider limits and unverified live gates.
- Docs/Phase1B/SECURITY-BOUNDARIES.md — shared-service/transport limits.
- Packages/WesleyFlowCore/Package.swift — populated provider and developer harness/test dependencies.
- WesleyFlow.xcodeproj/project.pbxproj — new tests and their product links.

Thirteen new files:

- Docs/Phase1B/PHASE1B3A-COMPLETION.md
- Docs/Phase1B/Contracts/Ollama-0.33.0/provenance.json
- Packages/WesleyFlowCore/Sources/Domain/LocalInference.swift
- Packages/WesleyFlowCore/Sources/ModelProviders/OllamaTransport.swift
- Packages/WesleyFlowCore/Sources/ModelProviders/OllamaProvider.swift
- Packages/WesleyFlowCore/Sources/SystemOperations/SystemInferenceMemory.swift
- Packages/WesleyFlowCore/Sources/Workspace/ProposalGenerator.swift
- Packages/WesleyFlowCore/Sources/TaskExecution/ProposalTaskExecutor.swift
- Packages/WesleyFlowCore/Tests/WorkspaceTests/ProviderTests.swift
- Packages/WesleyFlowCore/Tools/OllamaEvaluation/EvaluationMain.swift
- Packages/WesleyFlowCore/Tools/OllamaEvaluation/Corpus.json
- Scripts/Phase1B3A/verify-native-transport.py
- Scripts/Phase1B3A/run-local-evaluation.py

Nineteen intended changed/new files; index empty, working tree intentionally dirty. No previous source/test file changed or was removed. New files were manually reviewed and scanned for private-key/API-key patterns, with no matches; this is not a universal secret detector. No generated build/evidence artifact is an untracked candidate for commit. No unrelated project was modified, and no remote operation or commit was made. Temporary verification drafts were confined to the task temporary directory.

## Requirement disposition and readiness

| Area | Status |
|---|---|
| Clean start, architecture inspection, preservation, scoped implementation | TESTED |
| Replaceable contract, bounded loopback transport, strict proposals, coordinator integration | TESTED with fixtures/native HTTP probes; no productive feature activated |
| Installed API metadata/provenance | TESTED |
| Exact-version chat/schema/options behavior on loaded models | PARTIALLY VERIFIED by source/fixtures; live behavior BLOCKED |
| Conservative memory admission/one WF lease/pressure/timeout policy | TESTED in deterministic fixtures and actual denied-admission observations |
| Frozen20-task corpus and reproducible two-model harness | TESTED preparation;40 live outcomes BLOCKED |
| Quality/performance comparison, load/peak/unload and compute cancellation | BLOCKED or UNVERIFIED; no model selected |
| Complete suite, replay, Debug/Release, optimized QA/concurrency/dependencies | TESTED |
| Real-source disclosure, productive broker, isolated/authenticated provider, model/OS containment | UNVERIFIED and not enabled in this scope |
| Actual macOS26 runtime and Swift6.2.3 compiler compatibility | UNVERIFIED |

**Readiness: HOLD.** The native foundation and deterministic boundaries pass verification, but do not claim Phase1B.3A fully accepted or advance to1B.4. A future explicitly scoped run needs sufficient available headroom without bypassing admission or disturbing unrelated applications/services, followed by the same frozen corpus on both models, real schema/error/stream observations as applicable, cancellation/settlement/unload measurements and cold/warm memory/load/latency acceptance. Do not select a winner, enable real-source inference or infer productive/OS containment from fixtures. Stop at this report.

## Engineering review and foundation checkpoint

19 October 2026. **Approve the software foundation checkpoint only. No blocking P0/P1 defect was identified in the reviewed scope, and no application source/test correction was needed.** The checkpoint is not approval of live provider functionality or advancement to the next milestone. Safety thresholds and all core/test/tool sources are unchanged from the frozen613-case implementation. Only this review record and the current AGENTS authorization were added during review.

Reviewed all19 intended changed/new files, the complete tracked diff and new modules/tests/scripts/corpus/provenance, the architecture/provider/security documents, prior execution records and their current-source hashes. Request serialization has fixed roles/schema/options, bounded bodies and no tools; response decoding enforces model/terminal/role/content/metric bounds before the existing strict proposal decoder/validator. Canonical loopback endpoint construction and native redirect refusal have code and synthetic HTTP evidence. Native resource/deadline limits, actor-owned cancellation and quarantine preserve uncertainty rather than claiming compute termination. Model identity is selected explicitly, checked before/after generation and remains a metadata observation rather than attestation.

Task/operation/generation binding, single use and post-await cancellation checks preserve existing coordinator ownership. Validated proposals remain data, without productive-operation authority, file handles or execution ports. The existing permission broker, lifecycle, persistence and app composition are unchanged. Neither productive filesystem effects nor an actual coding-agent/tool engine is enabled. Memory observation errors, unknown pressure, insufficient available pages and foreign residency prevent admission; pressure/timeout/cancellation paths stop owned HTTP and quarantine uncertainty. No thresholds were altered and no model inference or local-service evaluation was started in this review.

Reverification: complete automated suite **613 expanded cases /223 functions**, exit0; independent test-without-building replay **613 /223**, exit0; both zero failures/skips. Five synthetic native HTTP probes passed again, exit0. The probe executable's SHA256 matches the recorded developer build, and its three-argument --probe-transport branch contacts only the synthetic loopback fixture server. The model-evaluation script was reviewed but not run. Existing Debug/Release and optimized Release test-compilation records each have exit0 and source hashes matching the reviewed code/configuration, so those builds were validated from unchanged-source evidence rather than rerun. The pre-existing AppIntents/linkd log messages remain; no new Swift concurrency diagnostic was observed.

Exact new Xcode commands use the common command above with NAME `accepted-checkpoint-full`, DERIVED `DerivedData/Phase1B3A-Accepted`, CONFIG Debug, TAIL `test`, then NAME `accepted-checkpoint-replay` with TAIL `test-without-building`. Both exit0. Native probes ran:

```sh
python3 Scripts/Phase1B3A/verify-native-transport.py Packages/WesleyFlowCore/.build/debug/OllamaEvaluation $REPO_ROOT/Evidence/Phase1B3A/Checkpoint
```

Checkpoint logs/source hashes and xcresult bundles are `Evidence/Phase1B3A/accepted-checkpoint-{full,replay}.*`; extracted counts and native command/probe records are under `Evidence/Phase1B3A/Checkpoint/`. Raw evidence/build products remain ignored and are not checkpoint contents. Every staged blob is checked against the reviewed working file before the local commit. The checkpoint contains exactly the19 files listed in this report; no credentials, generated artifacts, external dependencies, unrelated changes or previous source removals were identified. The authorized message is `feat(models): add guarded local Ollama provider foundation`, with parent `8d77088a2bf1e043ad752213d76bd9834b8224ba`; the resulting commit hash and final working-tree status are reported after commit. No push or remote creation is authorized or performed.

Remaining live-inference blockers are unchanged: both installed models were denied admission under the recorded workload; all40 model/task rows remain BLOCKED; generation quality/schema behavior, latency/load/peak footprint, cancellation settlement and unload are unverified. The shared daemon is unauthenticated/unattested and not OS-contained by this client. Streaming and actual macOS26/Swift6.2.3 compatibility remain open. These prevent live/provider milestone acceptance but do not prevent preserving the reviewed foundation. **No model selected; next milestone remains HOLD.**
