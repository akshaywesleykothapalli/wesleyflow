# Coding task lifecycle and durable results

19 October 2026 · Proposal-only architecture adopted; preserve Phase1A semantics. New contracts remain documentation, not implemented additions.

## Sequence and ownership

1. Trusted UI selects a registered project and reviews requested context/model/offline mode. Registry revalidates root identity and acquires the global/project lease. No model-driven project selection.
2. Submit a bounded immutable proposal task using existing admission ordering: durable initial transaction plus open admission gate before acknowledgement. No acceptance after shutdown or duplicate task ID. Planning/inference is a scoped inspection operation whose approval shows disclosed bytes, selected artifact and limits; it grants no file effects.
3. Coordinator enters planning → awaitingApproval(resumePhase: running). Trusted UI issuer approves the exact operation; coordinator validates, persists intent, consumes and dispatches through the restricted adapter. An inference request is created only within this approved resource/context scope, never simply because a view opened.
4. ModelProviders owns the direct local inference request, lease and bounded progress. It returns a strict CodingProposal, not tools/commands. Workspace validates it against the trusted snapshot and policy. Further context requires separately scoped consent. CodingAgents remains disabled optional fixture infrastructure, outside this primary flow.
5. Workspace validates a final structured proposal against the baseline snapshot and computes expected post-snapshot. UI displays base/current hashes and diff. A successfully completed proposal task is labeled **proposal prepared**, not code implemented. Selected context/patch contents remain transient unless retention was explicitly approved.
6. User submits a new linked immutable application task with exact per-file operations, total workflow-family budgets and required independent verification. Revision/effect contracts must first be extended as described in [architecture](ARCHITECTURE.md). Current fixed-revision TaskPlan is insufficient for this step. Changed plan/command/target → new digest and approval, never mutate pending work.
7. Each application operation independently enters awaitingApproval. Coordinator commits intent before dispatch; broker validates/redeems final dispatch authority, rechecks handles/hashes and applies only approved bytes. Record per-file disposition and actual resulting snapshot. Any conflict/partial/uncertain result stops the chain, reports inspection required and withholds automatic repair.
8. After all expected effects, executionDone → verifying. Independent VerificationRunner checks actual receipts/post-state against the declared verification scope. File-content verification does not execute commands. If the task requires build/test success, a trusted fixed command plan, separate tested subprocess containment, exact approval and actual exit/artifact/test evidence are mandatory; without them the required verification fails/incompletes. Never downgrade that requirement to file-content checks.
9. Only committed, complete, matching evidence permits verificationPassed → succeeded. Agent text, idle, HTTP success, an empty test run or a diff alone never do. Coding application tasks cannot omit verification to take noVerificationDone. Proposal-only tasks may explicitly have no code-verification requirement and must retain their distinct presentation label.

No new lifecycle states are proposed. Session substatus (starting/streaming/abort requested/stop confirmed/uncertain) is adapter metadata, never a parallel authority to complete a task. Preserve denial→cancelling→cancelled; typed failure with resources→cancelling(failed cause)→failed(original cause); verification approval resumes verifying. Terminal outcomes remain immutable.

## Time, counts and backpressure

One active productive task globally, at most 16 waiting. Alias/nested roots share a lease. Across a linked coding workflow family: at most 20 inference turns, 50 proposed changes/context requests, two explicitly authorized retries, 15 minutes productive execution excluding approval waits, 5 minutes each process/operation, 5 minutes approval TTL. No child-task/continuation reset. Proposed provider limits can be lower. Count rejected proposals/hidden runtime turns; if upstream cannot enforce/observe the bound, stop the session rather than assume compliance.

ContinuousClock-derived monotonic deadlines are authoritative. Persisted timestamps are diagnostic only. Check after every await and at final dispatch/result acceptance; completion must be strictly before the deadline, including verification. Watchdog delivery is a wakeup, not authorization. Cancellation increments generation and revokes policy before waiting for persistence. Late completion is bounded sanitized diagnostics only, never outcomes, success or lease release for another generation.

Progress is lossy/coalescible and ephemeral; approval decisions, intent, outcome, evidence reference and terminal events are durable/non-droppable. Proposal byte/depth/count limits are in [contracts](PROPOSAL-CONTRACTS.md); old fixture SSE limits remain in [protocol](PHASE1B1-PROTOCOL.md) for optional infrastructure. Semantic overflow/disconnect becomes a typed protocol failure and cleanup; never silently ignore a permission request. UI observation must unregister cancelled continuations/streams.

## Cancellation and shutdown

Stop admission/dispatch; increment generation; revoke grants; cancel the exact inference/stream and assess provider settlement. No OpenCode abort or worker launcher is active. If a future separately authorized operation owns a helper/guest, terminate only that owned resource and independently settle its provider request. Close/drain pipes concurrently, capture at most 1 MiB combined while continuing to drain. Graceful 2 s then escalation 3 s, sharing the coordinator's 5 s total cleanup budget rather than starting serial five-second budgets.

Return `.stopped` only with proof that every owned execution resource is released and no owned descendant can act. Per-resource evidence includes worker identity/start identity, wait/termination status, guest stop where applicable, descriptor/stream closure and provider lease settlement. `.stopped` still says nothing about which modifications applied. Unknown or survivor → `.uncertain`, failed cleanup and quarantined conflicting lease; bounded UI shutdown may return while uncertainty remains. Never interpret OpenCode abort true, URLSession cancellation or task cancellation as kill confirmation.

The existing coordinator bounds reporting when persistence stalls, retains underlying writes and exposes late receipts. Do not await the diagnostic waitForPersistenceSettlement in shutdown. Preserve the difference between shutdownCompleted, physical cleanup and durable terminal acknowledgement. No adapter may block the coordinator's executor with synchronous process/network/store work.

## Persistence and crash matrix

Reuse atomic state/event and sequence CAS; do not serialize grants, worker handles, credentials or resumable authority. Add versioned sanitized session/descriptor/evidence metadata through an explicit migration decision; missing new fields must not destroy old v1 stores. A separate artifact store needs intent/reference ordering and reconciliation, not an independent unaudited success database.

| Crash/failure point | Required restart behavior |
|---|---|
| Before initial admission save | No acknowledged task/effects; preserve unknown commit if acknowledgement lost |
| After intent before dispatch | Interrupted; inspect intent; never assume dispatch did/did not occur |
| During staged/per-file replacement | Record/reconcile original and expected hashes per file; partial/uncertain remains visible; no replay/automatic rollback |
| After effect before outcome save | Effect potentially applied; user inspection required, never retry automatically |
| After artifact publication before DB reference | Orphan quarantined until ownership check; no inferred success |
| DB reference but missing/corrupt artifact | Evidence failure; no verified completion claim |
| Cancelling with live helper/provider | Invalidate old authority; block conflicting work until owned resource reconciliation; do not kill by stale PID alone |
| Persistence stuck/late commit | In-memory uncommitted failure; actual durable state on restart decides recovery; late acknowledgement never replaces emergency terminal status |
| Already terminal with unresolved intent | Keep terminal state and inspection flag; never prune as resolved |

Startup interrupts all nonterminal states (including cancelling), clears pending approvals and begins a new broker session. Do not reconnect/replay a persisted OpenCode session; historical IDs are diagnostic. A surviving runtime has no host effect capability; its isolated resources still need explicit reconciliation. Retry requires a new linked task, new snapshot, fresh approvals and remaining family budget. Destructive retry is never inferred from an interrupted ledger.

## Outcome reporting

Report separately: proposed changes, actually applied files, unknown dispositions, commands attempted, exits/signals, tests discovered/executed/passed/failed/skipped, captured/truncated bytes, input/final snapshots, stale evidence, cleanup and durability. Storage failure, policy denial, conflict, provider unavailable, protocol mismatch, resource pressure, timeout, verification failure and incomplete cleanup need distinct safe messages. Raw runtime errors may contain secrets; expose a redacted diagnostic reference, not unchecked text. Independent success is narrower than “agent said done.”
