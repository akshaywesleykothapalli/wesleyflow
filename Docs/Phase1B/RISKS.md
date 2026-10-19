# Phase 1B risk register — proposal-only architecture

19 October 2026 · Updated after adopted2A finalization. Future exposure, not evidence of an enabled production agent. Original risk history is preserved in Git and phase reports.

| ID / priority | Current evidence and changed applicability | Required closure | Blocking scope |
|---|---|---|---|
| B-R01 / critical | Tested App Sandbox enforced outside-container restrictions but lacked complete task/executable/descendant boundary. Live OpenCode disabled, not accepted with deferrals | Separate concrete isolation decision/tests if any untrusted execution returns; command subgate remains mandatory | General runtime and generated build/test execution |
| B-R02 / high | Pinned1.18.25 static schema/fixtures retained; live binary conformance untested. Not a dependency of direct inference | New decision/authorization plus exact binary/schema conformance before optional reuse | Optional future OpenCode only |
| B-R03 / critical | OpenCode configuration/plugins/hooks remain unverified; no launcher enabled. Hostile project text also threatens provider/policy injection | No execution of context/config; strict data-only proposals and trusted provider routes; contained safe-start proof before any runtime reconsideration | Runtime startup; PC/PI hostile-context acceptance |
| B-R04 / high | Existing fixed-revision TaskPlan cannot honestly represent edits | Versioned per-step expected/observed revision/effect ADR, old-model migration tests, immutable application task | PE productive editing |
| B-R05 / critical | Public identities are not dispatch authority; current broker rejects productive effects | Private one-use final-dispatch capability with exact scope/generation/deadline/root/hash rechecks | Every productive effect |
| B-R06 / high | Child survived forced parent death. Provider HTTP cancel is not server stop; no model inference tested | Positive owned-resource/lease settlement within shared5s or quarantine; never kill unrelated daemon | Resource reuse/physical-stop claims; commands |
| B-R07 / high | M4/16GiB; two7–8B artifacts known historically, no winning benchmark. Tiny helper RSS is not model budget |30-minute aggregate8GiB/headroom4GiB target-device workload and artifact accounting | PI live model acceptance |
| B-R08 / high | OpenCode-to-Ollama gateway no longer required; direct Ollama structured output and cancellation unverified | Replaceable ModelProvider conformance, bounded structured bytes, no arbitrary routes/pull/cloud, exact leases | PI enablement |
| B-R09 / high | Proposal quality and stale/malformed handling unmeasured | Frozen20-task corpus, compare both candidates; reject invalid output, select neither on failure | Model selection; never grants authority |
| B-R10 / critical | Builds/tests execute arbitrary code even without an agent runtime. App Sandbox experiment did not qualify a general runner | Separately establish and test contained macOS runner; independent actual command evidence | Command-based verification in PE/PX |
| B-R11 / high | Pure paths/hashes cannot stop root/symlink/hardlink/alias races | Trusted handle-relative no-follow reads/effects, root/file identities, scoped snapshots and actual race tests | PC disclosure and PE writes |
| B-R12 / high | Prompts/source/cache/evidence can exceed retention/quotas | Opt-in content, sanitized durable summaries, combined100MiB quota/10MiB reserve; actual provider accounting and cleanup | PC/PI/PE privacy and production retention |
| B-R13 / high | Multi-file effects and DB are not one atomic transaction | Per-file intent/receipt/crash reconciliation; no automatic retry/rollback; unknowns visible | PE/PX reliability |
| B-R14 / high | Swift6.4/Xcode27beta/macOS27.2 evidence only; actual macOS26 and compiler floor open | Separate full older-toolchain/runtime and stable signing/release lane | Compatibility/release claims |
| B-R15 / medium | Fixture SSE bounds/epochs tested; optional live replay still unverified. New proposal decoder not implemented | Preserve existing fixture tests; PB strict bounded parser/digest vectors; PI bounded stream and no blind resend | PB/PI, optional runtime reconsideration |
| B-R16 / critical | Model/project approval text can imitate user intent; a validation result is not authority | MainActor exact diff/scope approval, policy/validator failure blocks, one-use broker dispatch; no approval/result wire fields | Every productive operation |
| B-R17 / high | Proposal-only design reduces execution authority but still discloses selected source to provider and admits hostile structured bytes | PC explicit bounded disclosure; PB unknown/duplicate/schema/size rejection; provider threat/privacy model | PB/PC/PI |

## Current disposition

Architecture adopts proposal-only local inference, not an active feature. PB documentation is ready for separately scoped implementation. No broker/provider is enabled. OpenCode fixture infrastructure is preserved and disabled. XPC/VM are research alternatives only; neither is accepted for general execution and no provisioning is authorized.

Accepting this reduced architecture closes the decision of which primary path to pursue; it does not close the evidence gates above or Phase0 ADR008's requirements for any future command execution. No risk is waived because an application policy says denied, a signature exists, cancellation was acknowledged, or351 deterministic tests passed.
