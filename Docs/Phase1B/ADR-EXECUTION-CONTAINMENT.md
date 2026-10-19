# ADR — execution containment after Phase 1B.2A

19 October 2026 · Status: **ADOPTED by explicit user request for Phase1B.2A finalization**. Feasibility decision **B — NATIVE HELPER INSUFFICIENT**. This ADR grants no live-execution or implementation authority.

## Context

The approved architecture requires an isolated proposal producer, WF-owned approvals/effects and positive all-resource stop evidence. Current fixture protocols provide no OS containment. Phase1B.2A tested an experimental signed App Sandbox parent and inheriting child, not OpenCode or an XPC service. See [feasibility report](PHASE1B2A-SECURITY-FEASIBILITY.md) for official Apple sources, commands, raw evidence locations and limits.

## Decision

Do not qualify the tested native helper as a complete future coding-agent boundary. Adopt **proposal-only local inference without OpenCode execution**, with bounded WF-controlled context/provider transport and inert output. Any actual operation remains separately mediated by a trusted broker; native verification commands require their own accepted isolation. No runtime proposal, public session ID or cancellation acknowledgement creates authority.

A minimal sandboxed XPC component without direct network/filesystem capabilities remains a candidate for a narrowly typed proposal/relay design. It must be tested independently, including peer authentication and descendant lifetime. Investigate a macOS VM separately only if tool execution remains necessary; no host filesystem shares, unconstrained NIC, credential or clipboard bridge. Its performance/admission and guest stop gates must pass on M4/16 GiB before selection. Neither alternative is accepted through this experiment.

## Evidence classification

| Classification | Claims |
|---|---|
| **Demonstrated, limited to tested host/profile** | Approved synthetic reads/writes succeeded. Outside-container file, traversal and symlink attempts failed EPERM with positive unsandboxed controls. No-network socket/connect attempts failed; listener saw no connections. Correctly entitled child reproduced restrictions. NetworkClient parent/child reached changing local listener ports. |
| **Demonstrated limitations** | An unrelated sibling inside the sandbox container remained readable. `/usr/bin/true` executed despite being outside the WF test allowlist. Forced parent death left a live lock-holding child; the external runner had to stop it. Non-inheriting fixture copies were rejected, which is narrower than denying every unauthorized executable. |
| **Demonstrated lifecycle behavior** | Normal/cancel/timeout/repeated cancel/graceful parent shutdown/forced child paths completed; actual parent wait status, kernel child exit and lock release were observed. Forced-parent cleanup was by the runner, not automatic containment. |
| **Reasonable expectations, not measured guarantees** | A small native proposal-only component should cost less than a full macOS guest. Properly restricted XPC separates privileges. A guest without host integrations should provide a stronger whole-worker lifecycle boundary. These require concrete implementations and adversarial tests. |
| **Unsupported assumptions — must not rely on** | XPC or Process.run alone isolates a runtime; signing metadata proves every denial; a private cwd limits file authority; App Sandbox is a per-task path/command allowlist; network.client restricts inference destinations; parent death or abort acknowledgement proves descendant/provider death; fixture tests prove OpenCode or VM security. |
| **Unresolved** | Exact installed runtime/config/plugin packaging, generic native worker confinement, authenticated IPC and inherited descriptors, resource quotas, provider cancellation, all-descendant stop/quarantine, stable signing, macOS26 runtime/Swift6.2.3 floor, VM RAM/disk costs, hostile build execution and real model budget. |

## Consequences and acceptance gates

The experimental result provides useful OS-denial evidence while keeping live agents disabled. It does not close B-R01/B-R03/B-R06/B-R07/B-R10 or approve unrestricted host mode. A fresh ephemeral worker container may improve cross-task separation, but no such production lifecycle was proven.

Retain the existing Domain graph, broker rejection of productive operations, immutable plans, session/generation fencing, durable intent/outcome ordering, bounded fixture streams and cleanup uncertainty. Preserve the 2 s graceful plus 3 s escalation shared budget and quarantine rule; the prototype's per-wait watchdogs do not implement that production contract. Never release a conflicting lease solely because an RPC or task acknowledged cancellation.

Further implementation needs a separately scoped request. Acceptance must bind concrete binaries/entitlements, exact context/IPC/network surface, real macOS26 and distribution signing tests, external-negative controls, stale-identity-safe ownership and stop evidence, and measured aggregate memory within the existing 16 GiB hardware constraints. If no candidate passes, retain proposal-only capability and hold productive native tool execution.

No production code, service install, VM provisioning or live model/runtime execution follows this ADR. The user separately authorized one reviewed local documentation/experiment checkpoint; no push or later implementation. Follow the [revised architecture](ARCHITECTURE.md), [proposal contracts](PROPOSAL-CONTRACTS.md) and [milestones](IMPLEMENTATION-PLAN.md). Stop after finalization.
