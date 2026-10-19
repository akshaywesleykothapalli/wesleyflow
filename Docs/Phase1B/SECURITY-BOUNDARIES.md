# Security boundaries and execution gate

19 October 2026 · Highest-priority requirements · No containment mechanism was implemented or tested in this task.

## Authority separation

| Authority | Exclusive owner | Runtime/model receives |
|---|---|---|
| User authorization | Trusted MainActor UI gesture, showing exact project/diff/command scope | Decision outcome only; project text is never a gesture |
| WF policy | SystemOperations broker, immutable limits and session revocation | Normalized denial/result, no issuer capability |
| Runtime session | CodingAgents actor and supervised worker ownership | Its own opaque session ID and bounded context |
| Tool proposals | Model/runtime, untrusted input | Ability to propose, never authority to execute |
| Actual effects | SystemOperations dispatch boundary | Sanitized receipts after authorized completion |
| Filesystem | Broker-held root/directory descriptors and one-use operation capability | Selected bytes, relative logical paths; no raw host capability |
| Terminal | Broker-owned executable/argv/environment/process descriptors | Output data, never shell access or arbitrary command delegation |

The existing PermissionBroker correctly limits current fake operations but does not enforce filesystem or process isolation. OperationToken is publicly constructible identity. Before real effects, broker dispatch must atomically validate/consume an unforgeable grant and recheck current generation/deadline/root/descriptor at the final effect boundary. Coordinator consumption alone, followed by an await into a freely callable executor, is insufficient. Proposed dispatch capability is one-use, nonpersistent and revoked by session generation; only trusted composition/coordinator can obtain it. Model and runtime never receive its creation or redemption interface.

## What each control can establish

| Control | Enforcement and limits |
|---|---|
| Prompt instructions | Useful behavior guidance; no security authority |
| WF/OpenCode policy prompts | Application decisions; cannot stop a different code path or arbitrary native process |
| Root/path validation | Broker restrictions for operations actually mediated by broker; cwd and string prefix tests do not confine a process |
| App Sandbox | OS-enforced entitlements/resource restrictions for correctly built/signed processes; exact helper/tool inheritance and access require tests |
| XPC | Privilege separation/lifetime boundary; not a sandbox by itself |
| Dedicated VM | Guest filesystem/process boundary if no host mounts/services expose authority; guest egress/shares/IPC still require explicit control/tests |
| Network restrictions | Separate enforcement: no guest network device or constrained authenticated relay; host App Sandbox client entitlement alone is not a per-destination allowlist |
| Audit/hashes/process observations | Detection/evidence after attempted actions, not prevention |

Apple documents App Sandbox limits and child-tool inheritance; runtime-granted file access needs careful handling. An installed unsandboxed OpenCode binary does not become sandboxed because WF launches it or uses XPC. [App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox), [inheritance requirements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).

Apple Virtualization supports VM infrastructure, including macOS guests on Apple Silicon. This is an evaluated design option, not evidence that an image, Xcode guest, network policy or bounded guest stop exists here. Linux guests cannot independently verify native AppKit/macOS builds. [Virtualization](https://developer.apple.com/documentation/virtualization), [macOS guests](https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon).

Do not base production security on ad hoc sandbox-exec profiles, process groups, code signing, Hardened Runtime or TCC consent alone. No supported arbitrary-process sandbox profile has been selected/verified. A signed, minimal sandboxed proposal helper may be lighter than a VM, but embedding this runtime, config writes, inherited rights and local inference connectivity remain feasibility gates.

## Selected safe default and fallback

No native OpenCode access to a host project, home, Keychain, credentials, global config or inherited descriptors. Start only deterministic fixtures in 1B.1. A future live proposal worker gets explicitly selected source bytes in a fresh disposable snapshot after containment and budget validation. Host brokers apply reviewed changes; guest-generated patches remain hostile data. Builds/tests can execute arbitrary repository scripts and generated code; require a separate contained verification boundary, not merely approval for the build executable.

Execution-mode ADR and explicit scoped user approval must precede any general-purpose worker/build. The design recommends isolated mode. Trusted-project unrestricted mode remains an alternative allowed by old ADR008 only with separate visible user-account-authority approval; **not selected here**, never valid for untrusted autonomous work. If no isolation candidate fits M4/16 GiB or native toolchain needs, hold live execution. Direct Ollama proposal generation with WF-controlled effects is the safer reduced feature, also requiring its own implementation scope and provider cancellation gates.

## Filesystem and project threats

Registration requires an explicit user-selected directory, stable volume/file identity, canonical path, scoped bookmark when applicable, trust mode and fresh root confirmation. A bookmark is an access mechanism, not the task grant. Revalidate moved/stale roots; reject `/`, home-wide and system roots. Bind every task to one registered identity, root device/inode (or stable equivalent), baseline content snapshot and runtime mapping. Nested/alias projects share a lease; no model-specified cwd. Wrong repo → conflict before context/effects.

Broker reads/writes traverse relative components from a held root directory handle, reject absolute paths, `..`, NUL, reserved metadata and unsupported names, and open components with no-follow semantics. Check file type, device/inode, parent identity and original content hash immediately before use; reject symlinks, hardlinks with external alias risk, special files and uncertain cross-volume/root swaps in the first implementation. String realpath validation followed by later path-based open leaves a TOCTOU gap. Persisted paths do not restore handles/authority after restart.

First productive patch scope: bounded regular text-file create/update only; no deletion, rename, modes, executable bits, hardlinks, Git metadata, submodule/worktree controls or arbitrary binary patch. Proposed defaults: 20 files, 256 KiB/file and 1 MiB total patch. Use structured edits/digests, not executable patch hooks. Precompute expected snapshots; reject mismatched base, case/Unicode collisions and external edits. Stage on destination filesystem under approved scope and replace per file with flush/revalidation; multi-file application is not atomic. Keep per-file applied/not-applied/uncertain receipts. Never auto-reset Git or roll back over user edits.

Read context by allowlist with explicit preview/bounds (initially 100 files/4 MiB before token truncation). Exclude hidden/private files, `.git`, `.env*`, keys, credentials, symlinks, package caches, binaries and executable runtime configuration by default. Filename filters alone cannot guarantee source contains no secrets: user-selected byte disclosure, local-only transport, scanning/redaction and least context are complementary. No unrelated project reads, credential mounts or broad home enumeration.

## Commands, injection and network

Approve exact executable identity/hash, argv array, cwd identity, sanitized environment, input hashes, allowed output directories, network mode, output cap and deadlines. No shell interpolation, `sh -c`, `eval`, pipelines or model-provided environment/path. Reject unknown executables/arguments and command-prefix approvals. Even git metadata commands can invoke helpers/config; use controlled configuration and disable hooks, external diff/textconv, paging, recursive submodules and network. Do not run project scripts during inspection.

Repository documents, comments, tool output, patches and model responses are untrusted data. They cannot change policy/provider/config or approve the next operation. Render approval data escaped; identify generated content and exact change scope. Reject injected requests to reveal credentials, add plugins, call network endpoints, rewrite approval rules, alter verification or switch projects. Detect suspicious instructions, but rely on restricted authority rather than classifier accuracy. Disallow egress by mechanism; localhost auth and disabled web tools alone do not establish network isolation. Inference relay allows only bounded requests to the selected local artifact, denies redirects/cloud/pull/config routes and shares no host credentials.

## Cancellation, evidence and retention

Revoke first, stop dispatch, close streams, request abort, terminate owned worker/guest and collect positive stop evidence. RPC ack or closed socket is not process death. Graceful 2 s plus escalation 3 s; report within 5 s, quarantine on uncertainty. Process groups cannot prove escaped descendants are gone; containment must prevent escape or allow termination of the whole owned guest. Never kill unrelated Ollama/user processes. Guest stop does not prove a host inference request ended: track the provider lease separately.

Persist sanitized intent before effects; if storage stalls/fails, dispatch zero new effects, revoke/clean up independently, show uncommitted failure. Keep unresolved dispositions on restart and invalidate all grants/sessions. No automatic replay, reattach or restored approval. Verify outcomes independently; no agent success narrative is evidence.

Source/prompt/patch/log retention is opt-in with scope/expiry; default database contains digests/IDs/safe summaries. External runtime databases/caches may retain content even if WF does not: allocate ephemeral isolated data, disable sharing, count it, and destroy only after positive cleanup or quarantine it. No erasure/backups guarantee. Aggregate managed history/evidence/artifact/staging/runtime-content quota 100 MiB, 10 MiB recovery reserve, 30-day eligible retention, 1 MiB captured output per operation. Disk images/model weights are separately inventoried resources with admission free-space limits, not hidden in the 100 MiB ledger. Current projected quota is not a hard OS limit; actual accounting remains a gate.

See [tests](TEST-AND-ACCEPTANCE.md) for the required separation of mocked authorization checks from adversarial OS enforcement evidence.
