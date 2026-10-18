# Wesley Flow Phase 0 — architecture review

18 October 2026 · Decision: **APPROVE WITH REQUIRED AMENDMENTS (design only)**

The native shell, incremental modules, inward dependency direction, separate speech/model/runtime adapters, and intent/outcome recovery approach are suitable for a greenfield foundation. Approval is conditional on the amendments below being incorporated into a future approved revision. This review grants **no implementation authorization**. Phase 0B still needs separately scoped explicit user approval; later phases retain their own gates. General-purpose execution remains on hold until the security gate in R4 is resolved.

## Scope and evidence

Read the complete original packet: README.md, architecture/ARCHITECTURE.md (including both diagrams), decisions/ADRs.md (001–012), ENVIRONMENT.md, DEVELOPMENT.md (directory plan included), TESTING.md, SECURITY.md, PLAN.md, and AGENTS.md. These are all nine files in the packet; all local document links resolve. Originals are preserved. No legacy source was inspected; no app source, repository, dependency installation, application code execution, build, test, or launch was performed. Environment outputs are packet evidence, not independently reproduced measurements. Official sources below were checked for design assumptions.

## Required amendments

### R1 — Separate review acceptance from execution authority

**Before Phase 0B:** Amend README “Approval requested”, ADR 012, PLAN 0B and AGENTS “Scope and approval gates”. Replace automatic authorization on architecture approval with: “Architectural acceptance does not authorize implementation. Phase 0B requires separate explicit authorization naming its repository/location, shell, Domain tests, and build/test/launch scope.” Record this review as conditional acceptance, not completed implementation or user approval. The current four documents would otherwise turn a review verdict into permission to execute work the user expressly excluded.

### R2 — Make the toolchain compatibility contract explicit

**Before Phase 0B:** Amend ENVIRONMENT, DEVELOPMENT and ADR 003. Distinguish compiler version, Swift 6 language mode, package tools minimum, SDK used to compile, deployment target, and OS used to run tests. Swift 6 mode alone does not guarantee Swift 6.2.3 source compatibility. Choose a proposed minimum package tools version of 6.2 and explicitly select Swift 6 language mode; use only features supported by that floor unless an ADR raises it. Explicitly choose nonisolated default isolation for shared/core targets and MainActor UI annotations; record upcoming-feature settings per target. [Swift concurrency guidance](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/enabledataracesafety/).

Use coherent Xcode compiler/SDK pairs. Xcode 27/Swift 6.4 with the macOS 27 SDK and deployment 26.0 is a valid *strategy*, not proof of macOS 26 runtime compatibility. Apple lists Xcode 27 with Swift 6.4 and macOS 12–27 deployment targets, and Xcode 26.3 with Swift 6.2.3/macOS 26.2 SDK; its supported host range ends at macOS 26.x. The packet’s macOS 27 host therefore cannot establish that older full-Xcode baseline. The CLT compiler is not a replacement for app/XCTest verification. [Apple compatibility matrix](https://developer.apple.com/xcode/system-requirements).

Keep the unusual reported host/build and compiler target triples as unverified observations; do not treat a compiler’s default target triple as the configured app deployment target. When implementation is separately authorized, recapture exact paths/versions and retain logs. Require availability checks for APIs newer than macOS 26; compiler/SDK guards or exclusion are also needed for declarations absent from the older SDK. Rebuild dependencies per compiler; do not share compiler-specific binary modules or build caches across lanes.

### R3 — Preserve dependency direction; specify missing application contracts

**Before Phase 0B:** Amend ARCHITECTURE “Dependency diagram” and DEVELOPMENT. The compile-time graph is acyclic and correctly points adapters and TaskExecution into Domain. Keep it. Clarify that dashed composition edges become real imports when those targets exist; they do not imply adapters can execute each other. Add a dependency allowlist checked against package/project target dependencies as modules arrive. Domain must not import UI, SwiftData, Speech, inference SDKs, or process facilities; CodingAgents must not receive an unrestricted executor. Domain may define narrowly scoped ports, but adapter-specific configuration stays with adapters.

**Before Phase 1:** Define a versioned workflow value containing ordered steps, inputs, approval checkpoints and verification requirements. Initially allow sequential steps only; snapshots of an in-flight workflow are immutable, edits create a new version, retries create linked tasks, and partial completion never causes automatic replay. DailyOps is currently a product goal without a workflow contract; do not add a speculative workflow engine in 0B.

### R4 — Turn the containment disclaimer into an enforceable gate

**Before Phase 0B:** Amend ADR 008 and PLAN phases 4–6 to state that non-sandboxed status is accepted only for the shell and deliberately bounded broker operations. SECURITY correctly acknowledges that arbitrary builds/tests execute code with the user’s authority. A root, argv allowlist, approval dialog or process group cannot constrain that code’s filesystem, network, Keychain, or descendant behavior. An XPC helper alone is also not a sandbox. Apple distinguishes sandbox inheritance from privilege separation. [Apple sandbox guidance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).

**Before any general-purpose execution:** Require a separate ADR choosing either tested OS-enforced isolation with explicit filesystem/network policy, or an explicitly approved unrestricted mode for user-trusted projects. Keep untrusted autonomous execution disabled until isolation is demonstrated. Define executable identity, argv, working directory, minimal environment, inherited descriptors, network policy, output limits and timeout in each operation. Explain that executing scripts/build configuration may change effects without changing argv. Approval binds the displayed operation and relevant workspace revision/digests; mismatch requires reapproval, without claiming this removes all races.

Separate approval presentation from runtime authority: only trusted user interaction can mint a one-use broker grant, bound to task/operation/session, scope, digest and expiry; consume it atomically immediately before dispatch. Never expose grant issuance to model/runtime ports. Include text insertion, Accessibility and Apple Events in the effects policy; plain dictation does not authorize cross-app insertion.

### R5 — Complete lifecycle, cancellation and persistence-failure semantics

**Before Phase 0B:** Amend the state diagram and transition table together. It currently cannot request approval from `verifying`, cannot fail from `awaitingApproval` on timeout/revocation, and always resumes approval into `running`. Add `verifying → awaitingApproval`, retain a typed resume phase, and permit approval failure/expiry. Cancellation from approval waits must revoke grants and release resources before terminalization. Explicitly handle failure before execution, including planning/setup failures.

**Before Phase 1:** Specify a generation/operation token and state recheck after every suspension to reject late callbacks. Actor isolation does not prevent reentrancy races. Define FIFO queue capacity, overflow response and cancellation behavior. Emergency revocation/cleanup must work even when history writes fail: stop new effects, perform bounded cleanup, show an uncommitted failure in memory, and reconcile persisted intent on restart. Never require a successful database write before stopping a process.

For processes, define graceful termination, escalation deadline, concurrent stdout/stderr draining, bounded output, and reporting of survivors. Process-group cleanup is best effort against ordinary children; detached/escaped descendants need the separate containment design. A noncooperative provider must not freeze the coordinator indefinitely: quarantine/disable it, report cleanup failure and withhold the next resource lease until safe; stronger termination requires a process boundary.

### R6 — Specify offline speech readiness and fallback

**Before Phase 2:** Amend ADR 009, SECURITY speech/network rows and PLAN phase 2. Evaluate SpeechAnalyzer/SpeechTranscriber first on macOS 26 for each selected locale/device; check supported and installed assets separately. Asset installation is an explicit online provisioning step, with progress, cancellation and failure states. Offline inference does not mean first-run assets are already present. Apple documents device/language limits, asset downloads and DictationTranscriber as another candidate. [Apple SpeechAnalyzer session](https://developer.apple.com/videos/play/wwdc2025/277/).

Fallback order: a validated on-device native alternative, otherwise typed input with a clear unavailable state; any bundled engine requires its own dependency/resource ADR. For SFSpeechRecognizer, require both on-device support and `requiresOnDeviceRecognition = true`; unsupported must fail locally. [Apple on-device requirement](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition). Distinguish stop-and-finalize from cancel-and-discard; replace volatile segments instead of duplicating them. Use macOS capture APIs, not an assumed iOS AVAudioSession lifecycle. Test offline after provisioning and missing-assets first launch separately.

### R7 — Add a provisional admission budget for M4/16 GB

**Before Phase 3:** Amend ARCHITECTURE resource policy, ADR 010 and TESTING. Deferring model selection is correct; deferring all admission limits is not. Proposed initial ceiling: **8 GiB aggregate measured incremental footprint** for app, inference workers/GPU allocations, speech services and tool children, with **at least 4 GiB estimated system headroom** at admission. These are conservative review proposals, not measured capacity or performance promises; revise through an ADR after target-device evidence. Do not double-count shared allocations or omit system speech memory merely because it is outside app RSS.

Record weights, quantization overhead, KV cache at maximum allowed context, scratch/prefill peaks and load-time peaks. Raw 4-bit weights alone are approximately 4 GB for 8B parameters or 7 GB for 14B, before overhead; neither is a fit guarantee. Cache and weights both affect memory behavior. [MLX-LM resource guidance](https://github.com/ml-explore/mlx-lm).

Default to one model lease; unload inference before memory-heavy verification, and serialize speech/inference until coexistence passes. Reject/defer over-budget admission, cap context/output, and stop/unload on sustained pressure. Validation must include a fixed 30-minute workload, peak system footprint, swap growth, pressure, thermal state, unload and cancellation. No OOM or sustained critical pressure is permitted; latency/quality targets must be declared before accepting the selected provider.

### R8 — Make durable history and privacy compatible

**Before Phase 1:** Amend ADR 007/011 and ARCHITECTURE storage. Use an actor-owned context with explicit saves for state+event commits, not implicit autosave as acknowledgement. Roll back failed mutations before retry; require unique task/sequence and operation identities. SwiftData provides explicit save/transaction APIs, but crash recovery still requires tests. [Apple ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext).

Define initial schema version, migration failure/corrupt-store behavior (preserve evidence; never silently recreate), artifact staging/reconciliation order, and explicit local-only configuration. Persist sanitized structured metadata, digests and outcomes by default; transcripts, prompts, tool output, argv and patches can contain secrets or source and need separate retention policy. Current “no source copies” wording conflicts with persistent patches: make that exception explicit and opt-in, or retain only digests by default. Proposed initial limits: 30-day history, 100 MiB evidence storage, 1 MiB per captured operation log; never prune active/uncertain evidence silently. At quota, block new effects and offer export/deletion.

## Measurable gates to add to TESTING and PLAN

| Gate | Required pass evidence when separately authorized |
|---|---|
| 0B foundation | Debug and Release arm64 builds exit 0; Domain and composition tests discovered and executed, zero failures/skips; every defined state/event pair exercised (including invalid pairs), terminal immutability and verification-required success rejection; shared scheme/result bundles; actual window launch. If launch is unavailable, mark 0B incomplete. |
| Toolchain/OS | Separate results for selected Xcode 27 lane, full Xcode 26.3/6.2.3 lane on a supported host if that source floor is retained, and actual macOS 26.0 runtime tests. Pending lanes remain explicit compatibility blockers, not inferred passes. |
| Phase 1 integrity | Fault injection before/after intent save, effect and outcome save; reopen store after each crash point; zero automatic replay/restored grants; denial/revocation/stale grant yields zero new effects; cancellation at every suspension rejects late success; dependency allowlist passes. |
| Phase 2–3 resources | Declared locales and fixed audio/text corpus; provisioned network-disabled run; missing/revoked assets and denial cases; finalization without duplicate segments; maximum-context/load/unload and pressure tests against R7 limits; declared latency and accuracy thresholds met. |
| Phase 4–6 effects | Traversal/symlink/swap/conflict fixtures; bounded-output/nonzero/timeout children; proposed 2 s graceful + 3 s escalation cleanup limit, ordinary fixture descendants gone by 5 s and survivors reported; adversarial escape tests required for any containment claim; passing/failing verification linked to exact task/workspace revision. |

Phase 0B should remain small: native window, composition and pure Domain transitions only. Coordinator, durable history, providers and process execution belong to later authorized phases. Adopt the document amendments before 0B; satisfy the behavior-specific gates before enabling their corresponding features. No wholesale architectural rewrite is required.
