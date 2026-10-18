# Security and permissions strategy

## Trust model

User authority, macOS consent, and agent/model output are separate. Treat transcripts, repository files, README instructions, model responses and tool output as untrusted data. They cannot grant permissions or change policy. A coding agent can propose an operation; only the broker can authorize and execute it.

Threats include misrecognized commands, prompt injection in projects, secret exposure in context/logs, path escapes, stale edits, subprocess escape, excessive resource use and unknown outcomes after crashes. A non-sandboxed app with a general-purpose subprocess cannot guarantee containment against malicious code. Project builds and tests execute project code; consent must disclose that scope. Do not describe an allowlisted executable as safe merely because its name is approved.

## Operation authorization

Each effect carries task ID, operation ID, canonical root/resource, operation type and exact arguments or patch digest. The broker checks current policy and task state immediately before execution. Approval grants are scoped, short-lived, revocable and invalid after restart, changed arguments or changed patch. The confirmation shows concrete paths, patch, executable/arguments, expected effects and verification steps. Approval for reading does not imply writing or process execution. Destructive actions require explicit confirmation; no privilege escalation or `sudo` workflow is planned.

Resolve and check paths against selected roots; reject traversal, outside-root symlinks and reserved app/credential locations. Revalidate before writes and compare original file hashes before applying patches. Use handle-based/no-follow access where available to reduce path-swap races; document residual races rather than claiming canonicalization alone solves them. Stage writes, provide diffs, preserve user changes and report partial application. Do not automatically reset repositories or roll back unrelated edits.

Runtime adapters must route supported effects through the broker. A runtime that directly edits files/spawns processes escapes these controls; it remains unsupported pending an explicit containment design. Even brokered arbitrary builds can execute unrestricted child code in the initial non-sandboxed architecture. Strong isolation needs a separately designed OS boundary; it is not delivered by this proposal.

## macOS permission map

| Capability | Approach |
|---|---|
| Microphone | Request only on first explicit capture; provide usage description; stop capture on cancel/denial |
| Speech recognition | Check authorization and on-device availability for selected language/API; request speech permission if that API requires it; fail locally if offline recognition is unavailable |
| Accessibility | Request only for approved UI-control features; explain System Settings workflow; recheck before use |
| Apple Events | Target-specific Automation consent and required usage description/entitlements; avoid blanket requests |
| Project files | Explicit user-selected root; maintain access state; security-scoped bookmarks only where applicable; handle stale/revoked access |
| Screen recording | Not needed for Phase 0; no request until an approved feature requires it |
| Full Disk Access | Not a baseline requirement; do not request speculatively |
| Network | No baseline inference/recognition network dependency; later model downloads are explicit with source, size, integrity and license checks |

The shell requests no microphone, Accessibility or Automation permissions. Add entitlements only with the feature and test them with signed builds. Plan direct distribution with Hardened Runtime, Developer ID signing and notarization as release gates; specific entitlements must follow actual integration requirements. App Sandbox is deferred (ADR 008), which is a material isolation limitation.

## Data handling and recovery

Store task metadata in user Application Support, with normal per-user filesystem protection; do not claim app-level encryption at rest. OS disk encryption depends on host configuration. Credentials belong in Keychain if introduced. Do not capture raw audio or retain transcripts by default. Exclude credentials, ignored files and large/binary files from project context unless explicitly selected. Show context scope and support removal. Avoid sending any project data remotely in the local-first baseline.

Bound logs/artifacts by configurable retention and disk limits; retain essential task outcomes, disclose pruning and provide delete/export. Redact environment variables, tokens and personal paths in exported diagnostics. Deletion must cover database rows and referenced artifacts; do not promise forensic erasure or backup deletion. Recovery never resumes a privileged action or restores approval automatically. Persist partial-effect evidence and ask the user to inspect uncertain results.
