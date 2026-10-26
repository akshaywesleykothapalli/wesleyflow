# Phase 1D — Offline AI Rewrite

25 October 2026. **Opt-in preview integration implemented; native calls and deterministic fallback verified. Useful accepted rewriting and physical end-to-end acceptance remain PARTIAL / UNVERIFIED.** Automatic cross-app AI insertion is **DISABLED**. Do not treat unit tests, unchanged responses, or the earlier2.21-second diagnostic as proof that this feature consistently improves prose.

## 1. What is available in Wesley Flow

Smart Formatting now contains **Offline AI Rewriting**, default **OFF**, using a native persisted switch. Enabling it exposes **Preview latest dictation**, cancellation, the resulting text and **Copy reviewed preview**. Only a reliable final utterance from the current app session can be previewed. There is no history-browsing inference or automatic request on preference changes.

Current rollout is **explicit preview only**:

1. Existing hold-to-talk, final speech recognition and deterministic formatting run normally.
2. Existing target-bound deterministic insertion and single history write remain unchanged.
3. After completion, the opted-in user can explicitly preview an Apple on-device rewrite.
4. The result never automatically inserts, changes the original destination, presses Return, opens an app or submits a task. Explicit copy uses the existing lease-aware clipboard pathway and is blocked by a pending lease or active dictation.

This deliberately **does not enable the requested future rewrite-before-cross-app-insertion chain**. The request explicitly keeps automatic AI insertion disabled until physical verification. No hidden automatic mode or bypass flag was added. Normal dictation when OFF makes no model request, readiness query or model-resource polling call.

## 2. Provider and architectural boundaries

New pure Sendable request/outcome/protection contracts are in `Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift`. `AppleTranscriptRewriter` and the real `AppleRewriteGenerator` are in `Sources/ModelProviders/AppleTranscriptRewriter.swift`. ModelProviders continues depending only on Domain; resource source and monotonic clock are injected by AppComposition. Package.swift, project targets and external dependencies are unchanged. No Ollama file digest/weight estimate is fabricated for Apple's system-managed model; the existing coding-prompt rewriter remains separate and gated.

The generator explicitly creates `LanguageModelSession(model:SystemLanguageModel.default, tools:[], ...)` with default guardrails and a fresh session for each independent rewrite. It checks readiness and supported locale before generation. No Private Cloud Compute, HTTP provider, tools, file executor, model acquisition, fallback server or permission authority is exposed. Apple documents the selected [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) as on-device; the current installed SDK and real generation path were used.

Bounds and ownership:

- Input ≤2048 UTF-8 bytes; protected prompt ≤8192 bytes and32 merged spans; output ≤256 generated tokens /8192 bytes before restoration and4096 after restoration.
- Initial product language scope is **English**. Other requested locales and unprotected mixed-script prose retain deterministic text. Protected Unicode vocabulary can round-trip exactly. This is a feature limit, not a claim Apple's framework supports only English.
- Eight-second generation deadline after admission,250ms monitoring, Task cancellation and one composition-owned provider slot. No unbounded queue or implicit retry.
- Deadline, resource or cancellation fallback can return while a noncooperative generator settles. The slot remains owned until it finishes; repeated clicks cannot create replacement native sessions. Internal callback epochs reject stale completions.
- Delivery is claimed only after suspension points. A deterministic regression suspends the final clock lookup and proves a resource fallback cannot be overwritten by a late successful result.
- Framework context/guardrail/runtime-generation failures are caught and retain the fallback. Post-generation framework errors currently collapse to InvalidOutput rather than a detailed public error taxonomy; real guardrail/context fault injection was not performed.

Cancellation is cooperative with FoundationModels. Client completion does not prove the system service released all model memory; no daemon is killed or OS memory zeroized. The eight-second fallback is not an OS process-containment claim. No production coding execution was activated.

## 3. Protection and fidelity contract

Formatting runs first; the provider receives that deterministic text as its guaranteed fallback. Protected spans cover quoted/backtick code, command lines, paths (including bare/hidden filenames), URLs/email addresses, numbers/units, recognizable identifiers/names, shortcuts, vocabulary and phrase-expansion output. Literal ranges are merged in UTF-16-safe order and replaced by request-specific markers. Given the same input/request ID, masking/restoration is deterministic and reversible; runtime request IDs are fresh UUIDs, not authorization capabilities.

Acceptance requires every marker exactly once, unchanged and in original order; restoration is byte-exact. Adjacent boundaries are checked so signs/command suffixes cannot attach outside a protected marker. The remaining lexical ledger allows only hesitation fillers to disappear and preserves content-word order. A restrictive punctuation policy preserves added/removed operators, Unicode minus, currency and emoji rather than ignoring them. Empty/whitespace-only or oversized accepted output is rejected. Final restored text can never be an empty successful rewrite.

This is deliberately conservative: punctuation, capitalization and hesitation cleanup can pass; many otherwise reasonable grammar/paraphrase/reordering suggestions will fall back. **It is not a proof of semantic equivalence**: punctuation and capitalization can still affect meaning, and generic prose identifiers cannot always be recognized without vocabulary/code markup. Human review is required, and automatic AI insertion remains off. No claim of full arbitrary sentence restructuring or guaranteed meaning preservation is made.

Typed outcomes: `rewritten`, `unchanged`, `modelUnavailable`, `resourceBlocked`, `cancelled`, `invalidOutput`, `timedOut`. On any rejected result the text equals the deterministic input; the UI states why it was retained. An unchanged response is described factually, not as proof that the input was already suitable.

## 4. Actual native evaluation and quality

The diagnostic links the **actual production Domain/ModelProviders/SystemOperations frameworks**. A recording wrapper delegates directly to the real Apple generator and captures only synthetic masked responses. It does not substitute a mock. Each session used en-IN and had no tools. The client ran under the existing network-denial profile; the selected Apple API is explicitly on-device. This does not claim that every OS daemon's network traffic was captured or disabled.

Five bounded production-provider attempts across two prompt versions produced **four complete native outputs**. Three were accepted **unchanged**, one was rejected, and one returned ResourceBlocked before any complete output. **Accepted improved rewrites:0.** Do not aggregate these different prompt versions as a general model-quality benchmark.

| Version / case | Actual outcome | Provider elapsed | Host available proxy before → after |
|---|---|---:|---:|
| Initial prompt / casual | invalidOutput | 4664 ms | 6.267 → 4.650 GiB |
| Initial prompt / protected | unchanged | 3131 ms | 4.650 → 4.612 GiB |
| Initial prompt / contact | unchanged | 2290 ms | 4.612 → 4.584 GiB |
| Revised prompt / casual | unchanged | 2484 ms | 5.307 → 4.439 GiB |
| Revised prompt / protected | resourceBlocked | 1794 ms | 4.439 → 3.809 GiB |

All recorded before/after pressure observations were normal and swap usage remained0. The final resource-blocked request ended with **4,090,413,056 bytes /3.810 GiB** available. The guard returned deterministic text; no subsequent live attempt was made. The exact instantaneous failing sample is not stored by the production provider; the table is before/after host-wide observation, not an attributable model peak.

Actual samples:

- Casual input: `um please check the save button and tell me what you find`.
- Initial generated output echoed a large part of the instructions and then the input. The fidelity gate rejected it; accepted text stayed exactly the deterministic input. Full synthetic response is retained in `live.stdout.jsonl`.
- The prompt was shortened without weakening the gate. The revised casual response was exactly `um please check the save button and tell me what you find`, accepted **unchanged** in **2484ms**. It demonstrated the live path, **not a useful edit**.
- Protected input: `please keep saveButton in /tmp/Example.swift and use 12 kg for the test`. The initial model copied all three opaque markers correctly; restoration matched the original identifier, path and measurement exactly. Outcome unchanged,3131ms.
- Contact input: `please send the notes to ada@example.test and check https://example.test now`. Both opaque spans restored exactly; outcome unchanged,2290ms. No email or URL operation occurred.

Initial completed-response invalid rate was1/3 for that tiny prompt experiment. The final comparison had one unchanged completion and one resource failure; the planned third case was skipped. Completed-output latency ranged **2290–4664ms**; resource fallback took **1794ms**. The previous2.21-second native diagnostic is historical, not a latency guarantee. Overall meaning/formatting improvements have **not** been demonstrated by these samples.

After the last model request, further changes only strengthened deterministic protection and corrected UI wording. Four frozen native outputs were replayed against the final gate: three unchanged outputs accepted, instruction echo rejected. A repeated-filler property was also checked without inference. No fresh native request was used to bypass the resource block.

## 5. Resource policy and limits

The native provider separately uses normal pressure, the preserved **4 GiB host floor**, and no swap increase from its request baseline. Unknown memory observations fail closed. It checks admission, periodically while generating, and again before acceptance. SystemInferenceMemory's corrected free-plus-inactive proxy is reused; speculative memory is not added twice and compressed/swap bytes are not capacity.

No MLX6.81/6.26 GiB formula, fake native weight size or linear runtime discount was reused. Host memory is a proxy, not a native allocation limit. The existing memory-source contract does not provide per-model footprint or compression-growth metrics; these are **not measured/enforced separately by this provider**. No reserve constant was reduced. The live cancellation/resource result establishes fallback, not verified OS model unload. This remains a reason to keep automatic insertion gated and to require further physical/resource acceptance.

## 6. Dictation, history, clipboard and preference verification

- Latest reliable final-session ID gates preview; partial, interrupted, cancelled or prior-session speech does not become a new request.
- New capture, cancellation, disabling the preference, deleting its source entry, clearing history or closing invalidates the preview task/token. A late callback cannot publish into the next session.
- UI fixtures verify exactly one original insertion and one history ID, unchanged raw/cleaned text, no target recapture and no additional insertion after a preview.
- History schema is unchanged. Raw recognition and accepted deterministic insertion text are preserved. AI preview is ephemeral and **is not persisted or applied to the old insertion record**; it does not create a duplicate history entry. Persisting a separately accepted AI insertion remains future gated work, not a claimed feature here.
- Copy/delete confirmations, clipboard leases, terminal manual-copy policy, declined accessibility-tree activation, speech engine,84×32 pill, sidebar/window dimensions and current formatting defaults remain unchanged.
- New preference migrates missing version1 key tofalse; explicit opt-in persistence is tested. No user preference was enabled by verification.

The app was opened safely through normal Quit and its existing active-session/clipboard guard, never forced termination. The canonical Run app was not overwritten. Separate build directories kept running previews untouched while code was hardened.

Final built app: `$REPO_ROOT/DerivedData/Phase1DComplete/Build/Products/Debug/Wesley Flow.app`.

Native AX inspection of this exact final build confirmed Smart Formatting → **Offline AI Rewriting**, value **off**, with text explicitly saying automatic AI insertion remains disabled. An earlier transient ScreenCaptureKit−3811 inspection failure cleared on retry. No recording, model-preview button, permission grant, clipboard copy or submission was automated during UI QA.

**Physical dictation → preview acceptance remains UNVERIFIED.** A human test was requested; no confirmation was available at report time. ChatGPT multi-session insertion is not claimed fixed. The final build is left open on Smart Formatting with the preference OFF. The earlier test request referenced an intermediate build; the open Phase1DComplete build is the final hardened one.

## 7. Evaluation properties and automated evidence

`REWRITE-EVALUATION.json` contains15 synthetic property contracts: casual English, repeated hesitations, Swift/TypeScript identifiers, paths, URLs, email, measurements, code, vocabulary/names, shortcuts, long bounded input, blank input, mixed scripts, unsupported locale and embedded instruction attempts. Properties concern preservation/fallback, not exact desired wording. Native quality coverage is only the samples above; other categories are fixture/property checks, not claimed live model passes or independent human review.

Final full native suite: **945 cases /431 declarations passed**,0 failures/skips. Fresh-process replay: **945 cases passed**. The previous902-case baseline is preserved;43 new expanded cases were added, no tests removed or weakened. Original test-file prefixes retain their pre-task hashes. The full native suite includes the new provider and app-lifecycle cases; the prior143 Python Model Lab tests were not relabeled as native evidence.

Focused core checks passed with controlled clocks/executors; final full tests include all later hardening. Coverage includes all outcome boundaries, marker mutation/order/duplication, wrong content words, input/output bounds, empty-success rejection, unsafe signs/symbols, bare filenames, model availability, foreign cancellation, caller cancellation, eight-second fallback while a generator stalls, busy-slot ownership, resource stop, suspended-clock completion race, final-only preview, unchanged target/history and opt-in migration/persistence. No arbitrary sleeps make these tests pass.

| Verification | Actual result |
|---|---|
| Full native suite |945 cases passed; exit0|
| Independent replay |945 cases passed; exit0|
| Debug build |Passed; exit0|
| Release build |Passed; exit0|
| Four frozen native outputs through final gate |Passed; exit0; no model execution|
| Actual production-model sessions |3 unchanged,1 invalid/fallback,1 resource/fallback;0 accepted improvements|
| Native UI control/default |Observed off in final build|
| Physical voice/preview/insertion matrix |UNVERIFIED|

All native builds used `/Applications/Xcode-beta.app/Contents/Developer`, Swift6.4/Xcode27 beta, arm64 macOS26 minimum on actual macOS27.2. Swift6 concurrency checks compile; there are no new Swift concurrency diagnostics. Routine AppIntents metadata-extraction notices are not app build failures. macOS26 runtime compatibility was not newly tested.

Exact relevant commands (cwd repository, DEVELOPER_DIR above):

| Action | Actual argv | Exit |
|---|---|---:|
| final-core | `/usr/bin/xcrun swift test --package-path Packages/WesleyFlowCore --scratch-path /tmp/wesley-phase1d-build --filter OfflineRewrite` | 0 |
| protected-final-core | `/usr/bin/xcrun swift test --package-path Packages/WesleyFlowCore --scratch-path /tmp/wesley-phase1d-build --filter OfflineRewrite` | 0 |
| ready-full | `/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/ready-full.xcresult test` | 0 |
| ready-replay | `/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/ready-replay.xcresult test` | 0 |
| ready-debug | `/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug build` | 0 |
| ready-release | `/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release build` | 0 |

Detailed JSON/logs/xcresult bundles are in `Evidence/Phase1D/`. `ready-full-summary.json` and `ready-replay-summary.json` preserve actual Xcode counts. `tested-source-hashes.json` binds the final Swift sources. Initial failed compiler attempts are not hidden: a wrong default clock dependency was removed via injection; Debug's expression type-check timeout was fixed with explicit intermediate values. `initial-debug.json`/log preserves exit65. An evidence-only frozen-replay compile later failed because a temporary source filename was missing; that file was restored and the successful rerun recorded separately. None of those failures was counted as a pass.

## 8. Readiness and remaining blockers

**Implemented:** opt-in, local-only production-oriented preview provider, reversible protection, typed fallback, session isolation, safe UI copy, cancellation/resource checks and verified builds/tests.

**PARTIAL:** useful accepted AI editing. Current live results show no accepted change, one quality rejection and one resource block. The strict gate also intentionally rejects many paraphrases/grammar changes. Do not advertise a demonstrated general grammar/meaning-preserving rewriting capability from this run.

**UNVERIFIED / DISABLED:** physical speech-to-preview acceptance, repeat cross-app insertion with AI text, model-service cleanup/peak attribution, non-English rewriting, and AI text persistence/insertion. Automatic AI insertion must remain disabled. The next necessary evidence is a human synthetic dictation/preview test and another separately scoped quality/resource evaluation when sufficient headroom exists; no model retry follows automatically.

No cloud inference, downloads, MLX loading, training, coding-agent execution, generated file effects, clipboard bypass, Return submission, commit or push occurred. **CUSTOM MODEL TRAINING: NOT STARTED.** Stop after Phase1D; no later phase began.

## 9. Git and preservation

Branch `main`, 0a3e91c731a716945853a6b84bcfaaf6d9e672d3 `0a3e91c731a716945853a6b84bcfaaf6d9e672d3`. Index empty; working tree remains intentionally dirty with prior work preserved. This milestone modified only AGENTS.md, AppComposition, DictationPreferences, GlobalDictationView, SystemWideDictationCoordinator, appended AppTests/GlobalDictationTests and appended WorkspaceTests/ProviderTests, plus the two new core rewrite source files and Phase1D documentation/property data.

The Xcode project, package dependencies, speech adapter, original formatting implementation, persistence schema, insertion/clipboard broker, model admission constants, V1/V2 datasets and cached models were not modified. No prior versionable file was deleted. `before.json` / `final-review.json` record hashes and intended deltas. Existing test content is preserved byte-for-byte before the appended Phase1D suites.

```text
 M .gitignore
 M AGENTS.md
 M App/AppComposition.swift
 M App/FoundationView.swift
 M App/WesleyFlowApp.swift
 M Docs/Phase1B/MODEL-PROVIDER.md
 M Docs/Phase1B/SECURITY-BOUNDARIES.md
 M Packages/WesleyFlowCore/Package.swift
 M Packages/WesleyFlowCore/Tests/WorkspaceTests/ProviderTests.swift
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
?? Docs/Phase1D/
?? ModelLab/
?? Packages/WesleyFlowCore/Sources/Domain/AppOpeningCommand.swift
?? Packages/WesleyFlowCore/Sources/Domain/Dictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/AppleTranscriptRewriter.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/LocalPromptRewriter.swift
?? Packages/WesleyFlowCore/Sources/Persistence/SwiftDataDictationHistoryStore.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeAppOpening.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/
```
