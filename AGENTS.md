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
