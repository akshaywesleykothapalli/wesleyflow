# Phase 1B.2A finalization and architecture pivot

19 October 2026 · **Adopted: proposal-only local AI inference. Security finding B: the tested native helper configuration is insufficient for Wesley Flow's complete general-purpose coding-agent requirements.** This is not a finding that App Sandbox is insecure/nonfunctional. No production implementation or live provider/broker activation in this task.

## Why the architecture changed

2A demonstrated useful OS restrictions: outside-container file/symlink/traversal and configured local-network probes were denied. The experiment's token guard was application-level fixture scoping, not OS confinement. Same-container sibling reads and a system executable were permitted. A held child survived forced parent death and required explicit runner cleanup. Signing/self-inspection established metadata; raw operations/positive controls established the measured restrictions. Other transports/descriptors/quotas, actual XPC/VM/OpenCode and macOS26 behavior remain unverified. See [full evidence](PHASE1B2A-SECURITY-FEASIBILITY.md).

The previous primary OpenCode worker and runtime-to-provider gateway assumptions are superseded. Choose the smaller authority surface: selected context → replaceable local ModelProvider → strict structured proposal → validator → policy → user approval → separately implemented controlled broker → independent verification → durable result. Neither a prompt nor an approval grants the model a runner or file handle. Keep OpenCode disabled. Do not bypass the failed complete-execution gate with unrestricted host mode.

## Reuse, exclusions and contracts

Preserve the entire Phase1B.1 implementation/test suite and source provenance. Runtime Domain values, injected HTTP/SSE fixtures, bounds, actor correlation/cancellation and inert manifests remain disabled optional infrastructure. Phase1A orchestration/persistence/policy contracts and module direction remain intact. No new Swift file, target, dependency, build setting, launcher, permission or startup entry was added during finalization.

No OpenCode launcher, native tool dispatcher, JS bridge/SDK, ACP adapter, configuration shim or OpenCode-to-Ollama gateway is required for the new primary path. They are not implemented, removed from existing code, or silently enabled. ModelProvider remains the existing documented future abstraction, not a claimed implemented port. Ollama is the primary future adapter. Historical/user-supplied candidates qwen3:8b and qwen2.5-coder:7b remain unranked; no inference, refreshed inventory, download or benchmark occurred.

[Proposal contracts](PROPOSAL-CONTRACTS.md) document all ten requested Sendable-compatible version 1 values: CodingProposal, ProposalIdentifier, ProjectIdentifier, WorkspaceSnapshot, ProposedFileChange, ExpectedFileRevision, ProposalValidationResult, ProposalRejectionReason, ApprovalRequirement and VerifiedChangeResult. No implementation of 1B.2B is included. Strict bounded decoding rejects unknown versions/keys/kinds, duplicates, malformed/oversized inputs and absolute/unsafe targets. Only regular text create/update proposals are representable; no commands/deletions/permission fields. Trusted snapshot/policy comparison rejects stale or unauthorized changes. Model claims are distinct from independently observed effects.

## Authorization and remaining OS requirements

Explicit context selection/disclosure occurs before inference. A validated proposal still has no authority. Policy computes exact approval requirements; MainActor review shows project/diff/hashes/scope. A failed validator/policy cannot be overridden by approval. A future broker must atomically consume private one-use task/session/generation/descriptor/root/revision/deadline-bound authority and recheck immediately before effects after every await. Current PermissionBroker still rejects productive operations.

Actual project editing requires PC root/context evidence, PB validation, PE exact broker authority, versioned immutable revision/receipt contract and migration tests, no-follow race-resistant effects, per-file durable intent/receipts and independent post-state verification. Partial/unknown effects stop work and never auto-replay/rollback. Proposal prepared, content verified and contained build/tests passed are distinct results.

Proposal-only inference removes the untrusted tool runtime, not all OS concerns: host file reads/writes still need trusted scoped mechanisms and privacy controls; provider processes/IPC/network/residency need ownership/resource evidence. Before any command-based product build/test verification, separately establish and test subprocess containment, descendants, egress, output bounds and stop within the shared 2 s + 3 s cleanup budget. Existing self-project Xcode regression evidence is not permission to execute generated code in user projects. VM/XPC alternatives remain separate investigations; no services/images/security changes authorized.

## Milestones and readiness

| Milestone | Revised responsibility |
|---|---|
|1B.2B | Structured proposal Domain, strict decoder and pure validation; no IO/inference/effects |
|1B.2C | Read-only authorized context and secure snapshots |
|1B.3 | Local Ollama structured proposals behind replaceable ModelProvider, benchmark both candidates |
|1B.4 | Controlled file effects and independent verification; commands require separate containment subgate |
|1B.5 | Disposable-project coding evaluation after every applicable gate |

[Implementation plan](IMPLEMENTATION-PLAN.md) supplies dependencies, scope, concrete modules, boundaries, tests, gates and failure handling per phase. [Acceptance criteria](TEST-AND-ACCEPTANCE.md) replace broad old B2 with PB/PC/PE and a separate command gate without declaring the old gate passed. Core lifecycle, TTL/revocation, immutable revision chain, 8 GiB incremental / 4 GiB headroom, provider settlement and no-replay requirements remain.

**Ready for separately scoped 1B.2B pure Domain/validation implementation. Not authorized to start it here.** Live inference, editing, command execution and complete Phase1B acceptance remain blocked on later gates. Remaining risks include hostile proposal parser/canonicalization, context disclosure/races, private dispatch capabilities, partial effects/crash reconciliation, shared provider cancellation/memory, stable signing and actual macOS26/Swift6.2.3 compatibility. No model winner or universal containment conclusion is claimed.

## Finalization verification and checkpoint

Reviewed all pending changes and experimental source/scripts. Experimental entitlement dictionaries only generate ad-hoc disposable evidence bundles; they grant no production signing privileges. App/Package/Xcode membership references no experiment/helper/entitlement/startup configuration. No generated bundle/binary/plist, credential, raw log, database or DerivedData is included in the checkpoint. Experimental source is retained as reviewed reproduction material outside production targets; it is not a product execution path.

No experimental test, Swift source or build configuration changed in finalization. Hash comparison against the finalization-start baseline verifies those files unchanged. Therefore the prior actual 227 assertions/16 scenarios, 351 cases/113 functions and Debug/Release results are preserved, **not rerun or relabeled as new results**. The prior final review checked 48 recorded process identities with none remaining. Original raw evidence/result bundles and failures remain in ignored Evidence/Phase1B2A. No new process probe/inference was run.

Documentation consistency checks validate local links, the strict synthetic JSON example and expected shape, all ten contract names and milestone gate mapping, adopted/disabled status, hashes of all production/experimental source and package/project settings, whitespace and exact pending/index allowlists. The reviewed index excludes credentials/artifacts and unexpected source changes; checks/command exits and hashes are in ignored Evidence/Phase1B2AFinalization. This is structural document verification, not executable validation-engine testing or a formal security proof.

Reviewed checkpoint paths are the updated Phase1B architecture, security, provider, lifecycle, risk, acceptance and implementation documents; new proposal-contract/pivot/ADR/feasibility documents; four historical reports with status pointers only; AGENTS current authorization; and the five previously authorized containment experiment source/readme files. Exact inventory, staged diff, evidence hashes and actual commit/status are retained in Evidence/Phase1B2AFinalization. A commit cannot contain its own hash; the final response and ignored checkpoint record supply it after creation.

Commit authorized by this request only: `docs(security): adopt proposal-only coding architecture`. One local checkpoint, no remote/push, no later phase. The experiment's earlier no-commit restriction is superseded only for this reviewed checkpoint. Stop after finalization.
