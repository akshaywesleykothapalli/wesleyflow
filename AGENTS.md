# Wesley Flow implementation instructions

Phase 0B is explicitly user-authorized at this new repository. Follow Docs/WesleyFlow-Phase0 and its review/traceability/risk documents. Their statements about pending Phase 0B approval are historical; the current user instruction authorizes the shell, pure Domain values/transitions, composition, tests, Debug/Release builds and launch only. It does not authorize Phase 1.

No legacy application implementation may be inspected/reused. No voice, agents, subprocess execution, workflows, inference, persistence or permission prompts in 0B. Use the explicit full Xcode toolchain, Swift 6, macOS 26.0 arm64, package tools 6.2, nonisolated core and explicit MainActor UI. No external dependencies. Maintain all state/event and guard tests. Keep actual build/test/launch evidence separate from compatibility/release claims; no code-generation success claims. Stop after 0B and await separate authorization.

## Current Phase 1A authorization

The user explicitly authorized Phase 1A: durable task orchestration, FIFO scheduling, permission policies, SwiftData persistence, cancellation/timeouts, interrupted recovery, sanitized event logging and verification interfaces, with deterministic test executors. This supersedes the historical 0B-only stop above for this scope only. Preserve existing work, use native Codex approvals where required, keep changes in WesleyFlow, run Debug/Release builds and automated tests, inspect Git changes, and stop after Phase 1A. No real coding agents, voice, unrestricted processes/automation, remote pushes or later phases. Architecture boundaries and compatibility/release limitations continue to apply.

## Phase 1A remediation authorization

The user separately authorized fixing audit A1–A4 and the small observer cleanup A5, regression/recovery/stress tests, relevant documentation, and one local commit named `fix(core): resolve task lifecycle concurrency defects` only after all P1 fixes and verification pass. Preserve pre-existing Phase1A work, use native approvals, and keep the historical audit/evidence. No push, remote creation or Phase1B/product integration is authorized.

## Phase 1B.1 fixture-only authorization

The current user explicitly authorizes Domain protocol values, a populated CodingAgents target, injected HTTP/SSE fixtures, bounded actor-owned fixture sessions, inert launch data, tests and actual Debug/Release/full-suite/replay verification. Preserve existing design documents and Phase1A behavior. No OpenCode invocation, launcher, live agent/provider/network execution, productive tools, Phase1B.2, commit or push. Runtime identities/proposals never grant execution authority.

## Phase 1B.1 final review and checkpoint authorization

The user separately authorizes final review, narrow Phase1B.1 fixes with regression verification, explicit staging of reviewed implementation/documentation, and one local commit named `feat(agent): add fixture-only coding runtime foundation`. This supersedes the prior no-commit statement for that single checkpoint only. No push, remote creation, live runtime/provider execution or Phase1B.2 work.

## Phase 1B.2A containment feasibility authorization

The current user authorizes only an experimental Swift sandbox helper, ad-hoc signing of disposable test bundles, harmless synthetic filesystem/local-listener/process-lifecycle probes, relevant tests/builds and feasibility/ADR documentation. Keep experiments outside production targets. No OpenCode, inference, sensitive-data access, unrelated projects, system service installation, privileged/system-security changes, broad Phase1B.2, commit or push. Same-user native Codex execution approval does not authorize sudo or system-wide changes. Stop any test requiring those and report it separately.

## Phase 1B.2A finalization and adopted architecture

The user adopts proposal-only local AI inference. Follow Docs/Phase1B/ARCHITECTURE.md, PROPOSAL-CONTRACTS.md, revised milestones/gates and the adopted ADR. Keep OpenCode fixture infrastructure preserved and disabled; ModelProvider remains a replaceable documented future port. No model commands, writes/deletes, self-approval or permission expansion. Only a separately authorized future broker may perform effects; no provider/broker is activated now. This request authorizes documentation/contracts-in-documentation, scope/evidence consistency review, preservation of the existing standalone containment experiment, and one reviewed local commit named `docs(security): adopt proposal-only coding architecture`. It supersedes the prior no-commit instruction only for that checkpoint. No live inference, new production source, Phase1B.2B implementation, push or remote creation. Before any command-based product verification separately establish and test subprocess containment. Stop after finalization.

## Phase 1B.2B proposal validation authorization

The user authorizes the ten proposal Domain contracts, strict bounded serialization/hashing and a pure Workspace validation engine with injected snapshots/policy, fixtures/tests and actual focused/full/replay/Debug/Release/concurrency/module verification. Preserve Phase1A and1B.1 behavior; no broker, filesystem observations/effects, provider/runtime/AI execution, new services or external dependencies, or later phase. Validation is data-only and never user approval or an executable capability. The earlier no-1B.2B statement is superseded only within this scope. No commit, staging, push or Phase1B.2C. Stop after1B.2B.

## Phase1B.2B final review and local checkpoint

The current user authorizes independent review, narrow Phase1B.2B fixes/regressions and verification if necessary, explicit staging of reviewed Phase1B.2B files, and one local commit named `feat(workspace): implement structured proposal validation`. This supersedes the prior no-staging/no-commit statement for that checkpoint only. No push, remote creation, live model/runtime/effects, or Phase1B.2C. Preserve historical evidence and stop after the checkpoint.

## Phase1B.2C read-only observation authorization

The current user authorizes an explicit fixture-root registry, read-only descriptor broker in SystemOperations, Domain observation ports/data, Workspace snapshots/context and proposal integration, deterministic disposable-fixture tests, documentation and actual builds/full/replay verification. Historical no-2C statements are superseded only for this scope. No app operational wiring, automatic real-project access, filesystem effects, live provider/runtime/inference, general process executor, new entitlement, Phase1B.3, staging, commit or push. Preserve existing behavior and stop after2C.

## Phase1B.2C final review and local checkpoint

The current user authorizes independent review, reproducible Phase1B.2C fixes/regression tests, actual focused/full/replay/Debug/Release/concurrency verification, explicit staging of only reviewed files, and one local commit named `feat(workspace): add secure read-only project context`. This supersedes the preceding no-staging/no-commit statement only for this checkpoint. Preserve prior behavior/evidence; no push, remote creation, live inference, productive operations or Phase1B.3. Stop after the checkpoint.

## Phase1B.3A proposal-only local provider authorization

The current user authorizes local Ollama0.33.0 metadata/conformance inspection, a replaceable ModelProviders implementation, synthetic-only structured proposals through existing validation/coordinator ports, deterministic fixtures, bounded sequential experiments with installed models and memory admission, relevant documentation and actual builds/full/replay verification. This supersedes historical no-inference/no1B.3 restrictions only within1B.3A. No real user source disclosure or edits, tools/commands, OpenCode, cloud fallback, model downloads/training, privileged services, Phase1B.4, staging, commit or push. Do not bypass memory admission to produce benchmark results. Stop after1B.3A.

## Phase1B.3A engineering review and foundation checkpoint

The current user authorizes engineering review, narrow Phase1B.3A defect fixes/regression verification if necessary, explicit staging of reviewed source/tests/configuration/documentation and one local commit named `feat(models): add guarded local Ollama provider foundation`. This supersedes the previous no-staging/no-commit rule only for this foundation checkpoint. Do not start inference, change safety thresholds, claim live-provider acceptance, push, create a remote, or begin a later milestone. Preserve the measured40 BLOCKED model rows and all live inference/cancellation/unload limitations. Stop after the checkpoint.
