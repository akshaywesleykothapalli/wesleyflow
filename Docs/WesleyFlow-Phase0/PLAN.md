# Phased implementation plan

## Implementation gates

Architectural acceptance does not authorize implementation. Phase 0B requires separate explicit user authorization naming the independent repository/location, minimal native shell, Domain tests and build/test/launch scope. Each later phase also requires explicit authorization. Completion never starts another phase automatically.

Phase 0A is documentation complete with all mandatory review amendments addressed as design decisions. No user implementation approval, application code or runtime gate pass is implied. Remaining evidence and security decisions are in [risk register](../PHASE0A-RISKS.md).

| Phase | Authorized scope only after its own user instruction | Required exit evidence |
|---|---|---|
| 0A — amended documentation | Nine-document revision, original backup, traceability, consistency review, risks and completion report | Documentation checks pass; no app source/repo/builds/dependencies; stop here |
| 0B — awaiting separate authorization | Independent repo/Xcode app, one native window, local Domain values/transitions and tests, composition test | G0: actual Debug/Release arm64 builds, exhaustive state/event + composition tests zero failures/skips, result bundles, dependency allowlist, actual launch; missing launch means incomplete |
| 1 — task/permission foundation | Coordinator, local durable history/recovery, cancellation, private grants, bounded read operation, immutable sequential workflow values | G1: no effects on invalid grant, crash/reopen and storage-failure cleanup, no replay/restored grant, queue/limits/leases and artifact/quota behavior |
| 2 — offline voice | macOS capture/transcription, per-locale asset readiness, explicit submission, validated native fallback then typed input | GV: declared corpus/thresholds, provisioned network-disabled tests, missing/revoked assets, install/cancel/denial, no command/insertion from transcript |
| 3 — local models | One compatible provider selected by license/format/cancellation evidence | GM: fixed 30-minute M4/16 GB workload, 8 GiB ceiling/4 GiB headroom, measured peak/KV/load/unload/pressure, predeclared quality/latency thresholds; core works without model |
| 4 — bounded automation | Root-scoped approved edits/macOS effects and their consent UX | G1 + applicable GE effect fixtures; general-purpose processes remain disabled until separate execution ADR and approval; containment cannot be inferred from broker |
| 5 — coding agent | Bounded context, one compatible proposal-only runtime, reviewed patches/conflict checks | Compatible adapter contract, exact grants, version/limits/leases and stale edits tested; native/unbrokered effects unsupported; general-purpose work still subject to execution gate |
| 6 — build/test verification | Revision-bound plans, actual subprocess verification, result capture/failure classification | GE execution ADR/mode and explicit approval first; passing/failing/timeout/cleanup fixtures, survivor/uncertainty/stale revision handling and actual evidence; untrusted autonomous work only with verified isolation |
| 7 — hardening/replacement/release | Second provider/runtime only if needed; accessibility/performance/release | GC + GR, contract replacement, target-OS feature tests, stable Xcode, signed real permissions, Hardened Runtime/Developer ID/notarization and resource evidence |

## Gate dependencies and unresolved decisions

G0 can be attempted only after separate scope approval and environment recapture; a missing GC lane blocks compatibility claims, not shell work on the available coherent lane. GC requires full Xcode 26.3 on supported host and actual macOS 26.0 runtime in addition to the primary lane; CLT discovery cannot substitute. No toolchain installation is authorized now.

G1 precedes all productive later effects. General-purpose execution is held until a separate ADR chooses OS-isolated mode with filesystem/network enforcement, or explicit trusted-project unrestricted mode with visible user-account authority. The unrestricted choice never permits untrusted autonomous work. Adversarial isolation evidence is mandatory for containment claims. This decision is open and blocks enabling general-purpose features in phases 4–6; it does not block 0B shell construction under separate approval.

GV/GM must set exact locales/artifacts and latency/accuracy/quality thresholds before acceptance runs; current resource and retention numbers are adopted conservative limits, not measured benchmarks. Speech asset provisioning can be online while recognition remains offline; do not claim preinstalled assets or offline subprocess networking. Core paths require no model.

Choose bundle identifier/location/signing team only in authorized setup scope. Unsigned compilation cannot prove production consent behavior. SwiftData v1/migration/recovery remains conditional on G1; no durable feature claim before evidence. Future fine-tuning/distillation means separately validated model artifacts/providers; datasets/training need a new proposal.

## Stop condition

Finish Phase 0A documentation, report resolved requirements and open implementation risks, then request separately scoped Phase 0B authorization. No code, project/repo, dependencies, runtime, builds/tests or future phases are authorized by the current documentation task.
