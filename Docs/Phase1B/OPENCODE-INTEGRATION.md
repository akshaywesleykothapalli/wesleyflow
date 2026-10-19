# OpenCode integration decision

19 October 2026 · Research verified against official documentation; no server/session launched.

## Version boundary

The resolved CLI is `/Users/akshaywesley/.nvm/versions/node/v20.20.0/bin/opencode`; `--version` returns 1.18.25. Installed package metadata is `opencode-ai` 1.18.25. This is **V1**, not V2. Official V2 uses `@opencode/cli`; its embedded SDK is `@opencode/sdk`. V2 permission rules use `permissions`, `shell`, `subagent`, unlike V1 `permission`, `bash`, `task`. Do not infer API generation from a V1 SDK subpath named `/v2`. [V2 installation](https://opencode.ai/v2/docs/), [V2 SDK](https://opencode.ai/v2/docs/build/sdk/), [V2 permissions](https://opencode.ai/v2/docs/permissions/).

Installed runtime version is verified; compatibility of its exact HTTP schema with rolling documentation is **not**. No live `/doc` was retrieved because starting a runtime was outside this task. 1B.1 must bind binary path/hash/version and captured schema hash to decoder fixtures. Reject unknown generations, endpoint shapes or missing required safety features; never silently use V2 fields or upgrade.

## Alternatives

All assessments below are engineering judgments. None was integration-tested here.

| Method | Complexity/reliability | Ownership and lifecycle | Streaming/cancel | Permissions/testing/maintenance |
|---|---|---|---|---|
| Native Swift HTTP + SSE — primary | Small supported API subset; explicit typed decoding; transport reconnection must be written | WF owns dedicated runtime instance/session mapping; no attach to user's server | SSE parser plus explicit abort; separate process cleanup | Policy remains WF-owned; excellent recorded/mock HTTP fixtures; schema drift handled by pin |
| Official V1 JS/TS SDK | Generated types reduce wire work; requires JS runtime/dependency supply chain | SDK can launch server or connect; embedded startup convenience can obscure ownership | SDK async streams/AbortSignal do not prove runtime stopped | Still no containment; adds pin/license/runtime and bridge testing; no official Swift SDK identified |
| Small Swift↔JS SDK bridge | Useful only if essential SDK-only behavior appears | Additional supervised process and framed IPC with size limits | Must translate events, errors and cancellation across two boundaries | Same authority problem; two version contracts; less desirable initially |
| Supported ACP stdio | No TCP listener; standard editor-oriented protocol | Dedicated child naturally owned; compatibility adapter still needed | JSON-RPC stdio; stop proof still separate | Capability/permission mapping must be proven; insufficient evidence here for full broker mediation |
| CLI run/JSON or terminal automation | Superficially simple, weaker control surface | Coarse invocation/session handling | Output parsing/interrupt can be ambiguous | Reject as primary: harder to correlate approvals/results or recover deterministically |

The official V1 SDK provides server+client creation and client-only connection; it is JS/TS, not native Swift. [V1 SDK](https://opencode.ai/docs/sdk/). ACP is explicitly supported through `opencode acp`, using JSON-RPC over stdio. It remains a legitimate later alternative, not an assumed safer executor. [ACP](https://opencode.ai/docs/acp/).

## Documented V1 wire surface to verify

The official server guide documents a headless HTTP server, Basic authentication, OpenAPI discovery and SSE. Candidate routes are below; **documentation evidence only**, not an exact-version conformance result. [V1 server](https://opencode.ai/docs/server/).

| Purpose | Documented candidate |
|---|---|
| Readiness/schema | GET `/global/health`, GET `/doc` |
| Create owned session | POST `/session` |
| Submit bounded proposal | POST `/session/:id/prompt_async` or `/message` |
| Progress/status | GET `/event`, GET `/session/status` |
| Abort | POST `/session/:id/abort` |
| Permission response | POST `/session/:id/permissions/:permissionID` |

Exact request types, permission event names/reply fields, directory selection, authentication failures, stream terminal conditions and disposal semantics must come from the installed schema/source and subsequent restricted conformance tests. The guide's permission route may represent a compatibility surface; do not guess an alternate endpoint or remember flag. Unknown permission request → deny/fail closed. Do not use init (writes AGENTS), shell, command, revert, configuration-write, auth or dynamic MCP endpoints. API success/idle/abort true are never effect, verification or termination evidence.

## Owned transport contract

Future worker startup must use a pinned absolute executable, controlled empty home/config/cache/data directories, sanitized environment and no inherited credentials. Prefer a dedicated instance per task; only one productive session globally. Never attach to a user's server or terminate their processes. Listen only on an isolated loopback interface with unpredictable per-run credentials and no mDNS/CORS exposure. Bind readiness to the owned child and expected version; port collisions/server substitution fail closed. Deny redirects and nonlocal endpoints. Authentication is local access control, not protection from an equally privileged compromised user process.

Connection within a VM needs an authenticated, bounded host↔guest channel; guest loopback is not host loopback. Relay only session messages and approved inference traffic, not arbitrary HTTP proxying. A proposed per-session inference gateway in ModelProviders translates the pinned runtime's compatible provider requests to Ollama; its schema/stream/error mapping must be proven in 1B.3. OpenCode must not independently load a second model or access host Ollama broadly.

Events are tagged with task/session/operation/generation and validated against the owned mapping. Bound each frame to 64 KiB, pending progress to 256 KiB and semantic request payload to 256 KiB; overflow is a typed protocol failure, never silent loss of an approval/outcome. Coalesce token progress (UI at most 10 updates/s); keep durable semantic events separate. These are proposed limits. On reconnect, use supported status reconciliation; SSE replay IDs are unverified. Never resend a prompt/effect on ambiguous disconnect. Duplicate events are idempotent; foreign IDs are rejected.

## Configuration is executable input

V1 merges configuration sources; pointing at one custom config does not establish exclusion of project/global config, plugins or tools. Global/agent permission precedence also matters. Therefore sanitize the snapshot: exclude `.opencode`, `opencode.json*`, local instructions/skills as executable configuration, hooks, MCP, LSP, formatters and package-install triggers. Repository instructions may be supplied as quoted untrusted context only. Verify effective configuration from safe allowlisted fields; never dump credentials. Disable updates, sharing, discovery and network-fetching extensions, subject to exact-version support checks. No assumed undocumented flag may serve as a safety boundary. [V1 configuration](https://opencode.ai/docs/config/).

V1 permission deny/ask/allow is defense in depth. Start with deny for all native tools, with no auto mode, no persistent/broad approvals and no subagents. Host approval is not an OpenCode native-tool approval: reject native requests; normalize an inert proposal and have WF separately evaluate it. If the runtime cannot produce bounded proposals without prohibited hooks/tools/config writes, leave it disabled or run it only inside the proved disposable guest, never grant host authority. [V1 permissions](https://opencode.ai/docs/permissions/).

## Contract gate

Before live enablement: exact schema fixtures; auth and wrong-server tests; effective-config provenance; no hidden plugins/autoapproval; provider routing; SSE bounds/order/duplicates; interruption without replay; actual owned worker stop/containment tests. Passing mock transport tests alone permits only mock use. No install, upgrade, SDK dependency, live server, API prompt or configuration change occurred during design.
