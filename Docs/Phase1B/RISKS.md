# Phase 1B risk register

19 October 2026 · Potential future exposure, not findings of an enabled production agent.

| ID / priority | Risk and present evidence | Required closure / responsible boundary | Blocking scope |
|---|---|---|---|
| B-R01 / critical | No verified OS containment. Native OpenCode/shell can bypass WF-mediated tools; HTTP is not isolation | Select execution-mode ADR, explicit approval and B2 OS evidence; SystemOperations/security review | All live runtime/general-purpose host effects and untrusted autonomous work |
| B-R02 / high | Installed V1 1.18.25; rolling docs include incompatible V2 and potentially changed routes | Pin binary+schema, fixture/conformance test exact fields; CodingAgents | Live API enablement; fixture-only 1B.1 can proceed |
| B-R03 / critical | Configuration/plugins/hooks can execute before tool prompts; personal global config exists, contents intentionally unopened | Isolated config/data/home and sanitized context; effective provenance/negative tests; CodingAgents/SystemOperations | Live runtime launch |
| B-R04 / high | Current fixed-revision immutable TaskPlan cannot honestly represent edits/final verification | Narrow versioned plan/receipt/revision extension, migration/terminal/evidence regressions; Domain/TaskExecution/Workspace | Productive application/verification, not transport fixtures |
| B-R05 / critical | Current public token is identity, coordinator grant consume is not final filesystem enforcement | Broker-only one-use dispatch capability with final revalidation; SystemOperations | File/process effects |
| B-R06 / high | Abort RPC/HTTP cancellation does not prove worker, descendant or shared Ollama computation stopped | Positive resource evidence within 5 s or quarantine; no kill of unrelated daemon; supervisor/provider | Physical cancellation and safe resource-reuse claims |
| B-R07 / high | 7–8B weights plus cache/runtime/VM may exceed 8 GiB; 16 GiB machine has other load | Actual aggregate 30-minute M4 tests, declared thresholds; ModelProviders | Live model acceptance/E2E |
| B-R08 / high | OpenCode provider bridge/gateway and enforcement of turn caps unverified | Pinned provider protocol, bounded requests and no hidden inference; CodingAgents/ModelProviders | Live OpenCode+Ollama integration |
| B-R09 / high | Model tool quality unknown, particularly smaller context; no inference performed | Frozen 20-task corpus, malformed-call rejection, independent success; ModelProviders/Verification | Model selection, never authorization correctness |
| B-R10 / high | Build/test scripts are arbitrary code; Linux isolation cannot qualify AppKit/macOS verification | Accepted macOS contained runner/toolchain with B4 evidence, or hold feature; Verification/SystemOperations | Native independent command verification |
| B-R11 / high | Path swaps/hardlinks/nested aliases/external editors defeat naïve root checks | Handle-relative no-follow access, restrictive first patch scope, hashes and race/OS tests; Workspace/broker | Project access/effects |
| B-R12 / high | External runtime content caches bypass default sanitized WF history; projected quota not hard limit | Ephemeral isolated data, combined content quota accounting, opt-in artifacts, cache cleanup/uncertainty tests; Persistence/runtime | Privacy/quota/production evidence acceptance |
| B-R13 / high | Partial multi-file edits and DB/filesystem crash boundary cannot be atomic | Per-file intent/receipt and artifact matrix; inspect unknowns, no replay/automatic rollback; Persistence/broker | Productive reliability claims |
| B-R14 / high | macOS26.0 runtime and full Xcode26.3/6.2.3 lane remain unverified; selected tools beta | Separate GC/stable release evidence on supported host; compatibility owner | Compatibility/release claim, not docs/fixture design |
| B-R15 / medium | SSE replay/ordering/exact terminal events and retention lifetime unverified | B1 bounds, duplicate/foreign event tests, status reconciliation without resend; CodingAgents | Transport acceptance/live reconnection |
| B-R16 / medium | User authorization can be confused with malicious model/project approval text | Trusted UI exact scope, escaped rendering, no autoapprove; Presentation/broker | Every productive operation |

## Decisions still requiring evidence or approval

The primary transport and reduced-authority model are recommended. Execution-mode acceptance remains open: can a properly packaged sandboxed proposal helper run the pinned runtime with no host data/egress, or is a dedicated VM necessary and affordable? No mechanism has passed B2. A VM may need images/toolchains/entitlements and more RAM/storage than available; none is approved for provisioning here.

Can shared Ollama expose enough cancellation/residency evidence without disrupting other clients? If not, require a separately owned provider deployment or keep inference disabled. Can the exact V1 runtime route all inference through the scoped gateway and disable configuration/extension side effects? Can all internal turns/tool attempts be bounded? A negative answer favors the direct proposal-only provider fallback, not broader authority.

The versioned revision-chain/evidence extension needs an ADR and old-store tests before mutation. Source retention opt-in and a trusted approval/evidence UI must exist before sending real code or applying changes. Keep 0A graph/lifecycle intact and resolve contradictions explicitly; old historical phase numbering does not grant any new implementation scope.

## Readiness disposition

Documentation is ready for review and a **separately authorized 1B.1 fixture-only implementation**. Real OpenCode sessions, host changes, commands, model acceptance and 1B completion remain HOLD until their gates pass. No P0/P1 production defect is inferred solely from a future risk; these priorities describe how severely an unsafe integration could fail. Existing Phase1A compatibility/storage limitations remain in force.
