# Phase 1B.1 completion report

Current architecture note (2A finalization): this is a historical phase record. [Proposal-only architecture](ARCHITECTURE.md) and the [adopted containment ADR](ADR-EXECUTION-CONTAINMENT.md) now govern delivery. OpenCode stays disabled; retained gateway/runtime references below describe optional infrastructure, not a requirement or authorization for revised1B.3. Original evidence and phase results remain unchanged.


19 October 2026 · Fixture-only coding-agent protocol foundation

Checkpoint follow-up: the original 349-case evidence below was reproduced. Final review added two regression cases and a narrow observer state fix; the latest total is 351 cases. See [final review and checkpoint](PHASE1B1-CHECKPOINT.md) for current results and the separately authorized local commit.

## Decision and scope

**COMPLETE for the authorized fixture-only Phase 1B.1 implementation and its available-toolchain verification.** Native OpenCode/Ollama execution, effective runtime configuration isolation, physical termination, OS containment and production integration remain **NOT TESTED / BLOCKED for live enablement**. No Phase1B.2 work, commit or push was performed. Separate authorization is required for any next milestone.

Final-source focused tests pass **48 functions / 91 concrete cases**. Complete native tests and independent replay each pass **111 functions / 349 cases**, zero failures or skips. Original 63 functions / 258 cases remain intact. Debug and Release builds pass. Exact commands, timestamps, exits, logs, bundles and matching source hashes are in [Evidence/Phase1B1](/Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1B1); accepted-proof.json correlates the final source and bundled fixtures with those five accepted runs.

## Repository inspection and preservation — COMPLETE

Started on main at `686a0af7aebdfb270ef3cfefc51ecb703d017e4a`. The working tree was **not clean**: the nine existing Docs/Phase1B design documents were untracked from the previous authorized task. There were no other nonignored changes. Captured SHA256 baseline for all 63 existing nonignored files before edits; preserved those nine documents byte-for-byte. Root AGENTS, the design packet, Phase1A remediation, manifest, Domain, task orchestration/permissions, persistence/cancellation/recovery and existing test assertions were inspected.

No full independent Nemotron 3 Ultra audit was found in repository filenames, including ignored evidence outside build directories. The eight findings supplied in the current task were used; this is not a claim to have reviewed an unavailable full audit. No legacy source or unrelated project was accessed.

## Implementation and architecture — COMPLETE

Added Domain/CodingAgentRuntime.swift with CodingAgentRuntime, SessionManifest, RuntimeSessionIdentifier, RuntimeEvent, RuntimePermissionRequest/Response, CancellationRequest, CleanupAssessment, RuntimeProtocolError and SessionCorrelation. Added RuntimeLaunchManifest as inert bounded data. These are Sendable generic values, not provider/vendor objects or security capabilities. RuntimePermissionResponse can express rejection only. Neither IDs nor model-generated permission proposals confer authorization.

Created populated CodingAgents and CodingAgentsTests Swift package targets plus a native Xcode fixture test bundle. CodingAgents depends only on Domain; platform serialization and hashing stay in its adapter. No Workspace/ModelProviders/Verification empty targets, new external dependency, production runtime composition or TaskCoordinator redesign. Existing task types, broker, SwiftData schema and all Phase1A source/tests remain byte-identical. All 86 pre-existing Xcode project objects preserve their settings; only new target/group membership was added.

The injected HTTP abstraction implements one exchange, explicit deadline/cancellation, incremental size/status/content-type/JSON checks, sanitized errors and owned disposal. There is no native network backend or credential lookup. The SSE parser handles chunking, UTF-8/BOM, CR/LF variants, multiline/empty data, IDs, comments, EOF and bounded errors. The fixture actor correlates task/operation/session/generation/connection epoch, owns lifecycle/observation/disposal, rejects concurrent chunk ingestion and foreign/stale sessions, deduplicates JSON event IDs and simulates reconnect without resending work. Late input cannot promote a terminal session.

Critical queue overflow fails the session as uncertain, retains accepted critical entries for draining, and exposes an inspectable typed error. Progress is explicitly lossy/coalesced. Limits and the aggregate encoded-payload budget are documented in [protocol contract](PHASE1B1-PROTOCOL.md). **NOT TESTED:** allocator/RSS peak and future live worker/model resource budgets; encoded payload limits are not an OS memory cap.

## Verified API sources and provenance — COMPLETE static capture

The installed package metadata says opencode-ai **1.18.25**; darwin-arm64 package also says 1.18.25. No OpenCode invocation, including --version, occurred during this phase. Static binary SHA256:

`88eed7b0c2431162422cb0625aa68a55239970446951e4c9aad6a4f1fbc232b9`

Official tag v1.18.25 resolves to commit **cb7d8b2f5e44876ef98b661dc10590c915af3a9f**. Four captured files were re-fetched at that immutable commit and matched tagged bytes. [Official pinned source](https://github.com/anomalyco/opencode/tree/cb7d8b2f5e44876ef98b661dc10590c915af3a9f), [local provenance](Contracts/OpenCode-1.18.25/provenance.json).

| Captured source | SHA256 |
|---|---|
| packages/sdk/openapi.json | c0af493bae06c8f50ae05474921570eb05f301c92a5f68f6a6365f530b719ad7 |
| packages/opencode/src/config/config.ts | 87a9071af1ddb04d65947dba49be3fb4c94ecf63e120f17ce46ee81ff25dd45a |
| packages/opencode/package.json | b5ffecdcf0cd3f3dc981a754641803bfb63ee4e4602e40c164bf22ede75de325 |
| MIT LICENSE | 625f0f619133f89bbbb2abe37369613dfa1885eba1e50d02170deb62bb42cb6b |

The OpenAPI info.version is 1.0.0, independently of release 1.18.25. The pinned schema distinguishes current `/permission/{requestID}/reply` (`reply`) from deprecated session permission response (`response`). The adapter encodes rejection for the former only. It decodes a narrow classic Event subset with id/type/properties, not an invented general V2 API. Captured synthetic fixtures are independently checked against bundled schema fragments. Full public source/specification references retain their license and hashes; they contain no user credentials or real session traffic.

**NOT TESTED:** the installed binary's actual HTTP behavior, authentication, server startup/connection, session creation request binding, the rest of the Event union, upstream replay guarantees or binary reproducible-build correspondence. Unsupported events fail closed. No assertion equates SSE checkpoint IDs with JSON event IDs. Exact source capture did not require running OpenCode, so no isolated live-start authorization was requested or needed.

## Configuration and provider contract

**COMPLETE:** inert launch manifest and [future gateway contract](PHASE1B1-PROTOCOL.md#future-provider-gateway--documentation-and-inert-fixture-only), with [synthetic gateway fixture](Contracts/gateway-fixture.json). These describe request/model/context identity, bounded stream/tool proposals, cancellation/deadline propagation, safe errors and trusted provider-lease ownership; they are not asserted vendor wire messages.

**DEFERRED / live BLOCKED:** runtime configuration isolation. Pinned configuration source references global/custom/project/directory/inline/managed loading, command/agent/plugin discovery and dependency setup. A custom config does not establish isolation. Config/cache/data/cwd/endpoint/authentication fields are data only; personal config/auth contents were not opened. No launcher, hooks, MCP, LSP, plugin or inference path was added or started. Future gateway implementation belongs to 1B.3, not this milestone.

## Independent audit disposition and concurrency review

| Supplied finding | Classification | Evidence / disposition |
|---|---|---|
| Missing runtime Domain interfaces | CONFIRMED at baseline | Added consumed generic contracts and compile-time Sendable/conformance tests |
| Missing module dependencies | CONFIRMED at baseline | Added CodingAgents→Domain and concrete test target; package/Xcode graph checks pass |
| Unverified OpenCode V1 schema | CONFIRMED at baseline | Resolved static source provenance/selected fixtures; live binary conformance remains NOT TESTED |
| Missing SSE buffering/delivery semantics | CONFIRMED at baseline | Bounded parser/queue, coalescing, critical-overflow uncertainty and deterministic tests |
| Missing session correlation | CONFIRMED at baseline | Full identity/generation/epoch checks before and after suspension; foreign/reconnect tests |
| Missing permission event models | CONFIRMED at baseline | Untrusted request and reject-only response; no authority issuer/executor access |
| Unverified runtime config isolation | DEFERRED | Static source investigated, no runtime launch; separate security gate remains mandatory |
| Possible existing continuation/shutdown races | NOT REPRODUCED | Inspected current Phase1A actor ownership/one-shot continuation removal; unchanged regressions pass full+replay. No proof of every possible interleaving is claimed |
| V2 SDK/launcher/OS containment implementation | NOT APPLICABLE to fixture-only change | No V2 SDK, live launcher or OS containment implementation; future gates remain open |

No CheckedContinuation was replaced by UnsafeContinuation. No lock, detached task, unchecked Sendable or concurrency-warning suppression was introduced. New actor tests cover shutdown/terminal delivery during observer registration, shutdown during input's clock await, concurrent receive ordering and stale suspended input after reconnect. Work/disposal handles remain owned. Fixture cleanup is separate from task success/effect disposition/OS stop.

A concrete defect was found in the **new adapter during this task**, not inherited Phase1A: it initially equated SSE ID and JSON ID. The new transportCheckpointIsIndependentFromJSONEventIdentity test reproduced duplicateConflict before the fix: checkpoint-regression-before exited65, 3 functions, 1 failure. Removed the unjustified equality check, retaining JSON-ID/digest deduplication. The final regression and complete suites pass. No tests were deleted or weakened.

## New tests and retained Phase1A verification — COMPLETE

| Area | Actual coverage |
|---|---|
| HTTP | Success/chunking/disposal, one exchange/no replay, bad status/type/JSON, incremental oversize, held-request timeout/cancel, delayed-watchdog boundaries, safe error mapping and fixture input limits |
| SSE | 34 split positions, single-byte UTF-8/BOM, multiline/empty data, comments/heartbeat, CR/LF variants, persistent/reset/NUL IDs, retry metadata, malformed/truncated UTF-8, EOF, callback cancellation and size limits |
| Sessions | Creation/state/identity, duplicate/conflicting IDs, foreign input, reconnect/epoch fencing, slow consumer/coalescing, ordered critical delivery/overflow, byte/identity limits, cancellation/uncertain cleanup, deadline boundaries, repeated shutdown and controlled reentrancy |
| Domain/contracts | Sendable/protocol compilation, bounded input validation, no approval decision constructor, inert manifest, pinned synthetic schema validation, malformed permission/retry rejection and independent SSE checkpoint semantics |
| Existing Phase1A | Original cancellation disposition, approval expiry/revocation, no duplicate execution, save faults/reopen/recovery, stalled-store bounded shutdown and observer cleanup execute unchanged in full suite and replay |

Tests use controlled clocks, held continuations and explicit fixture notifications; no arbitrary sleeps. Existing real SwiftData tests were run. The historical six external abrupt-exit helpers were **not rerun** in this phase; their prior evidence remains historical. This task does not claim a new OS crash/kill or power-loss campaign.

## Actual verification results

| Accepted execution | Exit | Result |
|---|---:|---|
| accepted-focused | 0 | 48 functions / 91 expanded cases; 0 failed/skipped |
| accepted-full | 0 | 111 functions / 349 cases; 0 failed/skipped |
| accepted-replay | 0 | Independent test-without-building; same 111 / 349; 0 failed/skipped |
| accepted-debug | 0 | BUILD SUCCEEDED, includes CodingAgents fixture test target |
| accepted-release | 0 | BUILD SUCCEEDED, includes CodingAgents fixture test target |
| Native result summary/tree extraction | 0 | Counts independently derived from Test Case/Arguments leaf nodes; runtimeWarnings empty |
| Toolchain/settings/package/preservation checks | 0 | static-verification.json; zero unexpected dependencies/edges; old settings preserved |
| Diff and final preservation checks | 0 | No whitespace errors; scope/preservation evidence retained |

Every accepted run records final matching code hashes; Debug/Release bundled JSON fixture hashes match source. Earlier focused/integration runs also passed but are not used as final-source proof. The intentional failing regression remains preserved. Two inspection-helper issues (metadata filtering and mixed JSON/stderr parsing) were corrected; an initially sandbox-restricted result-bundle extraction exited64, then native-approved extraction succeeded. Those were not application/test failures.

Lane: explicit `/Applications/Xcode-beta.app/Contents/Developer`, Xcode27.0 beta build27A5237l, AppleSwift6.4 swiftlang6.4.0.30.4, SDK27.0, host macOS27.2 build26B5112a. Effective arm64/macOS26.0 deployment, Swift mode6.0, strict-concurrency complete, core nonisolated; no extra upcoming flags. All fixture modules compile under these settings with no Swift concurrency warning. Nonfatal unused-AppIntents metadata and host linkd diagnostics remain in raw logs; none was suppressed. Thread Sanitizer/Instruments, full Xcode26.3/Swift6.2.3 and actual macOS26.0 compatibility lanes are NOT TESTED, not implied by these builds.

### Exact build/test commands

Run from `/Users/akshaywesley/Developer/WesleyFlow`, all with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. The shared argv prefix is:

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Phase1B1 -disableAutomaticPackageResolution -skipPackageUpdates
```

Append each row's exact suffix (complete argv arrays also reside in the corresponding JSON):

| Record | Suffix |
|---|---|
| accepted-focused.json | `-configuration Debug -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1B1/accepted-focused.xcresult -only-testing:CodingAgentsTests test` |
| accepted-full.json | `-configuration Debug -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1B1/accepted-full.xcresult test` |
| accepted-replay.json | `-configuration Debug -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1B1/accepted-replay.xcresult test-without-building` |
| accepted-debug.json | `-configuration Debug -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1B1/accepted-debug.xcresult build` |
| accepted-release.json | `-configuration Release -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1B1/accepted-release.xcresult build` |

Static command argv/exits are in static-verification.json. Each summary/tree extraction has its own command JSON; full source/checksum URLs are in provenance.json. Native approvals were used for project writes, dependency-free static source capture, Xcode verification and result extraction. No prompt was bypassed.

## Requirement disposition

| User section | Status | Practical limit |
|---|---|---|
| 1 Repository inspection/preservation | COMPLETE | Full independent audit unavailable locally, explicitly disclosed |
| 2 Audit review/classification | COMPLETE | Supplied findings classified above; unproved old races not rewritten |
| 3 Contract source verification | COMPLETE | Immutable tagged source verified; live executable conformance NOT TESTED |
| 4 Minimum Domain contracts | COMPLETE | Data/proposal identities only; no effect authority |
| 5 Package structure | COMPLETE | One populated production adapter target and its concrete test target |
| 6 HTTP abstraction | COMPLETE | Injected equivalent byte transport; actual networking NOT TESTED |
| 7 SSE/buffering/delivery limits | COMPLETE | Bounded encoded payload/counts; measured allocator/RSS NOT TESTED |
| 8 Fixture session lifecycle | COMPLETE | No live session or production TaskCoordinator integration |
| 9 Inert launch manifest | COMPLETE | Effective runtime isolation BLOCKED/NOT TESTED |
| 10 Provider gateway contract | COMPLETE | Documentation/synthetic fixture only; implementation deliberately absent |
| 11 Deterministic tests | COMPLETE | 91 new cases, original 258 retained; no new external crash helper run |
| 12 Verification | COMPLETE on available lane | Older compiler/minimum-OS compatibility NOT TESTED |
| 13 Disabled security-sensitive features | COMPLETE | No live runtime/provider/effect/voice/automation/training activation |
| 14 Completion report | COMPLETE | This report and linked exact evidence |
| 15 Stop/no commit or push | COMPLETE | Phase1B.2 not begun; implementation remains unstaged/uncommitted |

No required fixture deliverable is left PARTIAL. The explicit BLOCKED/NOT TESTED entries apply to live/security/compatibility capabilities, which fixture success cannot establish.

## Files and Git state

Modified only four existing files: root AGENTS.md (current authorization), Packages/WesleyFlowCore/Package.swift (new populated targets/resources), WesleyFlow.xcodeproj/project.pbxproj and its shared WesleyFlow.xcscheme (new fixture test bundle). Added five production Swift files (one Domain/four CodingAgents), five test Swift files, two bundled JSON fixtures, five pinned public contract/provenance/license files, an inert gateway JSON fixture, protocol documentation and this report. Existing Swift source/tests, app composition/UI, approved architecture and nine uncommitted design documents remain unchanged.

Main/HEAD unchanged. No staging, commit, remote change, push or new repository. Final Git status/preservation, source review diff and full file inventory are in final-scope.json and git-final.txt under Evidence/Phase1B1; those sidecars are generated after this report. Original nine untracked docs remain untracked. Build outputs/raw evidence remain ignored.

## Security limits and Phase1B.2 recommendation

**Ready for review and separately scoped Phase1B.2 planning/implementation, not live coding enablement.** Live use remains held by the execution-mode ADR, demonstrated configuration/OS/network containment, root-bound broker-only capabilities and revision/effect receipts. Provider cancellation/lease/memory and independent command verification are later gates. These controls must precede file-changing or unrestricted tools; successful fixtures do not relax them.

No OpenCode/Ollama process/session, inference, project edits by an agent, arbitrary command launcher, plugin/MCP/LSP, browser/voice/system automation, model download or training was enabled. App still uses its honest foundation shell. Protocol/source references are not an approved executable configuration. Stop after Phase1B.1 and await separate authorization; do not automatically start Phase1B.2.
