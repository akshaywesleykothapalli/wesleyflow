# Wesley Flow — Phase 0A amended architecture

Revision: 0A-amended-1 · 18 October 2026. **Phase 0A documentation complete; design accepted with explicit implementation gates. Phase 0B is not authorized or started.**

This is an independent greenfield macOS 26+ Apple Silicon design. No previous Wesley Flow, LocalFlow or DailyOps source was inspected, copied, imported or migrated. The packet specifies future behavior; it contains no application implementation or executed application verification.

## Review packet

- [Architecture, dependencies and lifecycle](architecture/ARCHITECTURE.md)
- [Architecture decisions](decisions/ADRs.md)
- [Environment evidence and compatibility contract](ENVIRONMENT.md)
- [Directory plan and standards](DEVELOPMENT.md)
- [Testing and measurable gates](TESTING.md)
- [Security and human authority](SECURITY.md)
- [Phased plan](PLAN.md)
- [Project instructions](AGENTS.md)

## Approval requested

Architectural acceptance does not authorize implementation. Phase 0B requires separate explicit user authorization naming the new repository/location, minimal shell, Domain tests, and build/test/launch scope. Approval of these documents, or of a reviewer verdict, cannot substitute for that instruction. Each later phase also needs explicit authorization.

The eligible Phase 0B scope is one native window, composition, a local package with pure task values/transitions, foundational tests, and actual verification. Coordinator, history, speech, inference, workflow execution and system effects are outside 0B. See [implementation gates](PLAN.md#implementation-gates).

## Amendment evidence

The independent review remains unchanged at [PHASE0-ARCHITECTURE-REVIEW.md](../PHASE0-ARCHITECTURE-REVIEW.md). Review requirements R1–R8 and every measurable gate are mapped in the [traceability matrix](../PHASE0A-TRACEABILITY.md). See the [consistency report](../PHASE0A-CONSISTENCY.md), [remaining risks](../PHASE0A-RISKS.md), and [completion report](../PHASE0A-COMPLETION.md). The recoverable original packet and hash manifests are under [PHASE0A-ORIGINALS](../PHASE0A-ORIGINALS/README.md).

## Current result and limitations

All mandatory documentation amendments have concrete decisions and future pass/fail checks. Runtime evidence remains pending, not passed. Earlier environment observations are preserved with provenance limitations. The beta host cannot prove macOS 26.0 runtime behavior or the full Xcode 26.3 compatibility lane. Speech locale readiness, model performance, persistence recovery, permission behavior, signing and process containment remain unverified. General-purpose execution is disabled by design until the separate security decision and evidence gate is satisfied. Untrusted autonomous execution requires demonstrated OS isolation; an unrestricted trusted-project mode cannot enable it.
