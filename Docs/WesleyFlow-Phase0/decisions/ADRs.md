# Architecture decision records

Revision 0A-amended-1, 18 October 2026. These are selected documentation decisions following independent review R1–R8, accepted by this architectural review with implementation gates. They are neither user implementation approval nor evidence of running software. Original proposed records remain recoverable in the original packet. Any future change records its reason, evidence and affected gates; do not silently replace the source/compiler or containment contract.

## ADR 001 — Independent native application

Retain SwiftUI with selective AppKit, macOS 26+, Apple Silicon. Entirely new application source; no inspection/reuse of legacy Wesley Flow, LocalFlow or DailyOps implementation. Revisit only for a concrete authorized platform requirement.

## ADR 002 — Incremental modules and dependency allowlist

Start app + local Domain package; add populated targets with real consumers/tests. Adopt ARCHITECTURE's Dependency allowlist; composition dashed edges become imports, never authority. Domain has no Apple UI/persistence/speech/model/process facilities; vendor configuration stays in adapters. Workspace proposes patches, SystemOperations applies effects, and CodingAgents receives no executor/grant issuer. Check actual dependencies/imports as modules arrive. Revisit edges only by ADR. Addresses R3.

## ADR 003 — Compiler floor and explicit concurrency

Adopt package tools minimum 6.2, explicit Swift 6 mode, compiler 6.2.3 source floor, macOS 26.0 deployment, arm64. Primary lane uses observed Xcode 27 beta/Swift 6.4/macOS 27 SDK as a coherent pair; verify exact installation before implementation. Compatibility lane is full Xcode 26.3/6.2.3/macOS 26.2 SDK on supported host, plus actual macOS 26.0 runtime. Core/shared defaults nonisolated; UI explicit MainActor; mutable services actor-owned; effective isolation/upcoming-feature flags recorded per target, no additional opt-in flags initially. Do not assume language mode implies older compiler compatibility or availability/back-deployment. ENVIRONMENT defines reproducible evidence and SDK/availability rules. Missing GC evidence blocks compatibility claims; raising floors requires an ADR. Addresses R2.

## ADR 004 — Voice is data, not authority

Capture/transcription emits editable transcript values only. Explicit review/submit starts planning; effects and cross-app insertion need separate trusted human approval. No spoken/model/project/website text grants authority. Stop finalizes; cancel discards; volatile ranges replace earlier text. Revisit never to bypass approval. Addresses R4/R6.

## ADR 005 — Replaceable model and runtime ports

Retain independent capability-driven inference and coding-runtime contracts. Adapters normalize requests, capabilities and errors; unsupported capabilities fail. No direct runtime native effects in baseline; an incompatible runtime is rejected. Models advertise identity/format/license/context/output/memory/cancellation. Core shell/typed/history paths work without a model; fine-tuning/distillation and training remain separate. Replacement passes contract tests without coordinator edits. Revisit only on evidence from actual integrations. Addresses R3/R7.

## ADR 006 — Scoped grants, sequential work and bounded agents

Only trusted user approval mints broker grants; one use, task/operation/session/digest/scope bound, 5-minute expiry, atomically checked/consumed at dispatch. No restored approval or model issuance. One executing task/operation, FIFO max 16 waiting and workspace leases including aliases/nested roots. Adopt ARCHITECTURE limits: 20 turns, 50 requests, 2 retries per failed step, 15-minute task execution excluding approval waits, 5-minute processes/approval requests. Limits cannot be raised by untrusted content. Revisit concurrency/limits only through measured need and ADR. Addresses R4/R5.

## ADR 007 — Explicit local SwiftData commits and bounded evidence

Actor-owned local-only schema v1, no CloudKit sync, explicit state+event save, autosave off for execution records, unique sequence/operation IDs, rollback on failed save. Default sanitized metadata/digests only; content-bearing evidence is separate opt-in (patches count as source copies), no raw audio retention baseline. Adopt 30 days, 100 MiB total including database/journals/staging, 1 MiB combined per-operation captured log, 10 MiB recovery reserve and new-effects quota blocking. ARCHITECTURE specifies artifact ordering/migration preservation. Passing G1 is mandatory before durable production claims. Revisit storage only on measured failure/performance requirements. Addresses R8.

## ADR 008 — Non-sandboxed shell; general-purpose execution disabled

Direct distribution remains the target; Mac App Store deferred. Non-sandboxed status is accepted only for shell and bounded broker operations, not blanket authority for arbitrary project code. General-purpose execution must await a separate ADR choosing verified OS isolation or explicitly approved unrestricted mode for user-trusted projects. Untrusted autonomous execution remains disabled without proven isolation. Process groups/XPC/signing/notarization are not containment. SECURITY defines descriptors, executable, argv, cwd, environment, network, digest and approval policy. GE is required before enabling general-purpose work; no mode is selected here. Signing/Hardened Runtime/notarization are later release gates. Addresses R4.

## ADR 009 — Offline speech capability and fallback order

Evaluate SpeechAnalyzer/SpeechTranscriber per locale/device with separate supported/installed checks. Assets are explicit online provisioning, not cloud transcription. Fallback is validated on-device DictationTranscriber, then SFSpeechRecognizer only with on-device support and requiresOnDeviceRecognition; otherwise clear typed input. Bundled engine requires separate dependency/resource ADR. macOS capture lifecycle, finalization/discard and duplicate prevention are required. GV blocks readiness until real offline/denial/asset tests and declared quality/latency thresholds pass. No provider/language is claimed ready. Addresses R6.

## ADR 010 — No inference dependency chosen; resource admission limits adopted

No library, model, weights or engine installed/selected in Phase 0A. Adopt provisional M4/16 GB 8 GiB aggregate incremental footprint ceiling and 4 GiB minimum estimated admission headroom, including workers/GPU/system speech/tool children without double counting. Budget weights/quantization/KV/scratch/prefill/load peaks; one lazy model lease, serialization until coexistence measured, unload before heavy verification, pressure/cancel/quarantine policy in ARCHITECTURE. GM requires fixed 30-minute corpus/workload and predeclared latency/quality thresholds. Values are design constraints, not benchmarks. Revisit only by measurement-backed ADR. Addresses R7.

## ADR 011 — Intent/outcome recovery and cancellation under storage failure

No atomicity across history and external effects. Persist sanitized intent first, per-file atomic replacement then outcome; multi-file changes may partially apply. Stage retained artifacts before committing references. Startup invalidates sessions/grants, marks all nonterminal tasks interrupted (including cancelling), reconciles artifacts/intents and never replays. Preserve old store on migration/corruption failure, block recovery rather than silently recreate. Emergency revocation/cleanup proceeds without a successful save; show uncommitted failure and reconcile prior intent later. Generation/state checks after awaits reject late callbacks. Cleanup budget 2+3 seconds, survivors/provider noncooperation cause quarantine/failure; stronger termination needs a process boundary. Revisit only for stronger verified recovery/isolation. Addresses R5/R8.

## ADR 012 — Architecture acceptance never authorizes implementation

Architectural acceptance does not authorize implementation. Phase 0B requires separate explicit user authorization naming repository/location, minimal shell, Domain tests and build/test/launch scope. Each future phase also needs explicit authorization. Phase 0A documentation is complete; nothing implements features or passes runtime gates. G0 completion requires actual launch, not “if possible”; GC remains a separate compatibility gate. Never infer user authority from this review or packet status. Addresses R1 and review acceptance gates.

## ADR 013 — Immutable sequential workflow values

Before Phase 1 implementation, adopt workflow ID/version, ordered bounded step inputs, approval checkpoints and verification requirements; snapshot on submission. Sequential steps only, edits create new versions, retries create linked tasks, no automatic partial replay/restart resume. No speculative workflow engine in 0B. G1 proves queue/lease/limit/replay behavior. Revisit concurrency only through ADR. Addresses R3/R5.

## ADR 014 — Execution evidence is separate from generation

Adopt TESTING gates G0, GC, G1, GV, GM, GE and GR. Gate evidence includes raw results, exact revision/environment/commands and independent inspection/rerun of critical scenarios under authorized scope. No generation, mocks, runner discovery or planned command counts as real execution. Missing checks block the corresponding feature/compatibility/release claim. No independent runtime verification is claimed in Phase 0A. Addresses all review measurable gates.

## Alternatives retained and rejected

Monolith rejected for weak boundaries; immediate empty-target proliferation rejected; cloud-first recognition/inference violates baseline; unrestricted embedded autonomous agent rejected; SwiftData in views rejected; raw SQLite remains a fallback only on measured requirements. App Sandbox from day one is not adopted implicitly, and that does not authorize arbitrary subprocesses. A helper/XPC boundary alone was rejected as an isolation guarantee. New ports/engines/workflow machinery remain deferred until authorized behavior needs them.
