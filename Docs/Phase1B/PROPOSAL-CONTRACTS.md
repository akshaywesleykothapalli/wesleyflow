# Structured proposal contracts — version 1 design

19 October 2026 · Documentation only. No Swift Domain implementation, decoder, validator, broker or authority constructor is added in this task. 1B.2B will implement consumed types and pure validation; 1B.2C/1B.4 will establish real context/effect boundaries.

## Typed value model

All values are immutable, Equatable where meaningful, and Sendable-compatible. Strings/bytes cross boundaries; Foundation process/URLSession/store/vendor objects and handles do not. Explicit top-level `schemaVersion: Int = 1` versions CodingProposal, WorkspaceSnapshot, ProposalValidationResult, ApprovalRequirement and VerifiedChangeResult; nested values use their enclosing version and cannot be decoded independently without one. Unsupported versions reject before interpretation. A future migration must be explicit, never best-effort reinterpretation.

| Type | Fields / closed variants | Owner and meaning |
|---|---|---|
| ProposalIdentifier | canonical lower-case UUID string | WF assigns to a response envelope; identifier grants no permission |
| ProjectIdentifier | canonical lower-case UUID string | Trusted registry assigns; never a path or authority; unknown project rejects |
| CodingProposal | schemaVersion, proposalID, projectID, baseSnapshotDigest, changes:[ProposedFileChange] | Decoded hostile model data; WF wraps it with task/operation/session/generation/provider/artifact/deadline/context identity |
| WorkspaceSnapshot | schemaVersion, projectID, snapshotDigest, entries:[relativePath, fileRevision] | Trusted context service constructs from authorized observations; model's claimed digest is compared, never trusted |
| ProposedFileChange | exactly `create(relativePath, expectedRevision:absent, utf8Content)` or `update(relativePath, expectedRevision:sha256, utf8Content)` | Bounded full replacement text, not a script/patch executable. No delete, rename, chmod, binary, command, URL or environment case |
| ExpectedFileRevision | exactly `absent` or `sha256(lowercaseHex64)` | Creation requires confirmed absence; update requires matching current regular-file bytes |
| ProposalValidationResult | schemaVersion; exactly rejected(reasons) or validated(proposalDigest, projectID, baseSnapshotDigest, expectedPostSnapshotDigest, policyRevision) | WF-only derived data, not dispatch authority; invalid proposals yield no partially usable validated plan |
| ProposalRejectionReason | unsupportedSchema, unknownField, unknownOperation, malformed, oversized, invalidPath, duplicateTarget, projectMismatch, unknownProject, staleSnapshot, revisionMismatch, unauthorizedTarget, unsafeFileType, conflict, cancelled, deadlineExceeded, policyChanged | Closed safe error codes with bounded index/relative-path references, no raw source/secret echo |
| ApprovalRequirement | schemaVersion, proposalDigest, projectID, baseSnapshotDigest, policyRevision, operationDigests, taskID, operationID, sessionID, generation, deadline, maximumTTLMilliseconds | Trusted policy computes exact review scope. A requirement says approval is needed; it is NOT a grant or an approval decision |
| VerifiedChangeResult | schemaVersion, proposalDigest, projectID, baseSnapshotDigest, observedPostSnapshotDigest, receipts, verificationScope, evidenceDigest, outcome | WF verifier constructs after broker receipts and independent observation; never accepted from a model/provider response |

`receipts` contain relative target, intended before/after hashes and actual disposition `notApplied/applied/uncertain`, plus durable intent/outcome references. `verificationScope` is exactly `fileContent` or `containedBuildAndTests`; `outcome` is `verified/failed/partial/uncertain`. Verified file bytes do not imply a successful build. Missing command containment means containedBuildAndTests cannot be claimed. These are future data types, not proof their producer is trusted: trust follows the private injected construction path and consumed one-use capability, never an arbitrary decoded result.

## Strict wire boundary

The model-facing schema is CodingProposal only. Unknown keys anywhere (including command, shell, permissions, approval, verification), unknown operation/revision discriminators, duplicate JSON keys, invalid types, unsupported schema versions and trailing documents reject. No coercion/default version, ignored unknown cases, lossy UTF-8 repair or automatic decoding into an effect/approval/result envelope. Swift synthesized Codable alone does not reject unknown/duplicate keys; the future bounded parser must implement these checks explicitly before typed construction.

Initial limits: complete input ≤1 MiB UTF-8, maximum nesting16, ≤20 changes, ≤256 KiB content/change with aggregate content plus envelope ≤1 MiB, ≤1,024 UTF-8 bytes/path, ≤32 path components, ≤128 bytes/identifier fields (UUID representation remains canonical36), ≤32 rejection diagnostics each ≤256 bytes. Empty change lists reject. Check declared/raw limits before allocating large objects; decoded string bytes and repeated/escaped keys also count. Stream assembly needs its own bounded budget. No truncation into a valid proposal; fail closed on overflow or malformed input.

Targets must be nonempty relative logical paths. Reject absolute/drive/UNC paths, slash prefixes, backslashes, colon, NUL/control characters, empty/`.`/`..` components, trailing separators, tilde prefixes and percent-encoded path syntax (no later percent decoding). First scope excludes hidden components, `.git`, `.env*`, credentials, build/cache directories and reserved runtime/config metadata. Normalize canonical Unicode and detect case/Unicode-equivalent collisions under the actual registered volume rules; reject ambiguous names. Content is never executed or interpolated. Reject duplicate/prefix-conflicting targets and path aliases; pure string validation is not OS confinement.

## Snapshot, authorization and validation order

1. Bound bytes/depth and strictly parse version/shape. Reject unknown kinds; validate IDs/digests and per-field/count/aggregate limits.
2. Bind the WF-owned response envelope to the admitted task, generation, provider request, context and deadline. A copied proposal ID does not create this binding.
3. Compare project identity/base digest against an injected trusted snapshot. Sort normalized UTF-8 relative paths bytewise; snapshot digest is SHA256 over the versioned, length-prefixed `(projectID, entry count, each path, revision tag/digest)` sequence. Integer lengths are unsigned64 big-endian. No locale, unordered JSON, timestamps, absolute paths or grant material in the digest. Digest comparisons require version equality.
4. Validate every create/update against file-specific expected revision, scoped editable-target allowlist and immutable policy revision. No model can broaden the supplied allowlist. A read-context grant is not a write grant. Reject nonregular files, symlinks/hardlinks/aliases and uncertain identity; actual handle/type/race checks belong to trusted adapters in 1B.2C/1B.4, not the pure 1B.2B validator.
5. Compute expected post-snapshot and a proposal digest over the versioned length-prefixed identity/base/ordered operation/path/revision/content bytes. Sort operations by canonical target; reject duplicates before hashing. Produce validated data or bounded rejection reasons. Validation success grants zero authority.
6. Trusted policy derives ApprovalRequirement. MainActor UI shows exact project, normalized diff, before/after hashes, limits and verification scope. Denial, expiry (at most300,000ms), revocation, changed digest/project/policy/revision or cancellation blocks dispatch. User approval cannot override invalid paths or stale revisions.
7. Only a separately implemented effect broker atomically consumes an unforgeable one-use dispatch capability bound to task/operation/session/generation, exact descriptor/project/base revision/policy/deadline. No public initializer or model-decoded field creates it. Revalidate handles/no-follow file identity, current hashes and generation after every await and immediately before effects.
8. Durable intent precedes effect; receipts and independent observations establish actual post-state. Partial/uncertain effects stop the chain and preserve unresolved intent. Never auto-replay/rollback on crash. VerifiedChangeResult is separate from the model claim; never mark build/test success without actual contained command evidence.

Snapshot entries cover all files admitted to the scoped transaction and collision checks; they are not a claim that an entire changing repository was atomically snapshotted. Revalidate the registered root and every affected file at use. Host changes outside the authorized snapshot do not silently become input/authority.

## Synthetic schema example

This is documentation, not a fixture added to a test target. Literal hashes are synthetic; the base digest does not assert correspondence to any actual project.

```json
{"schemaVersion":1,"proposalID":"11111111-1111-4111-8111-111111111111","projectID":"22222222-2222-4222-8222-222222222222","baseSnapshotDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","changes":[{"kind":"create","relativePath":"Sources/Greeting.swift","expectedRevision":{"kind":"absent"},"utf8Content":"struct Greeting {}\n"}]}
```

An update substitutes `kind:update` and `expectedRevision:{kind:sha256,digest:<hex64>}`. Exactly the documented keys are allowed for each variant. Documents/schema examples define future contracts, not present Swift APIs or accepted effects. 1B.2B acceptance includes decode rejection, deterministic digest vectors, aggregate limits, stale/unauthorized fixtures and zero dispatch capability; see [gates](TEST-AND-ACCEPTANCE.md).
