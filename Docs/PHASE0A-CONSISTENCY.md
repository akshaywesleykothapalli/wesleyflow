# Phase 0A consistency verification

18 October 2026 · Documentation-only review of revision 0A-amended-1. No application build, test, launch, model inference, dependency install or Git operation was run. Mechanical checks below inspect Markdown and preserved file bytes only.

## Manual consistency review

| Check | Conflict/dependency inspected | Resolution verified in the revised text |
|---|---|---|
| D1 | Review acceptance vs README/ADR/PLAN/AGENTS auto-authorization | All four require separate explicit scope approval; Phase 0A completion cannot authorize code |
| D2 | Swift mode vs compiler floor, beta SDK vs macOS minimum and CLT evidence | ENVIRONMENT/ADR003/DEVELOPMENT distinguish dimensions, set floor/isolation flags and three evidence lanes; GC pending blocks compatibility claims, not separately authorized shell work |
| D3 | Diagram vs imports, Workspace vs broker ownership, missing DailyOps value | Compile graph/allowlist aligns; adapters depend inward, no runtime authority; Workspace proposes and mediated reads, broker dispatches; workflow immutable/versioned/sequential, no 0B engine |
| D4 | “Non-sandboxed” as blanket approval; trust text vs human authority | SECURITY/ADR008/PLAN make general-purpose execution disabled until explicit mode/approval/evidence; website/project/voice/tool output cannot mint grants; cross-app insertion is a separate effect |
| D5 | Verifying approval, resume phase, cancelling terminalization and DB failure | Diagram/table agree; typed resume, expiry/failure, setup errors; cleanup independent of DB, generation/queue/iteration limits, process ownership and survivor/quarantine policy align |
| D6 | Offline inference vs online assets and macOS vs iOS capture | Per-locale supported/installed checks, visible provisioning/fallback and no network transcription; macOS capture, final/volatile/cancel semantics agree across architecture/ADR/plan/tests/security |
| D7 | “Set budgets later” vs mandatory provisional admission limits | 8 GiB incremental/4 GiB headroom adopted as constraints, not benchmarks; KV/load/system speech included, one lease/pressure policy and GM workload; quality thresholds predeclared in future provider ADR |
| D8 | “No source copies” vs retained patches, durable audit vs quotas/corruption | Metadata/digests default; content-bearing evidence opt-in; explicit local saves/rollback; stage/reference ordering, preserved corrupt store, no replay; quota reserve/emergency exception keep safety cleanup possible |
| D9 | “Launch if possible” and discovery vs actual/independent execution | G0 requires actual launch or remains incomplete; GC/G1/GV/GM/GE/GR have explicit pass/fail records and independent inspection/rerun requirement; no runtime pass claimed |

The independent review's amendments specify future tests before features, not immediate execution in Phase 0A. Resolving their documentation is compatible with retaining unexecuted gates. R4's future execution-mode choice is intentionally open and feature-blocking; it is not silently treated as OS isolation. Model/speech product quality thresholds must be fixed before acceptance, not fabricated now. K01–K11 enumerate remaining authorization and evidence conditions.

## Mechanical verification

D0 results are inserted from actual document checks after staging and rechecked at delivery. These are document checks, not application tests.

| Document check | Actual result |
|---|---|
| Packet inventory and edits | 9 Markdown documents; all nine changed; no application source or Git metadata in revised packet |
| Relative links | 133 references resolved, including 108 exact heading anchors; zero missing targets/anchors |
| Lifecycle diagram vs table | Exact match after expanding grouped rows: 9 states, 13 event types, 27 allowed state/event pairs; no outgoing terminal transitions |
| Future G0 enumeration | 117 pairs: 27 allowed and 90 rejected, plus guard cases. This is a documentation enumeration, not executed Domain tests |
| Dependency diagram vs allowlist | 11 nodes, 20 edges; exact agreement and acyclic |
| Traceability | 37 unique entries; R1–R8 and G0/GC/G1/GV-GM/GE covered, plus U-B/U-C/U-G |
| Preservation before install | Nine archived originals match the live pre-amendment packet byte-for-byte; authoritative review matches archived copy |
| Mechanical errors | 0; all checks above passed on the staged revision |

Delivery checks additionally compare installed files with this staged revision and original-review/archive hashes. [Revision manifest](PHASE0A-REVISION-MANIFEST.md) records the delivered document hashes; [original manifest](PHASE0A-ORIGINALS/SHA256SUMS.md) records recoverable source hashes. The manifest excludes its own hash to avoid self-reference.

## Review disposition

All R1–R8 mandatory amendment text and all five measurable-gate rows are mapped in 37 trace entries, with exact document sections and checks. No unresolved mandatory documentation finding blocks a separately authorized minimal Phase 0B scope. Immediate start still requires explicit user approval; actual toolchain availability can block G0 completion. Missing compatibility, isolation, speech, resource, persistence, permission and release evidence stays open at its specified gate. No code/feature readiness is inferred from this report.
