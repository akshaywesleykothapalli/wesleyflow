# Testing and evidence strategy

## Evidence status and independence

**No application code, application builds/tests, launch or benchmarks exist from this task.** Phase 0A verification checks documents only. The gates below are future pass/fail requirements, not executed results. Generated code, discovered runners and proposed commands never count as successful execution.

Every future gate record includes source revision, configuration, toolchain/SDK/OS, exact command or manual procedure, timestamps, exit status, discovered/executed/failed/skipped counts and durable result paths. An execution verifier must inspect raw results and rerun the critical scenario independently of the code-generation narrative, on authorized hardware/scope. This is a gate requirement, not a claim that an independent reviewer or second agent has run anything. Mocks prove only the named contract; manual consent tests and real integrations are labeled separately.

## Test layers

| Layer | Evidence |
|---|---|
| Domain unit | Every finite state/event pair, invalid guards, terminal immutability, timeout/denial/retry linkage, verification-required success rejection |
| Coordinator | Approval resume phase, FIFO/overflow, leases/limits, post-await generation checks, late results, cancellation at each suspension, persistence-failure emergency cleanup |
| Repository | Explicit atomic state+event save, rollback, uniqueness/idempotency, reopen/migration/corruption, crash intent/outcome/artifact ordering, quota/delete/export |
| Broker/workspace | Human-only grant issuance, one-use/expiry/revocation, traversal/no-follow/symlink/swap, aliases/nested roots, stale hashes and external edit conflicts |
| Processes | Fixture output flood, nonzero exit, timeout, cleanup, descendants/survivors, descriptors/environment, network policy according to selected mode |
| Providers | Identity/capabilities, unsupported operations, bounded streams, offline readiness, load/cancel/unload/pressure and replacement without coordinator edits |
| Native UI | Construct shell state, actual launch, keyboard/accessibility, approval provenance/escaping, empty/denied/error states |
| Target-device E2E | Provisioned offline dictation, explicit submission/approval, approved edit, truthful passing/failing verification, relaunch/recovery, resource/thermal workload |

Prefer Swift Testing for pure package tests; XCTest/XCUITest where app/UI integration needs it. Verify actual library/toolchain support when targets are authorized. Doubles use deterministic clocks/events and temporary roots/stores; no accidental microphone/Accessibility prompts. Real consent tests use signed, explicitly provisioned runs and remain separate from unit evidence.

## G0 — Phase 0B foundation gate

Only after separately scoped Phase 0B approval:

1. Clean independent repo/location and populated app + Domain + test targets; shared app/test scheme, no legacy source or speculative features; dependency allowlist passes.
2. Debug and Release arm64 builds exit 0 using recorded coherent Xcode 27 lane with deployment 26.0.
3. Domain and composition tests discovered and executed, zero failures and zero skips; retain result bundles. Exhaust every state/event pair in ARCHITECTURE's finite set, including failed guards, verification-required success rejection and terminal immutability. Composition test constructs actual shell state.
4. Actual launch shows the native foundation window and no feature/permission prompts. Record manual/UI evidence independently of compilation. If unavailable, 0B stays incomplete.
5. Independent execution-result inspection as above; state all missing compatibility lanes and release evidence. Passing G0 is not GC or production feature acceptance.

## GC — Toolchain and macOS compatibility gate

Separate evidence for coherent Xcode 27/Swift 6.4/macOS 27 SDK development, full Xcode 26.3/Swift 6.2.3/macOS 26.2 SDK on supported host, and actual macOS 26.0 runtime (arm64). Both compiler lanes build Debug/Release and execute applicable tests with zero failures/skips. Verify effective deployment target and availability paths; use per-lane caches/results. Minimum-OS runtime includes launch and real relevant feature paths as phases arrive, not only stubs. Missing lanes remain compatibility blockers. They need not prevent shell development after separate approval, but prevent claims of proven baseline compatibility. Stable release Xcode and permission/signing evidence are required before shipping.

## G1 — Integrity, cancellation and recovery gate

At every boundary before/after intent commit, productive effect, per-file replacement, artifact publish and outcome commit, inject failure/crash then reopen the store. Require no automatic replay or restored grant; preserve prior state and mark uncertainty. Test explicit-save failure rollback, duplicate sequence/operation callbacks, migration success/failure, corrupt-store preservation and missing/orphaned artifacts. No silent store recreation.

Denial, stale/expired/revoked/replayed grants and changed operation digests produce zero new productive effects. Cancel at every suspension; late success cannot change terminal state or release another lease. Verify emergency revocation/cleanup works when history cannot write and records uncommitted failure visibly. FIFO max 16 waiting, overflow rejects visibly; global and alias/nested-root leases prevent simultaneous effects; external edits cause conflicts. Test 20 turns/50 requests/2 retries/15-minute task/5-minute process/5-minute approval limits with deterministic clocks. Test 30-day retention, 100 MiB total including journals/staging, 10 MiB recovery reserve, quota blocking and complete row/artifact deletion.

## GV — Offline voice gate

Declare device, exact locale list, API/assets version when observable and fixed audio corpus before acceptance. Separately test supported/installed, missing assets first launch offline, explicit online install/cancel/failure/revocation, permission denial and provisioned network-disabled recognition. Document network controls/observations; offline recognition must succeed without transcription upload. Unsupported language yields validated on-device alternative or clear typed-input fallback. For SFSpeechRecognizer assert support and requiresOnDeviceRecognition; never enable network fallback. Confirm stop finalizes, cancel discards, volatile replacements create no duplicate segments, and transcript alone neither submits tasks nor inserts text/executes operations. Declare latency/accuracy thresholds before the acceptance run; failing them blocks locale/provider readiness.

## GM — Model and M4 resource gate

Provider ADR must predeclare model/artifact/license, maximum context/output, memory measurement method/uncertainty, critical-pressure signal, latency/quality thresholds, and representative fixed audio/text/repository corpus. Run a fixed 30-minute M4/16 GB workload with baseline, cold/warm loads, maximum-context prefill/decode, repeated unload/load and cancellation. Include system speech/tool/GPU memory without double-counting; record aggregate incremental peak, admission headroom, swap growth, pressure, thermal state, load latency, first-token latency, tokens/s and quality. Apply 8 GiB peak ceiling and at least 4 GiB estimated headroom; no OOM or critical pressure sustained beyond 2 seconds. If credible measurement is unavailable, heavy integration fails admission. Verify 5-second cleanup/quarantine, serialization and unloading before memory-heavy verification. Declared quality/latency thresholds must pass; these are not fabricated benchmarks. Shell/core non-inference paths also pass with zero models loaded.

## GE — Effect and general-purpose execution gate

Before general-purpose processes/builds/tests or native runtime effects, require the separate execution ADR and explicit user approval in SECURITY. Document isolated or trusted-project unrestricted mode and its limits. Untrusted autonomous execution requires adversarial tests establishing OS-enforced filesystem/network isolation, including symlink/path swaps, secret access, subprocess escape and detached descendants. A process group/XPC helper or passing ordinary fixtures cannot establish containment. Unrestricted mode must remain visibly unrestricted and reject untrusted autonomous work.

Bounded filesystem effect tests cover traversal, symlink/no-follow races, stale original hashes, partial multi-file writes and concurrent external edits. Process fixtures cover output cap/truncation with continued draining, nonzero exit, timeout, environment/descriptors and cancellation. Require ordinary child/descendant cleanup by 5 seconds (2-second graceful + 3-second escalation); deliberately unkillable/escaped fixtures must report failed cleanup/survivors and quarantine resources. Verify task/operation ownership and no next conflicting lease. For approval UX, project/website/tool text cannot issue grants; spoofed markup stays inert; cross-app insertion/Accessibility/Apple Events have independent approval and real OS-consent tests. Model adapters lacking bounded cancellation fail acceptance.

## GR — End-to-end and release gate

After separately authorized feature phases, run on target hardware: offline dictation → reviewed submission → exact approval → edit → passing and failing verification → truthful result → restart history/recovery. Link results to exact task/operation/revision; relevant edits during verification invalidate it. Check accessibility/keyboard, signed consent denial/revocation, GC matrix, resource gates, stable Xcode baseline, Hardened Runtime, Developer ID signature and notarization before release. A failed or missing required check blocks its feature/release; do not relabel it as success-with-limitations. Repeat broader checks only when changes or unresolved issues warrant them.
