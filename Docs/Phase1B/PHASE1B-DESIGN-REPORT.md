# Phase 1B.0 design report

Current architecture note (2A finalization): this is a historical phase record. [Proposal-only architecture](ARCHITECTURE.md) and the [adopted containment ADR](ADR-EXECUTION-CONTAINMENT.md) now govern delivery. OpenCode stays disabled; retained gateway/runtime references below describe optional infrastructure, not a requirement or authorization for revised1B.3. Original evidence and phase results remain unchanged.


19 October 2026 · Documentation-only delivery · No implementation authorization inferred.

## Recommendation

**Accept the design for review; proceed only to separately authorized 1B.1 transport/session fixtures. HOLD live OpenCode and productive coding until security/resource gates pass.** Recommend native Swift HTTP/SSE for installed V1 1.18.25 behind replaceable runtime/provider ports. OpenCode produces proposals from selected context in a verified isolated worker; Wesley Flow owns approvals, actual effects and independent evidence. Do not attach OpenCode's native tools to the host checkout. [Integration decision](OPENCODE-INTEGRATION.md), [security](SECURITY-BOUNDARIES.md).

A sandboxed proposal helper is a feasibility candidate, not an established solution. A no-host-mount VM is the fallback for native runtime containment; its M4/16 GiB cost and macOS verification requirements remain unproven. If neither fits/passes, leave OpenCode disabled and consider direct local inference producing inert proposals. Basic permissions, cwd, XPC and process groups are insufficient OS isolation evidence.

## Actual environment findings

Read-only inspection in this task; no installs, launches, agent sessions or inference.

| Check | Actual observation |
|---|---|
| Git at start | main, clean; HEAD 686a0af7aebdfb270ef3cfefc51ecb703d017e4a |
| OpenCode | CLI/package opencode-ai 1.18.25, **V1**; resolved CLI `/Users/akshaywesley/.nvm/versions/node/v20.20.0/bin/opencode` |
| Ollama | `/opt/homebrew/bin/ollama`; client 0.33.0; existing daemon local version API 0.33.0 |
| Installed models | qwen3:8b Q4_K_M 5,225,388,164 bytes; qwen2.5-coder:7b Q4_K_M 4,683,087,561 bytes; full hashes/context metadata in [provider](MODEL-PROVIDER.md) |
| Loaded models | Local `/api/ps`: empty; no model loaded by this task |
| Developer selection | Global `/Library/Developer/CommandLineTools`; explicit full `/Applications/Xcode-beta.app/Contents/Developer` used for discovery |
| Xcode / compiler / SDK | Xcode27.0 build27A5237l; AppleSwift6.4 swiftlang6.4.0.30.4; macOS SDK27.0 |
| Host / hardware | macOS27.2 build26B5112a; hardware Mac16,12, 17,179,869,184 bytes physical RAM (16 GiB); M4 target as previously recorded |
| Memory snapshot | memory_pressure -Q: 55% system free at observation; vm_stat includes compression; not accepted workload headroom |
| Storage snapshot | Data volume 228 GiB, used153 GiB, available approximately50 GiB, 76% used; rounded system output |
| Relevant config | `~/.config/opencode/opencode.jsonc` exists; checked json/jsonc project files absent; config contents/auth stores/environment secrets intentionally unopened |

Personal effective runtime permissions/plugins/provider config are therefore **unknown**; a live integration must use an independently controlled environment. No configuration override or safety claim is based on the unread file. No arbitrary home/user data was inspected. macOS26 runtime, full Xcode26.3/Swift6.2.3/SDK26.2 and stable release qualification remain unverified; this host cannot substitute.

### Check method and permission handling

Executed CLI version checks, package.json name/version/bin metadata inspection, `xcode-select -p`, explicit-full-Xcode `xcodebuild -version`, `xcrun swift --version`, `xcrun --sdk macosx --show-sdk-version`, `sw_vers`, `vm_stat`, `df -h` and Git read-only status/revision inspection. Combined discovery command completed exit0 but contained sandbox-denied `sysctl` and Ollama socket subcommands; those were not treated as successful checks.

Native approval was then obtained for `ollama list`, `sysctl hw.memsize hw.model`, `memory_pressure -Q` (command exit0), and a read-only local API inventory script (exit0) using urllib with 3 s timeouts for GET `http://127.0.0.1:11434/api/version`, `/api/tags`, `/api/ps`. It emitted only version and allowlisted model metadata. The existing daemon responded; none was started. No credential/config file contents, process-wide environment dump or API keys were requested. OpenCode version invocation was metadata only, not `serve`, `run` or `acp`.

## Inspection findings and reuse

Read current AGENTS and actual approved architecture/ADRs plus development/security/testing/environment/plan, 0A traceability/consistency/risks, Phase1A completion/audit/remediation, package targets, Domain types/transitions/ports, coordinator, SwiftData store, permission broker, App composition and foundational assertion coverage. No legacy application source was accessed.

Reuse the coordinator, lifecycle, durable ledger, private approval issuer, clocks and executor/verifier ports. Preserve actor boundaries and the approved inward dependency allowlist. The original audit's four P1 issues and observer P2 are documented as repaired in the committed remediation; this task did not rerun an engineering audit.

Two required integration amendments are explicit: public OperationToken is not filesystem authority, so add broker-only final dispatch capability; fixed-revision TaskPlan cannot describe genuine edits/final verification, so add a versioned immutable expected revision chain and trusted effect receipts before productive work. These changes are proposed, not implemented. No replacement task engine or broad dependency redesign is recommended. [Architecture](ARCHITECTURE.md), [lifecycle](TASK-LIFECYCLE.md).

## Verified versus assumed APIs

| Claim | Evidence level / limitation |
|---|---|
| OpenCode installed version/generation | Actual CLI 1.18.25 and opencode-ai package metadata; compared official V1/V2 packages |
| V1 HTTP/SDK/ACP capabilities | Official docs researched; exact 1.18.25 schema/behavior not exercised |
| V2 SDK/config distinction | Official V2 docs; excluded from installed V1 design |
| Local Ollama inventory/version/residency | Actual read-only daemon responses; no generation/cancel/unload tested |
| Chat/tool proposals/keep-alive/provider compatibility | Official Ollama docs; implementation conformance and quality pending |
| Containment, stop proof, provider gateway, revision-chain/evidence additions | Proposed WF contracts; not existing vendor capabilities and not verified implementations |

Research sources are linked at their supporting claims in [integration](OPENCODE-INTEGRATION.md), [security](SECURITY-BOUNDARIES.md) and [provider](MODEL-PROVIDER.md). Rolling documentation was accessed 19 October2026. No third-party API tutorial or community security claim substitutes for official evidence. Route/config assumptions fail closed until pinned conformance tests.

## Critical decisions and limitations

User/UI and broker are the only approval authorities. Model/project/tool text never grants access. WF policy and OS containment are separate. Runtime gets no host root, executor, credentials or user server session. Native runtime requests do not map to WF grants automatically. Exact effect dispatch, root handles/hashes, denial-by-default network, isolated config and stop proof precede live tools. Independent evidence, not an agent narrative, decides verified completion. Restart revokes everything and inspects unknown effects without replay.

One model lease, 4k initial context cap, measured ≤8 GiB aggregate incremental footprint and ≥4 GiB admission headroom; no invented throughput. VM cost and shared-daemon cancellation can make the recommendation infeasible. Full risks/open decisions/closure responsibilities are in [RISKS](RISKS.md). None of these controls is claimed implemented or OS-verified.

## Milestones and readiness

| Milestone | Permitted design objective after separate approval | Hard prerequisite |
|---|---|---|
| 1B.1 | Native runtime/session transport with deterministic fixtures | Pin/version contract; live launcher disabled |
| 1B.2 | Project roots, broker capabilities, patch/revision policy, containment | Execution-mode ADR, actual adversarial OS evidence before live tools |
| 1B.3 | Ollama provider and scoped runtime inference gateway | Artifact/protocol/cancellation/resource acceptance |
| 1B.4 | Independent contained build/test evidence | Actual macOS-capable execution boundary and exact command approval |
| 1B.5 | Real disposable-repository coding flow | All preceding applicable gates; never WesleyFlow first |

Each milestone's modules/interfaces/dependencies/security/scope/tests/acceptance/failure/rollback are in [implementation plan](IMPLEMENTATION-PLAN.md). [Acceptance matrix](TEST-AND-ACCEPTANCE.md) separates deterministic policy fixtures from real provider/runtime and OS containment evidence.

## Historical verification and this task's delivery checks

Inspected existing remediation execution records: final-debug.json, final-release.json, final-full.json and final-replay.json report exit0. Remediation report records 63 functions/258 concrete cases, zero failed/skipped, plus six crash seeds and 12 recovery/reopen runs. Those are **historical Phase1A evidence**, not new Phase1B tests. [Remediation report](../PHASE1A-REMEDIATION.md), [existing evidence](/Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1A-Remediation).

No application build/test, real API integration, inference, containment attack or generated-code execution was run here. Delivery validation checks exactly nine new Markdown files, local links, unchanged pre-existing tracked-file SHA256 hashes and unchanged HEAD. The 54-file baseline was captured before writing; delivery validation exited0: exactly nine new Markdown files, zero broken local links, all 54 pre-existing tracked files byte-identical, unchanged HEAD, and Git status containing only the nine untracked Docs/Phase1B files. Production/test/project/AGENTS/historical docs stay unchanged. No staging, commit, push, new repository, install or Phase1B.1 implementation.

**Stop: documentation delivery only.** Ready to review/authorize bounded 1B.1 fixtures separately; not ready to enable a live coding agent or declare Phase1B complete.


### Final document validation

The preservation/link/inventory check ran successfully (exit0). The final delivery remains unstaged and uncommitted: nine new documentation files only. No existing tracked file or HEAD changed. Inspection of the final wording also confirmed coordinator intent persistence precedes broker effect dispatch; no adapter receives direct persistence/execution authority by implication. This check validates document consistency and scope, not an implemented integration or security mechanism.
