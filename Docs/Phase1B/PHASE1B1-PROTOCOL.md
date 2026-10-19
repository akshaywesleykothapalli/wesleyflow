# Phase 1B.1 protocol contract

Current architecture note (2A finalization): this is a historical phase record. [Proposal-only architecture](ARCHITECTURE.md) and the [adopted containment ADR](ADR-EXECUTION-CONTAINMENT.md) now govern delivery. OpenCode stays disabled; retained gateway/runtime references below describe optional infrastructure, not a requirement or authorization for revised1B.3. Original evidence and phase results remain unchanged.


19 October 2026 · Implemented fixture foundation only. No live runtime/provider or effect dispatcher.

## Ownership and API surface

Domain owns generic Sendable runtime IDs, task/operation/generation/connection correlation, context/model/digest/deadline manifests, permission proposals, rejection-only responses, cancellation and cleanup values, typed errors and CodingAgentRuntime. All public constructors create data only, never authority. Existing TaskPlan, TaskLifecycle, approval broker and persistent model schema remain unchanged. CodingAgents imports Domain plus Foundation/CryptoKit for its own serialization/hash work. No adapter imports TaskExecution, Persistence or SystemOperations. App does not instantiate or import a live runtime; Xcode links CodingAgents into its dedicated fixture test bundle.

FixtureHTTPClient consumes an injected HTTPTransport, validates status/content-type/JSON/size, propagates cancellation and monotonic deadlines, maps unknown errors to sanitized typed transportFailure and issues one exchange only. There is no URLSession/network implementation, URL opener or credential lookup. A protocol-equivalent injected byte transport was selected instead of introducing a networking implementation that this scope cannot use. An ambiguous POST is never resent. Owned worker/disposal handles can outlive a bounded result if an injected backend fails to settle; cleanup stays uncertain and no second exchange is allowed. Actual native network behavior remains untested.

FixtureSessionManager is a one-session actor with a sealed FixtureSessionTransport. Its states are ready/creating/active/reconnecting/terminal. Runtime idle means idle only, not verified task success. Fixture resources are disposed exactly once; fixtureDisposed is explicitly not OS termination or a file-effect receipt. Cancellation/repeated shutdown join the same disposal assessment. Timeout and incoming-event acceptance use the injected TaskClock, recheck after suspension, and cannot promote an established terminal state. A receive gate rejects concurrent chunk ingestion instead of allowing chunks to overtake at a clock suspension. Connection epochs fence suspended old chunks; foreign session events cannot mutate another session.

Observation uses a single cancellation-aware checked continuation, or drains the bounded queue. New observations require active state before and after the clock suspension; disconnected readers fail with staleConnection. Previously accepted queued entries remain drainable. Registration rechecks state/queue after awaiting the clock; terminal/shutdown during that await cannot strand a waiter. No UnsafeContinuation, mutex, unchecked Sendable or detached task was introduced. Cancelling an active observer stops its dependent fixture processing; cancellation before registration cannot leave a stored continuation. The consumer owns processing after nextEvent returns; this API is not a durable acknowledgement protocol.

## Bounded transport and delivery

| Resource | Implemented maximum / behavior |
|---|---|
| HTTP request body | 256 KiB; path 1,024 bytes; identifier 128 ASCII bytes |
| HTTP timeout / response | Positive, at most 300,000 ms; response ≤256 KiB, checked incrementally |
| Sealed HTTP fixture storage | ≤64 chunks, each ≤256 KiB, aggregate ≤512 KiB; content type ≤128 bytes |
| SSE feed / frame | ≤256 KiB per supplied chunk; ≤64 KiB frame accounting; partial line retained only within the frame bound |
| Session event queue | ≤64 events and ≤256 KiB encoded-event accounting (including 256 bytes/event reserve) |
| Replay ledger | ≤256 event IDs, each ≤128 bytes plus 32-byte digest; exhaustion fails closed, no unsafe eviction |
| Permission proposal | ≤32 resources, ≤1,024 UTF-8 bytes/resource |
| Aggregate payload design budget | 2 MiB across the bounded fixture exchange/session components; bounds above keep retained encoded payload below this budget |

The aggregate figure is an encoded-payload design budget, not an allocator/RSS cap. Foundation JSON object overhead, Swift object/array capacities, transient copies and the test runner have not been instrumented. Limits bound both counts and byte payloads; they do not establish the later 8 GiB model/OS resource gate. A future network backend must enforce its own header/chunk allocation bounds before handing values to this API.

SSE accepts split bytes/UTF-8/BOM, LF/CRLF/CR, multiline/empty data, comments, persistent/reset IDs and numeric retry hints. Unknown SSE fields are ignored; malformed UTF-8 is rejected deliberately rather than repaired. An EOF discards an unterminated event per SSE framing; a session without an accepted terminal event becomes unexpectedEnd/uncertain. Retry hints are metadata only, never automatic replay instructions. Paired LF following CR is normalized; frame accounting is a parser bound, not an exact raw wire-byte quota.

Progress/status is explicitly lossy: a trailing noncritical event may be replaced by the newer update; noncritical entries can be evicted to make room for critical events. This preserves the accepted critical order. Permission/outcome/error/terminal categories are critical. If a critical event cannot fit after removing progress, receive throws criticalOverflow, session becomes terminal uncertain, prior accepted critical items remain drainable, and snapshot retains the sanitized failure even after the queue empties. No unlimited lossless delivery is claimed. Callers must stop dependent work on any protocol error. No real work is enabled here.

The release JSON event ID is the deduplication key, with payload digest conflict detection. SSE last-event-id is an independent transport checkpoint; no equality or server replay guarantee is assumed. Simulated reconnect increments the epoch, resets partial parsing, keeps the bounded duplicate ledger and does not recreate a session or resend a prompt. The manager is not an OpenCode resumption implementation.

## Pinned schema subset and remaining assumptions

[Release source](https://github.com/anomalyco/opencode/tree/cb7d8b2f5e44876ef98b661dc10590c915af3a9f) corresponds to tag v1.18.25 and package version 1.18.25. Complete public OpenAPI, configuration source, package metadata, MIT license and provenance hashes are retained under [Contracts/OpenCode-1.18.25](Contracts/OpenCode-1.18.25). Tests bundle a small independent schema subset and sanitized synthetic events, not recorded live traffic. The top-level OpenAPI info.version is 1.0.0 and must not be mistaken for the CLI release.

Only classic Event `id/type/properties` permission.asked, message.part.delta, session.status, session.idle and scoped session.error are normalized. Unknown events fail safely. This does not implement the entire large Event union, PermissionV2 wire events, server/global routing, session creation HTTP bindings, prompt submission, authentication or a production server client. The tagged schema itself includes some V2-named models; their presence does not make the installed product V2. Domain has no vendor-specific schema types.

Permission rejection uses the tagged `/permission/{requestID}/reply` body `reply=reject`. The older `/session/{sessionID}/permissions/{permissionID}` route is marked deprecated and uses a different body. No once/always approval encoder is provided. This corrects the uncertainty in the earlier rolling-document design without changing that historical packet. Static source correspondence is verified; behavior of the installed executable remains NOT TESTED, and source tag/version is not reproducible-build attestation of the binary.

## Inert launch manifest and configuration evidence

RuntimeLaunchManifest represents absolute executable/path data, expected version/SHA256, argv, cwd, environment-key allowlist, config/cache/data directories, endpoint and a requirement for an ephemeral credential. It contains no credential value and has no launcher. Its validation is bounded data validation, not path resolution, configuration isolation or authority.

| Setting / behavior | Status for 1.18.25 |
|---|---|
| OPENCODE_CONFIG, OPENCODE_CONFIG_DIR, OPENCODE_CONFIG_CONTENT | Referenced in pinned configuration source; not a proof that other sources are excluded |
| OPENCODE_DISABLE_PROJECT_CONFIG | Referenced around project config discovery; complete flag parsing and exclusion behavior not executed |
| Global/custom/project/directory/inline/managed sources | Merge/load paths present in static source; personal configuration was not opened |
| Command/agent/plugin discovery and dependency-install path | Present in static source; none started here |
| Cache/data/home isolation, CLI args, endpoint/auth flags, no network/extensions | Representable requirements; complete effective behavior unverified, launcher remains absent |

Source inspection is not a safe-start proof. Source includes remote configuration paths and directory dependency setup; therefore a custom config path alone must not be treated as containment. No OpenCode invocation, including --version, was used during this phase. Installed package metadata and binary hashing were sufficient. Any future live capture still requires a demonstrably isolated environment and separate approval.

## Future provider gateway — documentation and inert fixture only

The proposed gateway is not implemented or wired. [gateway-fixture.json](Contracts/gateway-fixture.json) is WF-owned synthetic contract data, not an asserted OpenCode or Ollama wire schema.

A request carries task/session/operation/generation/epoch, unique inference request ID, exact provider/model artifact digest, context manifest digest, total context and output-token caps, absolute monotonic deadline and a broker-owned provider-lease ID. The lease is issued/held by trusted composition/provider management; knowing its identifier confers no ability to acquire another lease. No arbitrary URL or cloud fallback is accepted.

Stream frames carry the same correlation, increasing sequence, bounded text or structured tool proposals, and an explicit final/error frame. Partial tool arguments accumulate only within their byte cap and are schema-validated after completion; unknown tool names/extra authority requests are rejected. Tool-call JSON is data only. No model call performs a tool action. Server-side OpenCode-to-compatible-provider mapping remains unverified and belongs to 1B.3, including translation to native Ollama streams.

Cancellation addresses the exact inference request and propagates the tighter of turn/operation/task deadlines. Closing a stream is not server stop proof. Release the lease only with observed request settlement/unload; otherwise report uncertain and block heavy admission. The shared user's daemon must never be killed or reconfigured. Errors distinguish unavailable, artifact mismatch, malformed stream/tool schema, overload/resource pressure, timeout/cancel, unexpected disconnect and uncertain cleanup; raw provider text is sanitized. One lease, initially 4k context/1,024 output-token caps and the existing 8 GiB/4 GiB measured gate remain future requirements. No inference, provider executable, downloads or model selection acceptance occurred.
