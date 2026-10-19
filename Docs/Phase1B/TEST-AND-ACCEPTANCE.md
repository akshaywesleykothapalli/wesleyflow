# Tests and measurable acceptance gates

19 October 2026 · Specification, not new test execution evidence.

## Evidence levels

D = deterministic unit/component with fake clock/executor/HTTP server; R = real local provider/runtime adapter; O = actual OS containment/adversarial execution on an accepted worker; E = end-to-end disposable repository. D proves policy logic only. A denied mock request cannot demonstrate that native OpenCode, shell, build scripts or escaped children lack OS authority. No R/O/E gate was executed in this documentation task.

Preserve the 117-pair/27-edge lifecycle oracle and all current Domain/composition/Phase1A regressions. Historical remediation artifacts report 258 cases; future runs must report discovered functions and expanded cases independently, zero failures and no silently skipped mandatory tests. Build Debug and Release and run the complete suite using explicit full Xcode per authorized implementation milestone, retain argv/cwd/environment allowlist/times/exits/result bundles and source hashes. A zero-test selector is not acceptance. macOS26/Xcode26.3 compatibility remains a separate unmet GC gate.

## Scenario matrix

| Scenario | Level and fixture | Required assertion |
|---|---|---|
| Permission denial | D, all operation classes | Zero executor/native dispatch, denial audit and legal cancelled transition |
| Expiry/revocation | D, deadline -1/0/+1; cancel before/after await; restart | Exact boundary expires, one-use consume; no effect after revoke; old session rejected |
| Forged/reused capability | D/O, public identity token, duplicate redemption | Cannot obtain dispatch; exactly one effect at most |
| Project selection | D/O, wrong repo ID/root replaced/bookmark stale | Zero context disclosure/effect; conflict visible |
| Outside-root access | O, sentinel outside fixture and home/network targets | Direct native read/write attempts denied by OS; sentinels unchanged; access result recorded |
| Symlink/traversal | D/O, intermediate/final symlink swaps, ../absolute, hardlink, alias/nested root | Deny unsafe path; no sentinel read/write; aliases share lease; race loops ≥1,000 attempts |
| Command rejection | D/O, unknown executable/argv, shell metacharacters, injected env/hook | No launch; allowed build fixture's child escape still OS-denied |
| Prompt injection | D/E, five hostile repo/tool-output cases | Zero policy/provider/root changes, zero credential access/network; no model approval accepted |
| Malicious runtime config | O, project/global plugin/MCP/LSP/formatter/autoapproval attempt | Nothing activated; no host config loaded; effective provenance matches pinned manifest |
| Concurrent sessions | D/R, 32 concurrent submissions, duplicate IDs, foreign events | One productive session/lease; FIFO/capacity honored, foreign results rejected |
| Stream safety | D, split/invalid UTF-8/oversize/duplicate/reordered/drop/unknown terminal | Bound buffers, typed failure, no lost semantic event or automatic prompt resend |
| Cancellation | D/O/E, blocked provider, fork/detach fixture, false abort ack | No post-revoke dispatch; stop confirmed or uncertain/quarantine; never infer effect disposition |
| Timeout | D/R/O, exact boundaries and delayed watchdog | Observed completion at/after deadline cannot pass; late result diagnostic only |
| Agent crash | R/O, owned child/guest killed at each lifecycle phase | Typed failure, resources assessed, no replay/false success |
| Provider failure | D/R, absent daemon/model, incompatible response, overload/offline | Visible unavailable/failure, zero cloud/pull/auto-start, no blind retry |
| Shared daemon | D/R, foreign residency/inference | Reject unaccounted admission; never terminate other's process/model request |
| Memory pressure | D/R/O, synthetic notifications plus actual measured workload | Immediate heavy admission stop; sustained 2 s triggers cleanup within 5 s or quarantine |
| Shutdown | D/O, approval wait, inference, child, stalled history | Admission closed first; report by 5 s + ≤250 ms harness scheduling allowance; uncertain worker/write retained |
| Persistence failure | D/real SwiftData, before/after save/stall | Zero new effects, atomic state/event or explicit unknown ack; emergency uncommitted status honest |
| False success | D/E, agent says done; build exits nonzero | Task never verified succeeded |
| Missing evidence | D/E, no tests/empty/missing/corrupt result/log overflow | Reject verified completion; record incomplete/truncated reason |
| Revision drift | D/E, external edit before/during verification | Conflict/stale evidence; no global weakening of hash checks |
| Partial patch/crash | D/O/E, before/after each replace/outcome | Per-file disposition, unresolved intent kept; no automatic rollback/replay |
| Restart | D/O/E, six existing seeds plus live worker/artifact boundaries | No restored grant/session/timer; interrupted state, zero automatic productive calls; second reopen idempotent |
| Quota/privacy | D/real store/O, 90/100 MiB limits and runtime cache | No new productive admission over reserve; no raw content by default; active/uncertain evidence never pruned |
| Observation/resource retention | D/R, 100 subscribe/cancel and 20 session cycles | Exactly-once disposal; owned handles/tasks settle or quarantine; no monotonic retained-resource growth |

Actual OS tests must use benign prewritten fixtures, not execute arbitrary AI-generated attacks on the host. Record worker entitlements/signatures, guest configuration/mounts/interfaces, child identities, attempted syscall/action results, before/after sentinel hashes, egress observations and cleanup results. A log saying “denied” without an independently attempted access is insufficient. No automatic rerun after a failed escape test.

## Gate definitions

| Gate | Milestone exit | Measurable condition |
|---|---|---|
| B1 | 1B.1 fixture adapter | Every selected request/event/error fixture decoded/rejected correctly; 64 KiB frame/256 KiB buffer caps; cancellation/deadline/disposal assertions pass; no live effects; actual Debug/Release/full tests zero failures |
| B2 | 1B.2 effect boundary | All authority/root/config/OS matrix rows pass with zero unauthorized reads/writes/launches/egress; ≥1,000 race attempts without escape; immutable before/after chain tested; ordinary descendants stopped ≤5 s or feature fails closed |
| B3 | 1B.3 inference | Pinned-provider/gateway conformance plus 30-minute target-device workload and frozen 20-task corpus meet [model thresholds](MODEL-PROVIDER.md); ≤8 GiB aggregate, ≥4 GiB admission headroom; no OOM/sustained critical pressure; cancellation/unload settled or quarantined ≤5 s |
| B4 | 1B.4 verification | Known pass/fail/zero-test/stale/timeout/partial-artifact fixtures classified correctly; all required actual commands/evidence bound to final snapshot; zero false verified success; command containment and cleanup proven |
| B5 | 1B.5 integrated flow | Three fresh disposable copies (success, intentional failure, cancellation) plus restart/hostile matrix; correct outcomes and no unauthorized effect; prior gates remain green; source, command and artifact evidence retained |

Physical-stop acceptance requires released resources, not merely a bounded uncertain report. Honest quarantine is correct failure behavior but does not pass a claim that the adapter stopped successfully. Gate rows are mandatory; if the selected isolation/provider architecture cannot pass, the corresponding feature remains disabled rather than “accepted with tests deferred.” Resource percentages, model inventory or a green HTTP fixture cannot substitute for B3.

## Verification record and failure handling

For each run record source revision/dirty diff, binary/artifact/schema hashes, exact toolchain/host, commands, exits/signals, discovered/executed/failed/skipped counts, scope/grant digests (not secrets), revisions, time/memory/pressure measurements, output truncation and cleanup observations. Raw source logs are opt-in; default durable report uses sanitized hashes/summaries. Keep expected failing fixtures distinguished from failed acceptance checks. Unexpected test failures block the milestone and get an accurate failure report; no success wording from planned checks.

Compatibility GC still requires full Xcode26.3/Swift6.2.3/macOS26.2 SDK on supported host and actual macOS26.0 runtime; primary Xcode27beta/Swift6.4/SDK27 host results do not close it. Stable release/signing/consent and power-loss durability are also separate. The design authorizes neither builds/tests nor adversarial execution today; only read-only environment checks and document validation were run.
