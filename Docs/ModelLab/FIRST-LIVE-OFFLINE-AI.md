# First Live Offline AI

25 October 2026.

**LIVE OFFLINE GENERATION: PASSED**

**CUSTOM MODEL TRAINING: NOT STARTED**

The primary objective is achieved: Apple's on-device model generated an actual synthetic rewrite on this Mac. The optional follow-up proposal attempt was stopped by the preserved host-headroom guard; no proposal was returned or validated. No inference was retried.

## Device, SDK and provider availability

Actual device: **Apple M4, Mac16,12, arm64,17,179,869,184 bytes /16 GiB unified memory**. OS **macOS27.2, build26B5112a**. Explicit developer directory **/Applications/Xcode-beta.app/Contents/Developer**, Xcode27.0 build27A5237l, Apple Swift6.4 (swiftlang-6.4.0.30.4), macOS27.0 SDK. Global xcode-select still points to CommandLineTools; it was not changed. Diagnostic builds explicitly selected Xcode and target arm64 macOS26.0. This is verification on the installed27.2 host, not a macOS26 runtime certification.

Installed SDK's FoundationModels interface marks SystemLanguageModel available from macOS26.0. A real compiled availability probe returned:

- `SystemLanguageModel.default.availability = .available`.
- `isAvailable = true`.
- Current locale **en_IN**, supported; explicit en_IN and en_US checks also true.
-24 supported language/region entries, fully recorded in `availability.json`.
- No generation session or download request was created by this probe.

Apple Intelligence enablement/readiness preconditions were satisfied as reported by the public availability API; no private preference inspection or setting change was used. The exact model asset/version is system-managed and was not exposed as a hash-verified weight artifact. We did not enable Apple Intelligence, request/download assets, select Private Cloud Compute, or use a third-party provider.

Apple documents [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) as its on-device model and exposes readiness through availability. The installed interface and successful local execution, not documentation alone, establish this task's result.

## Actual generation — rewrite PASSED

Synthetic input (no personal/project content):

> um can you check whether the save button works and tell me what you find

Actual model output, unchanged:

> Verify the functionality of the save button and report findings.

This preserves the requested check/report intent without claiming to perform the check. It is model-generated output, not a hardcoded expected response or mock.

- Model: explicit **SystemLanguageModel.default**.
- One fresh session, empty tools list, default guardrails, temperature0.
- Maximum96 response tokens;2048 UTF-8 output-byte check.
- Swift request deadline20 seconds; child task cancellation and parent30-second hard deadline.
- Harness-reported generation wall time **2.212054967880249 seconds**; parent process envelope **2.673752208 seconds**.
- Diagnostic process **exit0**, stderr empty, completed and reaped.

Network control: generation client ran under the existing child profile `(deny network*)`; no model/network client, remote endpoint, provider fallback or tools were configured. Only the explicitly on-device Apple type was instantiated. The system XPC inference service is outside that client's sandbox, so this is **not a packet-capture claim that the whole Mac or every daemon had no network traffic**. The API's on-device execution contract plus client network denial is the basis for the offline result; no cloud model was selected. No system network settings were altered.

## Separate native resource assessment

The MLX6.81/6.26 GiB formulas were **not used** as Apple model admission requirements. Apple's model and its allocations are system-managed; a quantized-file weight estimate would be inappropriate here. The bounded native diagnostic separately required normal pressure, retained the existing **4 GiB host floor**, stopped on any observed swap growth or >512 MiB compression growth, and monitored approximately every0.25 seconds. Unknown observation/parent failure terminates the owned client through cleanup; no unrelated process or system inference service was terminated.

| Observation | Rewrite | Follow-up proposal |
|---|---:|---:|
| Available proxy before |6,607,224,832 bytes /6.153 GiB|5,506,646,016 bytes /5.128 GiB|
| Lowest sampled available |4,691,755,008 bytes /4.370 GiB|4,284,284,928 bytes /3.990 GiB|
| Available after client exit |4,892,065,792 bytes /4.556 GiB|4,296,130,560 bytes /4.001 GiB|
| Pressure before/during/after |Normal, code1|Normal, code1|
| Swap used before/after |0 /0 bytes|0 /0 bytes|
| Swapouts before/after |0 /0 pages|0 /0 pages|
| Compressor occupied before/after |3,006,857,216 /3,001,794,560 bytes|3,184,230,400 /3,345,350,656 bytes|

Available remains `(free including speculative + inactive) × page size`, a reclaimability proxy, not guaranteed capacity. Host-wide changes are not attributed solely to Apple inference; other apps were not interrupted. Sampling is reactive: the proposal briefly crossed the floor, which triggered termination. We do not claim a continuously enforced OS allocation cap or a measured native-model peak. The4 GiB threshold was not lowered to let a request finish.

## Follow-up structured proposal — BLOCKED

Only after rewrite success, one second fresh, isolated session attempted **V2 ml2a-003**: create the specified `isEven` Swift function for a synthetic in-memory project, using the frozen project/proposal/snapshot/path/absent-revision bindings. Input is saved as `proposal-input.json`. No real project content was sent. It used the same explicit on-device model, no tools,384-token limit,8192 output-byte check,20-second Swift deadline and30-second parent limit. Proposal data could only become stdout and validator input, never commands or filesystem effects.

At **2026-10-25T13:20:37.917829Z**, available proxy reached **4,284,284,928 bytes**, below4,294,967,296 by10,682,368 bytes. The parent stopped the owned diagnostic with SIGTERM. Parent duration **9.926229667 seconds**, child **exit−15**, process reaped. Pressure stayed normal and swap stayed zero. No complete output was returned, and there was **no retry, partial-output repair or synthetic substitution**.

**Proposal validation: NOT TESTED**, because no proposal text existed to validate. `proposal-validation.json` records that outcome. The prepared path would pass an untouched complete response through the unchanged, hash-verified production Swift CodingProposalCodec/ProposalHashing/CodingProposalValidator via the existing bridge and V2 scorer. Native validation would never grant execution authority. No proposal was executed or applied.

The client process is gone, but termination does not establish that Apple's system-managed model/service released all memory or acknowledged cancellation. No daemon was killed, model unloaded, or memory zeroization claimed. This cleanup uncertainty matters for a future cancellation-safe provider.

## Minimal future provider interface — documentation only

Success supports a small future replaceable on-device text-provider adapter with these operations:

- `availability()` returns the public readiness reason and supported language/capability information.
- `generate(requestID, authorizedSyntheticOrApprovedContext, instructions, outputLimit, deadline)` returns inert text, native provider identity/provenance, latency and typed failure; no tool/effect access.
- `cancel(requestID)` and `shutdown()` report request completion/cancellation uncertainty rather than claiming residency absent from client exit.

Keep native-session ownership, request correlation, one active request, guardrails, explicit user initiation and resource checks. The composition layer must obtain project context through existing authorized read-only boundaries. ProposalPreparationService remains responsible for unchanged strict decoding/validation and explicit user-review boundaries; a provider receives no shell, source-write or approval capability.

Current Domain `LocalModelProvider` describes this lifecycle, but `ModelDescriptor` currently requires a stored-file byte count and64-character model digest. **Do not invent those for Apple's opaque model or reuse MLX/Ollama admission.** A separately reviewed identity/capability adaptation is needed before production integration. No Domain, provider, UI or application wiring changed in this milestone. A complete production proposal/cancellation path is not yet verified by the successful rewrite.

## Commands, testing and evidence

Diagnostic source is preserved independently in:

- `ModelLab/NativeDiagnostics/AvailabilityProbe.swift`.
- `ModelLab/NativeDiagnostics/OnDeviceDiagnostic.swift`.

No new Xcode target, package dependency or installed app was introduced. Both compiled with **Swift6, complete strict concurrency, warnings as errors**, target arm64 macOS26.0; both compiler exits **0**, no compiler diagnostics.

Actual invocations (explicit DEVELOPER_DIR above for compilation; cwd repository):

| Command | Actual exit | Evidence under Evidence/FirstLiveOfflineAI |
|---|---:|---|
| `/usr/bin/xcrun --sdk macosx swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors -target arm64-apple-macos26.0 -module-cache-path /tmp/wesley-foundation-module-cache /tmp/WesleyFoundationAvailability.swift -o /tmp/WesleyFoundationAvailability` | 0 | `compile.json` |
| `/tmp/WesleyFoundationAvailability` | 0 | `availability.json` |
| `/usr/bin/xcrun --sdk macosx swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors -target arm64-apple-macos26.0 -module-cache-path /tmp/wesley-foundation-module-cache /tmp/WesleyNativeInference.swift -o /tmp/WesleyNativeInference` | 0 | `generation-compile.json` |
| `/usr/bin/python3 -m unittest discover -s $REPO_ROOT/ModelLab/NativeDiagnostics -p test_resource_boundaries.py -v` | 0 | `boundary-tests.json` |
| `/usr/bin/sandbox-exec -f $REPO_ROOT/ModelLab/config/offline-worker.sb /tmp/WesleyNativeInference` | 0 | `rewrite-run.json` |
| `/usr/bin/sandbox-exec -f $REPO_ROOT/ModelLab/config/offline-worker.sb /tmp/WesleyNativeInference --proposal` | -15 | `proposal-run.json` |

Native wrapping invocations were `/usr/bin/python3 /tmp/wf_apple_availability_record.py`, `/usr/bin/python3 /tmp/wf_first_native_run.py` and `/usr/bin/python3 /tmp/wf_native_proposal_run.py`, each wrapper exit0. Wrapper success means evidence was recorded; it does **not** convert the proposal's child exit−15 to generation success. Live stdout/stderr, complete resource samples and source copies are retained in the evidence directory. `environment.json` records exact device/toolchain commands/exits. `generation-compile.json`, `rewrite-run.json`, `proposal-run.json`, `proposal-validation.json` contain actual outcomes.

**Seven deterministic resource-boundary tests passed**, exit0, without invoking a model: normal observation, exact4 GiB boundary, one byte below floor, abnormal pressure, any swap growth, exact compression-growth boundary and excessive compression. They test the exact guard function used in the recorded live run, extracted without executing the wrapper. They are not evidence of model capability; the actual rewrite is. Timeout/cancellation implementation compiled, but no separate injected native timeout was run because the milestone stops after the bounded diagnostic.

The prior143 Model Lab tests remain historical baseline evidence; they were **not rerun or relabeled as native model tests**. Native app Debug/Release/full suite were not rerun: application/core/configuration remained byte-for-byte unchanged. Git diff whitespace check passed; nothing staged.

## Required next action and limits

**No hardware upgrade or model download is needed to establish the first offline response: it already worked on this16 GiB Mac.** For the larger proposal request, the next separately authorized step is to create more headroom by normally closing unused applications and then perform one bounded monitored native proposal test. No app was closed on the user's behalf. There is no defensible fixed extra-RAM amount guaranteeing success from this single host-wide trace;10 MiB crossing is a stop trigger, not the full model working-set estimate.

The cached Qwen model and V2 dataset are preserved. No MLX load, additional MLX preparation, training, cloud fallback, private data access, generated-code execution, UI/speech/clipboard change, installed-app replacement, commit or push occurred. A custom model has not been trained. Stop here; no production AI activation follows automatically.

## Git working-tree status

Branch `main`, HEAD `0a3e91c731a716945853a6b84bcfaaf6d9e672d3`. Only pre-existing file changed by this milestone is the narrow AGENTS.md authorization append. Added independent diagnostic sources,7 boundary tests and this report; generated evidence remains ignored. All pre-existing uncommitted app/voice/clipboard/Model Lab files retain their initial SHA256 values. `before.json` and `final-review.json` bind that preservation check. No files deleted, nothing staged, no commit/push.

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
