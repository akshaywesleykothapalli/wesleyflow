# Phase 1B implementation milestones

19 October 2026 · Each milestone needs separate scope authorization. None is implemented by this packet.

The numbering groups delivery; it does not authorize bypassing dependencies. Security work precedes live tools. First live coding target must be a fresh disposable Git repository containing only approved fixtures, never WesleyFlow. Do not make a new repository during this documentation task.

## 1B.1 — Runtime adapter and session lifecycle

- **Objective:** Implement the smallest V1 HTTP/SSE contract and actor-owned session lifecycle against deterministic fixtures; keep live worker launch disabled.
- **Files/modules:** Domain narrowly consumed runtime values/port; populated CodingAgents target; App composition wiring only for fixtures; dedicated adapter tests; docs/evidence. No SystemOperations productive capability.
- **Interfaces:** CodingAgentRuntime; typed session/event/proposal/cleanup values; existing TaskClock and injected task executor for proposal-only operation. Capture binary metadata/schema fixtures from an authorized non-executing discovery path; if unavailable, mark live contract pending.
- **Dependencies:** Current Phase1A baseline; explicit toolchain; D01 acceptance. No JS SDK dependency or installs needed for fixtures.
- **Security:** No host root, executor, grant issuer or live process in adapter. Reject native permission requests, unknown schema/version, foreign session IDs and redirects. Startup launcher gate stays closed until 1B.2 OS gate and separate execution-mode approval.
- **Scope:** Encode/decode selected messages, readiness/error mapping, bounded SSE and actor session mapping, cancellation/cleanup assessment, progress disposal. No real inference, mutations, subprocesses or agent sessions.
- **Tests:** Split/malformed/oversize frames, duplicates/foreign IDs, disconnect/reconnect ambiguity, session creation failure, cancellation races, deadline -1/0/+1, shutdown, exactly-once disposal and no automatic resend.
- **Acceptance:** B1 gate; zero failures/skips in relevant new and existing tests, actual Debug/Release builds, all transport limits and zero real effects asserted. Fixture success is not live OpenCode support.
- **Failure:** Version ambiguity, event loss, unbounded buffers/tasks, false stopped/success or required undocumented safety behavior. Keep live adapter unavailable.
- **Rollback:** Unwire new adapter/feature flag; preserve Phase1A store and test baseline, no automatic DB reset. Return to honest unavailable state.

## 1B.2 — Permission enforcement and project boundaries

- **Objective:** Establish authority, registration and effect containment before any live file-changing or general-purpose tool.
- **Files/modules:** Domain descriptors/capabilities and versioned coding-plan envelope; Workspace registration/context/patch validator; SystemOperations broker/contained worker supervisor; TaskExecution narrow receipt/revision integration; Persistence metadata/migration only if consumed; App approval rendering; corresponding tests.
- **Interfaces:** ProjectRegistry, scoped read port, canonical OperationDescriptor, broker-only dispatch authority, per-file EffectReceipt, immutable expected revision chain, resource/lease cleanup assessment. Session actor still has no host executor.
- **Dependencies:** B1; explicit execution-mode ADR and scoped approval; supported containment feasibility; current Phase1A recovery contract. No live runtime just because the fixture adapter passes.
- **Security:** Prove helper inheritance or guest boundaries, no host mounts/secrets/egress, authenticated limited channels, reject project config/plugin execution, atomic one-use final dispatch, root handles/no-follow checks, alias leases, sanitized environment and positive owned-resource stop. Grants expire at 5 min, revoke on cancel/restart; no broad approval memory.
- **Scope:** Registration/read-context/structured create-update patch review; deterministic effect fixtures first. Commands remain disabled until B4 and actual contained verification approval. Live proposal can be exercised only after its own OS/protocol gates, no inference until B3. If containment fails, retain disabled state.
- **Tests:** Full B2 matrix including actual outside-root sentinel access attempts, path-swap/symlink/hardlink/alias races, native-tool bypass, malicious config, stale/forged grant, wrong repo, partial multi-file crash, no replay, source privacy and quota.
- **Acceptance:** B2 policy AND real OS containment rows pass on target host, zero unauthorized effects, all cases reported; all existing tests/builds pass; old store reopens. No host write enablement until revision-chain/receipt tests pass. Model fixture text does not count as containment evidence.
- **Failure:** Any escape, hidden runtime extension, unexpected network, reused grant, invalid hash accepted, unknown disposition erased, unbounded cleanup or inability to establish enforcement. Block productive feature, retain quarantined evidence.
- **Rollback:** Disable launcher/effects, revoke session, bounded cleanup, preserve user changes/uncertainty; no git reset or blanket file rollback. Migration rollback only from explicit preserved store copy while no active/uncertain operations exist.

## 1B.3 — Local model provider integration

- **Objective:** Add Ollama behind a replaceable provider port and scoped runtime inference gateway, with measured M4 admission/cancellation.
- **Files/modules:** Domain model capability/lease values; ModelProviders Ollama adapter/gateway; CodingAgents gateway configuration mapping; App selection/status; provider tests and benchmark evidence. No cross-adapter imports.
- **Interfaces:** ModelProvider; resource budget/pressure observer; exact request cancellation/unload assessment; provider-gateway protocol mapping verified for pinned V1.
- **Dependencies:** B1 plus B2 before live runtime, selected installed artifact/digest/license, no download. Transport-only Ollama conformance may precede live OpenCode but never broadens permissions.
- **Security:** Local-only allowlisted routes, no credentials/cloud fallback, no pull endpoint, no model tool execution, one leased request; refuse unaccounted shared-daemon interference. Reject any gateway request outside task/artifact/deadline scope.
- **Scope:** Discover two installed artifacts; bounded generation/load/unload/cancel; 4k context evaluation and explicit unavailable/pressure states. No MLX engine, training or new model installation.
- **Tests:** B3 provider, gateway malformed tool calls, daemon loss/overload, foreign activity, digest mismatch, offline, pressure, HTTP-cancel-with-server-still-busy, memory and measured 30-minute workload.
- **Acceptance:** B3 actual provider and memory/quality thresholds pass; no accepted inference without credible budget. Full suite/Debug/Release pass. Report installed versus selected versus accepted separately.
- **Failure:** Unsettled request/lease, unsafe shared daemon, over-budget, ineffective unload, poor tool quality or unsupported gateway mapping; select no model rather than bypass contract.
- **Rollback:** Disable provider/gateway, cancel/quarantine owned request, keep core/history usable; never stop user's daemon or delete their models.

## 1B.4 — Independent build/test verification

- **Objective:** Establish revision-bound actual command/evidence verification independent of the model.
- **Files/modules:** Verification target; Domain evidence manifests; SystemOperations contained command dispatch/output drain; TaskExecution final evidence guard/revision chain; Persistence artifact references/quota; App safe evidence view and tests.
- **Interfaces:** VerificationPlan, broker process descriptor, actual process/evidence receipt and final snapshot manifest. Only broker owns executable/argv launch.
- **Dependencies:** B2 execution-mode/command containment and explicit approval; B3 required only for model-driven proposal flow. Native macOS verification needs a proven macOS toolchain execution boundary; Linux guest results cannot substitute.
- **Security:** Build scripts/tests are arbitrary code. Review exact argv/cwd/env/network/output paths and toolchain; no shell interpolation; unload model before heavy verification; isolation prevents home/network access and escaped children. Do not run generated fixture code on host without the accepted contained mode.
- **Scope:** Deterministic passing/failing/stale/empty test fixtures, parse actual build/test evidence with independently chosen commands; no agent-selected success criteria or automatic fix loop.
- **Tests:** B4 actual exits/signals, zero discovered tests, missing/corrupt/truncated artifacts, known intentional failure, source change during run, timeout/fork survivors, storage failure and restart at artifact/DB boundaries.
- **Acceptance:** Every required command executed with evidence; intentional failure never passes; exact final snapshot stable; discovered/executed counts meet fixture expectations; resource stop proof and all B4 rows pass. Debug/Release/core regressions remain green.
- **Failure:** Narrative-only success, absent evidence, stale snapshot, hidden skipped tests, unsupported toolchain/runtime or survivor. Report failed/incomplete, preserve uncertainty, no verified success.
- **Rollback:** Disable verifier/effect dispatch; retain evidence and actual files; do not revert user changes or promote completed edit to verified success.

## 1B.5 — End-to-end disposable project evaluation

- **Objective:** Exercise registration → approved context → real bounded proposal → reviewed patch → approved effect → independent verification → durable result and cancellation/recovery.
- **Files/modules:** Existing adapters and composition, user task/approval/evidence UI as needed, end-to-end fixtures/evidence and docs; no new broad abstraction by default.
- **Interfaces:** Previously accepted ports only; changes require the same contract tests/decisions.
- **Dependencies:** B1–B4 all applicable real gates, stable pinned environment, isolated disposable repo with known contents and no credentials. WesleyFlow is explicitly prohibited as the first live target.
- **Security:** No production checkout or unrelated data. Adversarial config/injection included; commands/effects still require exact grants; no commit/push or network. Verify shutdown/restart leaves no reused authority or hidden worker.
- **Scope:** Three fresh fixture copies: known success, intentionally failing test, cancelled partial edit; plus restart and hostile inputs. No self-modifying WesleyFlow, voice, DailyOps, training or unrestricted autonomy.
- **Tests:** B5 complete flow and failure/recovery matrix, foreign session rejection and one global inference/effect lease under concurrent submissions.
- **Acceptance:** B5 passes with actual commands/results/artifact hashes/revisions, zero forbidden dispatch, all failure paths accurately reported and all foundational tests/builds green; no containment claim from simulations. Missing compatible-host or OS evidence remains visibly open.
- **Failure:** Any missing prerequisite, permission bypass, false verified success, survivor, unstable budget or unreported partial effect. Hold milestone; no automatic retries.
- **Rollback:** Disable live composition, revoke and quarantine as necessary, preserve stores/artifacts and fixture changes for review. Disposable repo deletion requires its own scope; do not silently clean uncertain evidence.

## Prerequisite ordering

B1 fixtures → B2 authority/root/revision/containment → B3 live provider → B4 contained independent verification → B5 live E2E. B2 can begin with deterministic policy development before isolation feasibility is solved, but its acceptance cannot omit OS evidence. No future milestone silently authorizes installations, VM images, Xcode provisioning, network changes or model downloads. Plan any such dependency separately. Stop after each scoped milestone and report unmet gates.
