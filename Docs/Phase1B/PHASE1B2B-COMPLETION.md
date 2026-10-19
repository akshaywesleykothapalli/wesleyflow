# Phase1B.2B — structured proposal contracts and validation

19 October 2026 · **COMPLETE for the authorized pure implementation and available-toolchain verification.** Ready for separately scoped 1B.2C, not enabled real project access, editing, AI inference or command execution. At implementation delivery nothing was staged or committed. The subsequent final-review/checkpoint record below governs the separately authorized checkpoint.

## Repository review and preservation

Started on clean main at `3c8506d884f46c6ce70964877d19fb870b754aee`. Read AGENTS, adopted pivot/architecture/security/ADR/milestones/contracts, current Domain/task/permission contracts, coordinator ownership/cancellation/recovery and test patterns. Captured SHA256 baseline of 93 tracked files before edits. Existing app/UI, Phase1A Domain/coordinator/broker/SwiftData implementation and tests, CodingAgents fixture implementation/tests, containment experiment and historical evidence are preserved. No legacy source, unrelated projects, user configuration/credentials or private files were accessed.

Changed seven existing paths: AGENTS current scope; package manifest; Xcode project/shared scheme for a dedicated WorkspaceTests bundle; current architecture, proposal-contract and milestone documentation. All 110 original Xcode objects retain their settings/semantics, with only additive references/target lists in three container objects. No old test was removed/modified, no persistent model/schema changed and no production app composition was activated. Exact preservation/module evidence is in Evidence/Phase1B2B/static-verification.json and final-scope.json.

## Contracts and architecture

All ten contracts are implemented in `Packages/WesleyFlowCore/Sources/Domain/CodingProposal.swift`: CodingProposal, ProposalIdentifier, ProjectIdentifier, WorkspaceSnapshot, ProposedFileChange, ExpectedFileRevision, ProposalValidationResult, ProposalRejectionReason, ApprovalRequirement and VerifiedChangeResult. Values are immutable and Sendable; strong canonical lower-case UUID identifiers and explicit schema1 are used. Model-facing proposal/identifier/change/revision values support Codable with exact keys and closed discriminators. Observation/review/result data is deliberately separate from the model wire schema. ApprovalRequirement embeds evaluation summaries, never grant/issuer/token authority. VerifiedChangeResult is report data, not a verifier or proof-producing service.

New concrete `Workspace` target depends only on Domain. Three files implement CodingProposalValidator/ValidationContext, bounded JSON preflight/codec/limits and SHA256 canonical hashing. Foundation and CryptoKit remain adapter implementation details; Domain has no imports. No third-party dependency, empty ModelProviders/Verification target, framework suppression, UnsafeContinuation, new actor/lock, background service or task-lifecycle redesign. No filesystem, subprocess, network or permission-issuer port exists in Workspace. Static source/import inspection and actual package metadata complement runtime tests; they are not a proof against every future side effect.

## Validation, operations and serialization

Only **create** and **replace** are supported, with wire kinds `create` and `update`. No `replace` alias is accepted; unknown operation names fail closed. Deletes/renames/moves/scripts/commands/installation/permission changes and executable patches are not representable. Content is a bounded full UTF-8 replacement string, never executed. A string containing Markdown or shell text remains inert content; structural acceptance does not say it is safe/correct Swift or an authorized edit.

Validation checks version, bounded canonical IDs, expected request/project identity, generation, deadline/cancellation, valid lowercase64-hex hashes, exact expected snapshot digest and independently recomputed injected snapshot digest, policy revision, counts/actual encoded envelope/content size, relative paths, duplicates/prefix conflicts, editable-target membership, expected file revision and supported injected file state. Wrong policy, stale/changed snapshot, existing create target, missing observation, changed replacement revision and unsupported file state return distinct safe rejection codes. First rejection is deterministic; no partially usable validated plan escapes.

Raw input is capped **before decoding**. CodingProposalCodec's bounded scanner rejects malformed JSON, duplicate decoded keys anywhere (including Unicode-escaped spellings), invalid UTF-8/unpaired surrogates, unknown keys, unsupported versions/kinds, ambiguous numeric spellings, trailing documents, BOM and Markdown wrappers. Generic JSONDecoder alone cannot supply duplicate-key security and is not the supported hostile-byte entry. Typed programmatic proposals are also revalidated. Predictable sorted-key JSON round trips preserve exact content. No silent input/path repair or command interpretation.

Limits and rationale are detailed in [contracts](PROPOSAL-CONTRACTS.md):1MiB input/encoded envelope,256KiB content/change,20 changes,1,024 path bytes/32 components,16 recursive value levels,512 syntax nodes,32 keys/object/128 key bytes and100 observations/editable targets. Counts and depth bound decoder object expansion; raw/decoded/encoded bytes are checked. Foundation/transient allocations, including escaped serialization, are not a measured RSS or OS memory quota. Transport/session buffering belongs to later adapters.

Lexical checks reject absolute/drive/UNC/backslash/percent/tilde/control/NUL paths, empty/dot/traversal components, protected/hidden/credential/config/cache metadata, trailing dot/space and non-NFC names. Policy revision labels are bounded ASCII tokens and compared byte-for-byte. ProposedFileChange equality also compares exact UTF-8 path/content bytes rather than Swift canonical Unicode equivalence. Case-folded and canonical/prefix aliases reject conservatively, including on case-sensitive volumes. This is not a complete model of volume name equivalence, actual symlinks, inode identities, hardlinks, mounts or race safety.

## Revisions, hashing and approval separation

SHA256 hashes exact UTF-8 content; canonical snapshot/proposal/operation encodings use versioned unsigned64 big-endian length prefixes and byte-sorted paths. Independent Python hashlib/struct vectors were generated before Swift execution and tested for create/update/multiple operations, post-snapshot and known empty/Unicode hashes. Operation order and snapshot order do not change canonical evaluation results. Content normalization does change content bytes/hashes; no repair occurs.

A create needs an explicit injected absent entry; no entry means unknown. Replacement needs a structurally valid expected SHA256 that matches the supplied regular-file observation. Snapshot fileState/revision consistency is checked before hashing; unsupported state rejects. Expected post-snapshot/content hashes are predictions, not observations that a file changed. Injected snapshots/context are caller data, not authenticated filesystem observations. Future1B.2C must obtain/revalidate them through the trusted read boundary.

ProposalValidationResult means **accepted for further evaluation** or rejected, not approved. A copied/forged public identifier, accepted summary or ApprovalRequirement cannot be redeemed for effects. Tests show that the unchanged Phase1A broker continues to reject fileWrite/process/automation after structural acceptance. Real request/provider correlation and current time/generation after asynchronous work must still be supplied/rechecked by future trusted adapters; pure synchronous validation does not attest context provenance. No broker, approval UI, grant issuance or dispatch is implemented here.

## Confirmed regression and correction

Initial focused tests passed30 functions/112 cases. Review found that the first draft checked project/snapshot but lacked expected proposal-ID correlation. Added `responseIdentifierCannotBeSubstitutedWithinExpectedProject` before fixing it: correlation-regression-before exited65,31 functions/113 cases, exactly one failing function. It demonstrated a `.validated` result where `.rejected([.conflict])` was required for a substituted request ID. The validator now compares the WF-owned expected proposal ID and expected/current generation in the injected context; malformed approval metadata is also bounded. Added stale-generation, snapshot consistency/limit, Unicode and metadata tests. No assertion was removed or weakened. The defect was in this new draft; no Phase1A rewrite was needed.

Final exact-byte review added two more regression functions: Swift synthesized String/enum equality hid different UTF-8 content, and non-ASCII policy metadata compared equal under Unicode equivalence. byte-identity-regression-before exited65,37 functions/123 cases, two failing functions/three assertions. The fix uses exact path/content byte equality and bounded ASCII policy tokens with exact matching. Those assertions remain unchanged and pass in the verified runs. An incremental post-fix build (accepted-focused) exited65 at link time, referencing the removed synthesized `__derived_enum_equals` symbol; no tests ran in that attempt. A fresh `DerivedData/Phase1B2B-Final` build with the same source resolved it. Intermediate472-case passing runs are retained but are not final-source acceptance proof. The extra unmodified Release QA attempt also exposed existing @testable imports compiled without testing access; an isolated optimized QA build with ENABLE_TESTABILITY=YES resolved that build-mode mismatch without production source/settings changes. Both failed builds remain recorded, with zero tests claimed for them.

## Actual verification

| Run | Exit | Observed outcome |
|---|---:|---|
| focused (initial draft) |0 |30 functions /112 cases, zero failures/skips |
| correlation-regression-before |65 |31 functions /113 cases; one intentional regression failure |
| byte-identity-regression-before |65 |37 functions /123 cases; two intentional failing functions, three assertions |
| accepted-focused (incremental link) |65 |Build failed on stale synthesized equality reference; no tests executed |
| verified-focused |0 |**37 functions /123 cases**, zero failures/skips |
| verified-full |0 |**150 functions /474 cases**, zero failures/skips |
| verified-replay |0 |Independent test-without-building, same 150/474, zero failures/skips |
| verified-debug |0 |BUILD SUCCEEDED |
| verified-release |0 |App BUILD SUCCEEDED |
| verified-release-foundation |65 |Extra QA compilation initially rejected existing @testable imports against ordinary Release modules; no tests executed |
| verified-release-tests |0 |Isolated optimized Release QA build with ENABLE_TESTABILITY=YES; Workspace/foundation test bundles compiled, no Release tests executed |
| Native summary/tree extraction |0 |Expanded function/Arguments counts independently verified, runtimeWarnings empty |
| Package/toolchain/settings/preservation/module checks |0 |No external packages; Workspace→Domain; old settings preserved; effective Swift6/strict complete/macOS26.0 |
| Diff/scope/fixture hash checks |0 |Original sources/tests preserved, executed fixtures match source, empty index; final source hashes match all six final runs |

All **351 previous cases remain**, plus 123 new cases. Full and replay include the existing Phase1A expiry/revocation, cancellation, persistence/recovery/shutdown and no-duplicate-execution tests, all Phase1B.1 HTTP/SSE/session tests, Domain lifecycle and native composition tests. The new parameterized cases cover malformed/unknown/duplicate/oversized proposals; root/traversal/NUL/separator/protected/case/Unicode paths; metadata/hash/revision conflicts;20-change/256KiB/1MiB/path/depth/snapshot boundaries; Unicode surrogate safety; canonical hashing; permission separation; Sendable values and cancellation. Fixture reads occur in test support only; production validator has no file API. No arbitrary sleeps, agent/model, filesystem broker or process/network executor runs in these tests.

Explicit lane: `/Applications/Xcode-beta.app/Contents/Developer`, Xcode27.0 build27A5237l, Swift6.4, SDK27.0, host macOS27.2 build26B5112a. The ordinary Release app build does not link Workspace because the app has no operational validator wiring. The additional Release build-for-testing explicitly compiles Workspace/test bundles with optimization and ENABLE_TESTABILITY=YES for existing @testable imports, in separate DerivedData/Phase1B2B-ReleaseTests; ordinary production Release settings remain unchanged; Debug focused/full tests compile and exercise them. arm64/macOS26.0 deployment, Swift6 language mode and complete strict-concurrency settings; compiler/Sendable checks pass without a new concurrency warning or suppression. Nonfatal AppIntents metadata and host linkd diagnostics remain visible in raw logs. TSan/Instruments, allocator/RSS quotas, actual macOS26 runtime and full Xcode26.3/Swift6.2.3 floor are NOT TESTED.

Evidence: ignored `Evidence/Phase1B2B/` holds exact argv/cwd/DEVELOPER_DIR/timestamps/exits, logs/xcresult bundles, source+fixture hashes for all final runs, review-results.json, independent vector provenance, package/settings metadata, module/preservation checks and final diff/status. No new OS crash/containment probe or model benchmark is claimed. An early result-tree counting helper was adjusted to count a failed nonparameterized test even when it has a Failure Message child; final passing counts were unaffected. Intentional failing evidence is retained.

### Exact verification commands

All run from `/Users/akshaywesley/Developer/WesleyFlow` with DEVELOPER_DIR as above and inherited SDKROOT removed. Common argv prefix:

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Phase1B2B-Final -disableAutomaticPackageResolution -skipPackageUpdates
```

| Record | Exact suffix |
|---|---|
| verified-focused | `-configuration Debug -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1B2B/verified-focused.xcresult -only-testing:WorkspaceTests test` |
| verified-full | `-configuration Debug -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1B2B/verified-full.xcresult test` |
| verified-replay | `-configuration Debug -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1B2B/verified-replay.xcresult test-without-building` |
| verified-debug | `-configuration Debug -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1B2B/verified-debug.xcresult build` |
| verified-release | `-configuration Release -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1B2B/verified-release.xcresult build` |
| verified-release-tests | `-configuration Release -resultBundlePath /Users/akshaywesley/Developer/WesleyFlow/Evidence/Phase1B2B/verified-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES` |

The Release QA command uses DerivedData/Phase1B2B-ReleaseTests rather than the common derived path. Initial/intermediate/regression runs use their named result paths and the focused suffix (or recorded full/replay/build actions), in the earlier DerivedData/Phase1B2B directory; actual argv/source hashes are in each named JSON. Result extraction: `/usr/bin/xcrun xcresulttool get test-results summary --path <named.xcresult>` and corresponding `tests`; exact arrays/exits in per-run extraction records. Metadata commands include `xcrun swift package --package-path Packages/WesleyFlowCore dump-package`, `xcodebuild -showBuildSettings -json -project ... -scheme ... -disableAutomaticPackageResolution -skipPackageUpdates`, toolchain and host queries, and Git preservation/diff/status inspection. All are controlled developer verification, not a model command runner.

## Files and remaining scope

Added four production Swift files: Domain/CodingProposal.swift and Workspace/CodingProposalValidator.swift, ProposalHashing.swift, ProposalJSON.swift. Added three test Swift files and two synthetic JSON fixtures under WorkspaceTests. Modified package/project/scheme and AGENTS; updated proposal-contract/architecture/milestone docs and added this completion report. Exact paths and hashes are in final-scope.json. No new persistence schema/migration, UI feature, real context service, model provider, effect broker or production command verifier. No empty future module.

**Structural validation is not real filesystem authorization.** It cannot attest caller observations, real file identity/permissions/symlinks/mounts/races, content safety/correctness, model quality, actual edits or build/test success for proposed code. Privileged operations remain disabled. The existing proposal-only architecture and insufficient-helper decision stand; a separately tested subprocess boundary remains mandatory before command-based product verification.

**Ready for separately authorized 1B.2C read-only context and secure snapshots**, with the remaining root/identity/no-follow/alias/disclosure/privacy/lease gates. No 1B.2C work began. Main/HEAD stays at `3c8506d`, index empty, intended implementation/docs remain uncommitted; no remote/push/new repository. Stop after 1B.2B.

## Final review and local Git checkpoint

Review decision: **PASS for this pure Phase1B.2B checkpoint; no blocking source defect found.** Independently inspected all17 pending paths, all ten Domain values, strict scanner/codec, path/revision/hash checks, authority separation, tests/fixtures and complete project/package/scheme changes. No source/test/build-setting correction was needed. The sole contract wording clarification states that NFC/conservative collision checks do not observe actual volume rules. Current checkpoint authorization was recorded in AGENTS. The implementation Git status above is historical, not the post-checkpoint state.

Validated the prior123 focused /474 full /474 replay records and all six accepted Debug/Release/optimized-QA records against current source+fixture hashes. Recomputed all stored SHA256 vectors independently in Python. Fresh checkpoint-full and checkpoint-replay-final each exited0: **150 functions /474 cases, zero failed/skipped**, runtimeWarnings empty. The initial checkpoint-replay exited65 because the cached app could not load its missing embedded native app-test bundle; the other test bundles ran. Its result tree contains470 entries including a synthetic failure, not470 successful executed cases. Rebuilding the test action restored the bundle and both complete runs passed. The failed replay and exact command/result records are retained; no test was removed or weakened. No source changed, so the matching prior Debug/Release/Release-QA evidence remains applicable without an unnecessary rebuild.

Only reviewed Phase1B.2B source/tests/synthetic JSON, package/project/scheme and documentation are included. App composition, lifecycle/permissions/persistence, CodingAgents and containment experiment remain unchanged. No credentials/generated binary/cache/database/evidence bundle, unexpected dependency, productive filesystem/provider/runtime path or unrelated modification is staged. Public evaluation/approval/result data remains non-authoritative; real observation, final effect capability and command containment gates are unchanged.

The user separately authorized one local commit: `feat(workspace): implement structured proposal validation`. Exact17-file inventory, staged patch/hash/index inspection, command exits, actual commit hash/parent and final clean working-tree status are retained under ignored Evidence/Phase1B2BCheckpoint. This report cannot contain its own eventual commit hash; the final response and checkpoint.json supply it. No push, remote creation or Phase1B.2C. Outstanding risks remain actual filesystem identity/races/context provenance, generic Codable misuse outside the strict codec, allocator/RSS bounds and actual macOS26/Swift6.2.3 compatibility.
