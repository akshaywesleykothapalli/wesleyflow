# Phase 1A implementation record

18 October 2026. Scope: the user's explicit Phase 1A authorization. The approved Phase 0A packet, traceability, consistency report and risk register were read and preserved. Their historical approval/stop wording is superseded only for this authorized task foundation. Phase 1A does not enable later effects.

## Modules and composition

`Domain` owns Sendable/Codable values, lifecycle, immutable workflow ID/version snapshots, operation digests/revisions, sanitized events and consumer ports. It imports no frameworks. `TaskExecution`, `Persistence` and `SystemOperations` each depend only on Domain, never on one another. The app composition root imports the concrete modules and supplies dependencies. There are no external packages.

`AppComposition.makeTaskServices` requires an explicit store URL and injected execution/verification implementations. It opens durable history, composes the broker, performs startup recovery and returns services plus the trusted approval authority. Closing requests coordinator shutdown before closing history. There is no production executor or automatic application-data-store creation. The native shell exposes foundation status; task/approval interaction is currently programmatic, exercised by composition tests. This is service infrastructure, not an operational coding or workflow product.

## Orchestration and authority

The coordinator actor owns one global active lease and FIFO of at most 16 waiting tasks. Immutable plans have 1–50 total operations, optional final verification, opaque workspace/revision identifiers and at most two explicitly linked retries. Retry creates a new task ID and preserves workflow ID/version; nothing resumes automatically. There is no inference/planning loop in this phase, so the architecture's agent-turn budget has no active integration.

Each operation requires a fresh one-use approval bound to the task, operation, workspace, revision, digest, generation, session and expiry. Only trusted MainActor composition receives `UserApprovalAuthority`; the coordinator receives the narrower policy port. This is a module/API boundary, not OS isolation against malicious code in the same process. Model, project and tool text have no approval entry point. File writes, processes and automation fail closed. Inspection/verification are typed interfaces with deterministic test implementations; there is no filesystem inspection adapter yet, and opaque workspace IDs are not filesystem capabilities.

A serialized mutation gate protects state/event commits across actor suspension. State and intent are committed before acknowledgement/dispatch. Final approval consumption checks expiry and execution deadline; worker ownership is installed before another await. Workers check generation/cancellation before calling the injected provider. Verification success requires matching digest/revision and a committed verification event before the terminal transition. Snapshots, ordered event reads and state waits provide verification interfaces.

Timers use an injected clock: five minutes per approval, five minutes per operation and fifteen minutes cumulative execution excluding approval waits. The production clock anchors monotonic elapsed time to an epoch timestamp; tests advance virtual time through explicit scheduling barriers. Actor-held worker, driver and timer handles supervise finite work without detached tasks. Cancellation immediately changes generation, cancels handles, revokes authority, starts provider cleanup independently of history writes, then records cancellation. Original worker ownership remains retained until cleanup acknowledgement. A five-second uncertain cleanup quarantines the lease and blocks scheduling; late callbacks cannot promote success. Failed saves publish visibly uncommitted failure and block further effects. Explicit shutdown prevents new dispatch and requests cancellation.

## Storage and recovery decisions

SwiftData schema v1 privately stores JSON task snapshots and event payloads in one explicit state/event transaction. CloudKit and autosave are disabled. A private serial model executor owns context access; asynchronous construction occurs off the caller actor. Framework model/context objects never cross Domain ports. Optimistic sequences, unique audit keys, immutable plans and contiguous audit validation reject stale/duplicate writes. An exclusive local lock prevents two repository writers.

A schema marker and migration plan establish versioning. No upgrade migration is implemented for this initial schema. Unknown versions and corrupt headers are rejected while preserving the store; there is no deletion/reset fallback. Before-save failure rolls back; a fault after a successful save is treated as an uncertain acknowledgement and is never retried blindly.

On startup, all nonterminal tasks become interrupted, approvals are removed, and original prior state is retained. Unresolved intents require inspection and quarantine; no work or grant is replayed. Reopening again preserves the interrupted record without appending another recovery event.

Default admission accounts for files in the dedicated store directory, with a 100 MiB budget and 10 MiB reserve for outcomes/cleanup/recovery. Projected writes include encoded payloads and a page allowance. This is conservative application admission accounting, not a hard filesystem quota: SQLite/WAL growth can exceed the estimate. Dedicated-directory ownership is required. Explicit maintenance prunes safe terminal records older than 30 days and deletes their audit rows; active/unresolved/inspection-required records are protected. There are no source, prompt, command-output or content artifact stores in 1A. Actual filesystem allocation bounds, future migration/backup/export and artifact fault matrices require their later integrations and evidence.

## Engineering and verification arrangement

Swift tools 6.2 and Swift 6 language mode remain configured, with nonisolated core defaults and explicit MainActor UI. No upcoming-concurrency opt-ins were added. The native shared scheme runs app composition, exhaustive Domain and Phase1A bundles. Native test targets reference the package test sources directly; no duplicated test implementation is maintained. Package products retain automatic linkage. The Xcode project was reserialized as valid OpenStep property-list syntax, accounting for much of its formatting diff.

The completion report links actual command metadata, source hashes and result bundles. Full GC, GE and GR architecture gates remain separate: these deterministic executor tests do not establish filesystem containment, subprocess cleanup, real verification tools, target-OS feature compatibility or release readiness.
