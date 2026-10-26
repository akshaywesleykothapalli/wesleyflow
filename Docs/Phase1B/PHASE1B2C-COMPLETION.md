# Phase1B.2C — secure read-only project context and snapshots

19 October 2026 · **Implemented and verified within the authorized fixture-root milestone.** No live model, real-project product access, editing, command executor or Phase1B.3 was enabled. At initial implementation delivery nothing was staged or committed. The final-review/checkpoint section below governs the separately authorized checkpoint. No push. Read-only observation does not authorize file modification.

Checkpoint review: **PASS after two confirmed fixes;214 focused cases and565 full/replay cases passed.** Current review findings, commands and limitations are recorded in the final checkpoint section below.

## Scope, review and files

Started on clean `main`, HEAD `70631ada818671011c6c2029712591cded0efccc`. Read AGENTS, adopted pivot/architecture/security, Phase0 security,2B completion, package/Domain/permission/snapshot/validator contracts and existing Workspace tests. Preserved every existing Swift source/test, package dependency, scheme, app composition and persistent schema. No legacy implementation was inspected/copied. Changes are confined to WesleyFlow; tests create and delete only their own UUID-named disposable local fixture directories.

Added:

- `Packages/WesleyFlowCore/Sources/Domain/WorkspaceObservation.swift`: registry/observation ports, typed errors, limits, immutable Sendable metadata and shared conservative policy.
- `Packages/WesleyFlowCore/Sources/SystemOperations/ReadOnlyWorkspaceBroker.swift`: actor-owned registry and sole project-source opening/read implementation.
- `Packages/WesleyFlowCore/Sources/Workspace/WorkspaceSnapshotBuilder.swift`: snapshot builder, deterministic manifest, bounded explicit-selection context assembler, proposal integration.
- `Packages/WesleyFlowCore/Tests/WorkspaceTests/ContextObservationTests.swift`:42 new functions/83 expanded cases across five suites, all disposable fixtures.
- This completion report.

Modified AGENTS with current narrow authorization, current Phase1B architecture/security status, and Xcode project with two additive file/build objects and test membership in two existing containers. No target, product, external package, entitlement, startup path or app feature was added. Workspace and SystemOperations each depend only on Domain; test composition imports both. Source files are included automatically by the existing Swift package; the new test file is included in both package and native WorkspaceTests builds.

## Registry and ownership

ReadOnlyWorkspaceBroker implements the minimal ProjectRegistry abstraction as well as WorkspaceObservationSource. Trusted fixture composition explicitly supplies a ProjectIdentifier and absolute selected root; it never discovers roots. IDs remain stable for the registration. Root device/inode identity is stored privately; no raw root path appears in snapshots/context. Maximum32 registrations, including revocation tombstones, per broker. Duplicate inode registrations and lexically nested/conflicting root registrations reject; same-ID replacement rejects. Revocation is idempotent, denies subsequent observation, and cannot silently regrant the same registration. Recreate the fixture service for a new scope.

Availability reports available, missing/inaccessible, relocated/replaced-at-path, or revoked. A moved path is missing until an explicit new selection; no outside-root search attempts to locate it. Every observation reopens the selected path through no-follow directory handles and checks its registered identity. Broad/system/home roots, symlink ancestors, unsupported roots, nonlocal final root filesystems, and directories not owned by the current user or writable by group/others reject. Root selection is injected data here, not a shipped UI permission mechanism or persistent grant. No bookmarks, persistence or automatic real-user registration is implemented.

Mutable registration state is actor-owned, with no production locks, unchecked Sendable, unsafe continuations or isolation suppressions. Observation runs synchronously on that actor with no awaits. Registration revocation is serialized with an in-progress bounded scan; Task cancellation is polled during work. Context assembly checks current registration availability before and after its assembly, rejecting a revoked root even when given an earlier snapshot. A separate validateObservation port also binds the observed root device/inode to the current registration, so another registry reusing a project ID for a different root cannot reuse that snapshot. Trusted composition must supply the real broker/registry ports; substituting a dishonest port cannot constitute filesystem evidence. These APIs are never exposed to a model.

## Descriptor access and path policy

The broker alone opens project source files. It opens `/` read-only and traverses each explicit selected-root component using openat with O_DIRECTORY/O_NOFOLLOW/O_CLOEXEC/O_NONBLOCK. Relative source traversal uses held directory descriptors, fstatat(AT_SYMLINK_NOFOLLOW), openat, fstat and bounded read. Descriptor duplicates use F_DUPFD_CLOEXEC; fdopendir owns its duplicate; every success/error/cancellation path closes descriptors through defer/explicit transfer. No realpath-then-open boundary, FileManager source read, URLSession, Process, shell, productive flag or network API exists in the new production implementation.

Relative paths are limited to1024 bytes/32 components, conservative ASCII names,255 bytes/component, with no empty/dot/parent/absolute/backslash/percent/colon/control/unsupported names or trailing dot. The context allowlist is deliberately narrower than2B's proposal spelling support: ambiguous Unicode names fail rather than being repaired. Existing2B case/alias/prefix conflict validation still applies before a snapshot escapes. Hidden and sensitive components are excluded before opening their contents. Every allowed candidate is stat-checked; symlinks, hardlinks with link count greater than1, FIFO/socket/device/unknown special types and unexpected device crossings fail the observation. The regular-file open includes O_NONBLOCK/O_NOCTTY and is followed by another type/identity check before reading.

Allowed text suffixes: swift,c,h,m,mm,rs,py,js,ts,tsx,md,txt. Hidden paths, .git/.env/.ssh, credential/secret/token/password/auth filenames, keys, caches/build/dist/node_modules/DerivedData/Pods/vendor/browser/profile locations, agent configuration, unknown types and binary suffixes are excluded. .gitignore is neither read nor trusted. Policy also rejects invalid UTF8, NUL/unsupported control characters, PEM material and several obvious credential assignment/token patterns. All errors are sanitized typed codes; production code does not log source text, secret contents or absolute paths. Diagnostics never contain raw file bytes.

**Sensitive content limitation:** suffix/name filtering and text heuristics cannot prove that arbitrary source contains no secrets. A credential disguised as ordinary Swift can evade them. Only synthetic safe data was assembled; nothing was disclosed to a provider or persisted. Production disclosure remains gated on explicit selection/review/consent, a privacy threat review and any additional secret-detection policy. Source comments remain untrusted repository data and cannot mint approval, alter limits or become system instructions.

## Limits and completeness

| Limit | Default | Configurable maximum |
|---|---:|---:|
| Observed regular + explicitly absent entries |100 |100 |
| Individual file bytes |256 KiB |256 KiB |
| Aggregate source bytes |4 MiB |4 MiB |
| Traversal depth below root |16 |32 |
| Enumeration work (all readdir entries, including dot/excluded entries) |4096 |16384 |
| Snapshot elapsed deadline |5000 ms |30000 ms |
| Accounted retained-data budget |8 MiB |8 MiB |
| Registry entries |32 |32 |

The100-entry cap preserves2B's approved limit; the suggested200 was not adopted silently. Byte/file/depth/work/duration/retention parameters validate at construction. Retention accounting conservatively charges source bytes, filenames, directory/path metadata, entry overhead and1MiB scratch allowance, including explicit absence metadata. The aggregate4MiB source cap remains independent. Array/String/runtime allocator overhead and transient copies are not a measured RSS bound or OS quota. These are per-observation limits; a caller retaining unlimited snapshots is outside the current managed resource model. There is no actor snapshot cache or content persistence.

Any exhausted scan/read budget, malformed selected path, invalid text, unsupported candidate, cancellation, deadline or consistency failure throws with **no snapshot result**. Incomplete enumeration never returns a partial apparently complete snapshot. Excluded subtree counts count exclusion roots, not uninspected descendants. There are zero automatic retries. The builder also checks an overall injected monotonic deadline before/after observation, during hashing and before returning the manifest. A controlled-clock regression advances time after the broker scan to prove that the builder rejects an expired whole operation. Registry and context construction are bounded separately; source disk operations themselves cannot be forcibly interrupted by the polled deadline.

## Snapshot and revision semantics

WorkspaceSnapshotBuilder consumes the Domain observation port, verifies returned project/selection/bounds/policy, hashes actual UTF8 bytes using SHA256 (including a leading BOM and decomposed Unicode code units), and reuses the version1 WorkspaceSnapshot/ExpectedFileRevision contracts unchanged. Per-file metadata includes relative path, regularUTF8 type, byte count, SHA256 revision, device/inode, mtime/ctime seconds/nanoseconds and metadataChecked consistency status. Files and entries use byte-stable path order. No model-declared hash is accepted as filesystem evidence.

The existing canonical2B content snapshot digest remains version1, with project identity, ordered relative paths and explicit present/absent content revisions. Identical content/path selections in two fixture roots retain that digest. A separate deterministic length-prefixed observation-v1 manifestDigest includes the content digest, observed root device/inode, excluded count and ordered file identity/size/type/consistency metadata. Repeated unchanged observations have the same manifest; host inode changes can change the manifest while leaving the content revision stable. No absolute root paths are included. Device/inode metadata is local observation data, not authority or a secret-safe export promise.

Creates require explicit absentCandidates. Absence is established only for the final component under existing verified parents, then rechecked; absence of an inventory entry is never proof of nonexistence. Unknown parents fail rather than manufacturing absence. Existing candidates are observed as regular files; combined present/absent count is capped100. The proposal integration accepts an ObservedWorkspaceSnapshot plus an exactly matching validation context; project, base snapshot, file revision, missing observation, existing create conflict and duplicate/conflicting target checks remain pure2B checks. The expected post-snapshot remains a prediction. Nothing writes files or issues an executable capability.

## Mutation, cancellation and filesystem limitations

The broker compares pre/post descriptor metadata and path metadata, verifies read byte counts, checks root/directory ownership/mode/device, revalidates all observed paths/directories/explicit absences after traversal, then reopens the registered root to reject relocation/replacement. Deterministic hooks simulate replacement, deletion, writes during reading, nested-directory swaps, directory mutation after enumeration, late earlier-file mutation, root disappearance and cancellation during chunks. Injected monotonic ticks exercise deadline failure without timing sleeps. No new production lock is used; the test clock uses a standard-library Mutex for its Sendable counter.

This is **not an atomic multi-file filesystem snapshot**. Another process may mutate files after their last check, change and restore state outside the observed interval, or move an opened directory. Descriptor checks prevent following symlinks and results fail on detected inconsistency; they do not create a filesystem transaction, perpetual ancestry lease or proof against privileged metadata manipulation. Reads remain historical, metadata-checked observations; refresh immediately before any future effect. Root identity uses device/inode, not durable volume UUID/generation/bookmark persistence. Inode reuse across long delays and mount/volume aliases require future persistent-registration design.

Hardlinks with multiple current names reject; link count cannot establish historical provenance of a single remaining link. Unexpected mount devices are rejected by the same policy tested with injected device identities; privileged mount/device-node creation was not attempted. Only local host fixture filesystem behavior is exercised. Unix socket nodes are bound only inside disposable fixtures, never listened on/connected to; FIFO and symlink probes do not block or disclose sibling content. Read-only special-file opening races and nonlocal/automounted paths still need platform-specific threat review before production selection. The local-filesystem check is not an OS egress policy.

Cancellation is polled between bounded steps/chunks and discards the result. A stalled kernel filesystem call can exceed the nominal elapsed deadline; there is no hard real-time cancellation or filesystem containment claim. An active actor scan finishes/stops before queued revocation takes effect. A caller already holding returned bytes cannot have those bytes retroactively erased. No TSan/Instruments, allocator peak/RSS quota, arbitrary malicious same-process code containment or adversarial privileged filesystem proof is claimed.

## Context assembly

ContextAssembler takes the trusted registry port, explicit project ID, observed snapshot, explicit selected paths and byte/token budgets. It never scans or opens files; it chooses whole-file excerpts from the bounded observation. It checks registration and observed-root identity before/after assembly, exact project identity, allowlist, target aliases, cancellation and budgets. Output contains selected relative references, content revisions, untrustedRepositoryText provenance, exact UTF8 excerpts, omitted paths, exclusion count and completeSelection/incompleteSelection. Missing/over-budget files are listed, never silently truncated. Complete means the explicit selection was assembled, not that excluded workspace files were read.

Token budgeting currently charges one unit per UTF8 byte, conservatively bounding returned bytes; it is not a verified provider tokenizer or a full request/context-window measurement. Phase1B.3 must account for its exact tokenizer, prompt/envelope/tool schema overhead, output reserve and model limits. No model/provider/HTTP route or prompt construction is implemented. Distinct provenance is preserved as data; a future UI/provider must preserve that distinction when rendering/serializing.

## Apple sources reviewed

- [Apple open(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html) documents read-only/no-follow/nonblocking descriptor behavior. [Apple fstat(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fstat.2.html) documents descriptor metadata. Installed Xcode27 SDK sys/fcntl.h and sys/stat.h confirm openat/fstatat declarations and no-follow/close-on-exec flags; actual builds exercise those declarations.
- [Apple App Sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) and [security-scoped bookmark creation](https://developer.apple.com/documentation/foundation/nsurl/bookmarkdata(options:includingresourcevaluesforkeys:relativeto:)) describe selected-resource access. Future trusted UI must explicitly select scoped roots, create/resolve scoped bookmarks where appropriate, handle stale resolution and balance start/stop accessing while broker resources are owned. A bookmark locates/extends OS access; it is not a restored task/disclosure/write grant. No bookmark entitlement or permission flow was added here.
- [Apple NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator) coordinates participating readers/writers/file presenters. It does not replace descriptor/path checks or compel an arbitrary nonparticipating writer. No coordinator or cloud/file-provider integration is introduced for local fixtures. That integration requires a separately reviewed resource/lifetime/deadline design.

The distinction between application policy and OS isolation remains mandatory. This broker mediates its own calls; arbitrary native code in the same process could call other APIs. No App Sandbox entitlement change, helper containment or general execution gate is established by these tests.

## Initial implementation verification (before checkpoint fixes)

Selected `/Applications/Xcode-beta.app/Contents/Developer` explicitly and removed inherited SDKROOT; default xcode-select still points to CommandLineTools and was not changed. Xcode27 beta/Swift6.4/macOS27 SDK on the Apple Silicon host; Swift6 language mode, complete strict concurrency and macOS26.0 deployment settings checked. Actual macOS26 runtime and Swift6.2.3/full Xcode26.3 compatibility are **NOT TESTED**.

| Initial implementation run | Exit | Result |
|---|---:|---|
| accepted-complete-focused, native WorkspaceTests |0 |79 functions /206 cases; zero failures/skips |
| accepted-complete-full |0 |192 functions /557 cases; zero failures/skips |
| accepted-complete-replay, test-without-building |0 |192 functions /557 cases; zero failures/skips |
| accepted-complete-debug |0 |Debug app BUILD SUCCEEDED |
| accepted-complete-release |0 |Release app BUILD SUCCEEDED |
| accepted-complete-release-tests |0 |TEST BUILD SUCCEEDED: isolated optimized QA compilation of all modules/test bundles; ENABLE_TESTABILITY=YES only for this QA command |

Focused sub-results: registry7 functions/12 cases; filesystem17/36; snapshot10/11; context6/22; proposal integration2/2. These42/83 new cases run alongside all existing37/1232B cases. Full/replay preserve all474 earlier cases, including Phase1A approval expiry/revocation, cancellation, persistence recovery/shutdown/no-duplicate execution and1B.1 fixture transport/session tests. Descriptor cleanup is checked across200 repeated failure paths with a32-descriptor allowance for concurrent test-runner activity; it is a leak regression, not a formal lifetime proof. No arbitrary sleeps were added.

Initial focused build exited65 on one new test's missing TaskIdentifier rawValue label; no tests executed. The next run exited65 on one expected error-type mismatch (excluded selection leaked a2B invalidPath error). Corrected the call and normalized selection errors without weakening assertions. Review strengthened registry revocation checks in assembly and added root/descriptor/boundary tests. Intermediate passing69-function runs are preserved but are not the final-source acceptance records. Final review added snapshotFromDifferentRootWithSameProjectIDIsRejected before correcting a concrete defect: project ID alone allowed a new registry's different root to accept the earlier snapshot. root-binding-regression-before exited65 with one failing function (6 functions/22 context cases). The unchanged regression now requires the registered root device/inode to match the observed root, checked before and after assembly. The first incremental corrected-focused build exited65 because the imported cached Domain interface lacked the newly added members; no tests ran. Fresh Accepted build output is used for final-source verification; previous553/554/556-case records are preserved as pre-correction evidence, not final acceptance. A synthetic byte-conversion check then showed Foundation's UTF8 initializer strips a leading BOM. The new BOM/decomposed-Unicode regression (accepted-bom-before) exited65 with one failing argument case in17 filesystem functions/36 cases: the old implementation rejected valid BOM text as inconsistent at final byte-count revalidation; no incorrect successful snapshot escaped. The broker now validates UTF8 and constructs the String from validated standard-library code units, preserving the BOM exactly. The first BOM attempt against the old build lane (bom-regression-before) repeated the stale-interface compilation failure and ran zero tests. All failed runs remain preserved. Final acceptance above uses unchanged source hashes. No failure is hidden or counted as success.

Native result summaries/trees show runtimeWarnings empty. Nonfatal host AppIntents metadata and linkd.autoShortcut diagnostics remain in raw logs; they are not Swift concurrency warnings. Ordinary Release app build does not link Workspace; the additional optimized QA compilation covers Workspace and all new source/test modules without changing production build settings. Release tests are not executed; Debug tests are the behavioral proof.

### Commands and evidence

Ignored `Evidence/Phase1B2C/` contains exact argv/cwd/environment/toolchain selection, timestamps, exit codes, source/fixture hashes, raw logs and xcresult bundles. Each named run has a JSON execution record. All ran from `$REPO_ROOT` with DEVELOPER_DIR set as above and SDKROOT absent. Common argv:

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/Phase1B2C-Accepted -disableAutomaticPackageResolution -skipPackageUpdates
```

Append the following suffixes (result paths are absolute under `$REPO_ROOT/Evidence/Phase1B2C/`):

| Record | Suffix after common argv |
|---|---|
| accepted-complete-focused | `-configuration Debug -resultBundlePath <evidence>/accepted-complete-focused.xcresult -only-testing:WorkspaceTests test` |
| accepted-complete-full | `-configuration Debug -resultBundlePath <evidence>/accepted-complete-full.xcresult test` |
| accepted-complete-replay | `-configuration Debug -resultBundlePath <evidence>/accepted-complete-replay.xcresult test-without-building` |
| accepted-complete-debug | `-configuration Debug -resultBundlePath <evidence>/accepted-complete-debug.xcresult build` |
| accepted-complete-release | `-configuration Release -resultBundlePath <evidence>/accepted-complete-release.xcresult build` |
| accepted-complete-release-tests | `-configuration Release -resultBundlePath <evidence>/accepted-complete-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES` |

Optimized QA uses separate DerivedData/Phase1B2C-Accepted-ReleaseTests. Replaying tests immediately after the full run preserves all test artifacts; normal app-only builds can replace test products, so rebuild the test action before a later replay. The preserved verification-runner.py and inspection records contain fully expanded actual command arrays; result bundle destinations must be new for another run.

Fully expanded final command lines (DEVELOPER_DIR explicitly selected and SDKROOT absent):

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2C-Accepted -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1B2C/accepted-complete-focused.xcresult -only-testing:WorkspaceTests test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2C-Accepted -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1B2C/accepted-complete-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2C-Accepted -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1B2C/accepted-complete-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2C-Accepted -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1B2C/accepted-complete-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2C-Accepted -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1B2C/accepted-complete-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2C-Accepted-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1B2C/accepted-complete-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```

Counts were independently extracted using `/usr/bin/xcrun xcresulttool get test-results summary --path <bundle>` and corresponding `tests`; Test Case functions and expanded Arguments cases are counted separately. Static review records `swift package --package-path Packages/WesleyFlowCore dump-package`, `xcodebuild -showBuildSettings -json`, SDK/toolchain/host queries, project-object comparison, baseline SHA256 preservation, import/side-effect inspection and `git diff --check` with actual exits. No prior source/test assertion or setting was deleted or weakened.

## Requirement disposition and remaining gates

| Area | Status |
|---|---|
| Explicit fixture registration/revocation/availability and root conflict checks |COMPLETE |
| Descriptor-mediated bounded reads, allowlist, typed failures and cleanup |COMPLETE for tested local fixtures |
| Deterministic snapshots, actual-byte revisions and explicit absence |COMPLETE |
| Mutation/cancellation/deadline checks |COMPLETE as cooperative metadata checks; atomic snapshot/hard interrupt not claimed |
| Context selection/budgets/provenance/completeness and revocation fencing |COMPLETE |
| Existing proposal validation integration with observed snapshots |COMPLETE; no effect authority |
| Focused/full/replay/Debug/Release/module/concurrency verification |COMPLETE on available toolchain; optimized QA status above |
| Real UI selection/scoped bookmarks/durable registry |DEFERRED by fixture scope |
| Provider-specific token accounting, actual disclosure/privacy approval |DEFERRED to separately authorized provider milestone |
| Actual mount/device adversarial probes, macOS26/Swift6.2.3, TSan/RSS |NOT TESTED |
| Live inference/productive writes/process execution/OS containment |NOT AUTHORIZED and disabled |

At initial implementation delivery Git remained on main at the starting HEAD. Nine intended changed/new paths (four existing modified, five added), no staged files; generated Evidence/DerivedData remain ignored. Final static inventory/hash evidence records exact status. No commit, push, remote creation, unrelated file deletion or Phase1B.3 implementation.

**Recommendation:** the read-only fixture foundation is ready for independent review and separately scoped Phase1B.3 work. Keep live disclosure/inference disabled until explicit review/selection consent, exact provider/token/resource/cancellation controls and the next milestone's tests are authorized and pass. This is not readiness for unrestricted AI coding. File modification and generated-code command execution remain separately gated under1B.4/containment requirements. Stop after1B.2C.

## Final engineering review and local checkpoint

Review decision: **PASS after two reproduced Phase1B.2C defects were corrected. No remaining P0/P1 finding within the fixture-only checkpoint scope.** Initial206/557/557 evidence matches the nine-path checkpoint-start inventory. Those execution records are preserved as historical evidence; the corrected implementation is verified below.

### Confirmed findings and corrections

| ID / severity | File and location | Actual problem and execution evidence | Correction |
|---|---|---|---|
| C1 / P1, fixed | `Packages/WesleyFlowCore/Sources/Workspace/WorkspaceSnapshotBuilder.swift:116` | ContextAssembler checked cancellation before its final asynchronous registry call, but could return context if cancellation arrived during that await. The actor-handshake regression cancelled exactly while final validation was suspended, released it, and observed a successful return. `accepted-review-regression-before`: exit65,7 functions/23 cases, one failing function/issue. This reproduces a cancellation contract defect, not a demonstrated external disclosure. | Recheck Task.isCancelled after final registry validation and before returning context. Preserve the unchanged regression with actor-owned CheckedContinuations and no sleeps/unsafe continuations. |
| C2 / P1, fixed | `Packages/WesleyFlowCore/Sources/SystemOperations/ReadOnlyWorkspaceBroker.swift:60` | Broad/protected-root deny rules compared case-sensitive spellings, permitting case variants through the pre-open lexical guard. Extracted the unchanged guard into a pure internal rootComponents seam, then reproduced seven accepted forbidden spellings. `accepted-root-policy-before`: exit65,8 functions/19 cases, one failing parameterized function/seven issues. The test opens no protected root; filesystem consequences depend on volume equivalence and later OS checks. No home/system read or OS escape was claimed. | Conservatively lowercase the root, home and protected-prefix comparisons, including broad Users/private roots, before any descriptor opens. Descriptor identity/no-follow checks remain unchanged. This is not a complete model of all filesystem aliases. |

Only the two reviewed production files and the new2C test file changed from the implementation draft. AGENTS records this checkpoint authorization; this report records review results. Domain observation data, existing proposal validation/hashing, package manifest, app, prior Phase1A/1B.1/1B.2B source/tests, persistent schemas, signing/entitlements and the original standalone containment experiment remain unchanged. No assertion was removed or weakened. Two functions/eight cases were added; all prior557 cases remain, for565 total. Overall2C adds44 functions/91 cases to the474-case pre2C baseline.

### Security and architecture review

Reviewed all nine pending paths, the full new Swift implementation/tests, architecture/security policy, package and project memberships, root and leaf open/stat/read paths, error cleanup, snapshot normalization/hashing, explicit absence and proposal integration. SystemOperations exclusively opens source files through no-follow descriptor-relative traversal. Root replacement fails identity validation; symlink/directory/file swaps and detected mutation discard the snapshot. All descriptor acquisitions have matching ownership transfer/defer cleanup, including fdopendir failures and partial-read/encoding/limit/cancellation failures. No retained descriptor is stored in registration/snapshot/context data.

Existing fixture regressions cover root replacement, nested symlinks, sibling targets, FIFOs/sockets, hardlinks, directory mutation, changed/deleted/replaced files, chunk cancellation, repeated failure descriptor accounting, limits, BOM/decomposed Unicode, independent SHA256 vectors, omitted context, wrong-project/root/revision conflicts and unchanged permission-broker denial of productive operations. Files are hashed from immutable validated bytes captured by the broker. A filesystem change during later hashing can make that historical observation stale; this is the already documented non-atomic limitation, not a current-state lease or permission to apply a patch. No claim of a fully atomic snapshot was found.

No new write, subprocess or networking API, external dependency, provider activation, automatic real-project discovery, credentials or generated artifact is included in the reviewed implementation. Source content remains transient untrusted data; model-facing references are relative. Tests operate only on owned disposable fixture roots; protected-root case tests are pure string policy checks. App composition exposes no operational read/provider/effect workflow. Public identifiers/manifests/results are data, not write/process authority. Mutable broker state and test-gate state are actor isolated; immutable values/clock callbacks are Sendable. No production lock, unchecked Sendable, unsafe continuation or concurrency suppression was introduced.

Remaining limitations are **P2/future gates**, not reproduced extra defects: metadata checks cannot make multi-file snapshots atomic or permanently current; inode reuse/firm-link and mount aliases and special-open races need production-platform review; single-link history cannot be proved; source heuristics cannot guarantee secret absence; filesystem syscalls cannot be forcibly interrupted; registry revocation is serialized with an active scan; byte-based token units are not provider tokenizer accounting; resource budgets are per-observation application accounting rather than measured/hard OS RSS/session quotas. Actual macOS26/Swift6.2.3 compatibility, privileged mount/device probes, TSan/Instruments and OS containment remain untested. No live inference or productive operation is authorized by these results.

### New checkpoint verification

All final commands exited0 and their code/fixture hashes match the reviewed source:

| Run | Exit | Actual result |
|---|---:|---|
| accepted-review-focused |0 |81 functions /214 cases; zero failures/skips |
| accepted-review-full |0 |194 functions /565 cases; zero failures/skips |
| accepted-review-replay |0 |Independent test-without-building;194 functions /565 cases; zero failures/skips |
| accepted-review-debug |0 |Debug BUILD SUCCEEDED |
| accepted-review-release |0 |Release app BUILD SUCCEEDED |
| accepted-review-release-tests |0 |Optimized TEST BUILD SUCCEEDED for modules/test bundles, ENABLE_TESTABILITY=YES for QA only; no Release tests executed |
| Package/settings/module/project/preservation/Git checks |0 |No external dependencies; adapters→Domain; previous sources/tests/settings preserved; Swift6/complete strict concurrency/macOS26.0 |

Xcode27.0 build27A5237l, Swift6.4, SDK27.0, Apple Silicon host macOS27.2. Inherited SDKROOT removed; explicit DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer; no global toolchain/security change. Test-result runtimeWarnings are empty. Nonfatal AppIntents/linkd host diagnostics remain in raw logs; no new Swift concurrency warning. Ordinary Release app build does not link Workspace; isolated optimized QA compiles the new Workspace implementation/tests. This does not close the older compiler or macOS26 runtime gates.

Evidence lives in ignored `Evidence/Phase1B2CCheckpoint/`: per-run exact argv/cwd/timestamps/exit codes/hashes, raw logs/xcresult, extracted summaries/trees, regression failures, initial inventory, dependency/settings/preservation inspection, full staged patch/index hashes and final commit/status records. The two failing regressions are not counted as accepted runs. Source hashes intentionally differ between before-fix failures and final success. Original `Evidence/Phase1B2C/` remains preserved.

Actual final command lines, run from `$REPO_ROOT` with the explicit environment above:

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2CCheckpoint-Accepted -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1B2CCheckpoint/accepted-review-focused.xcresult -only-testing:WorkspaceTests test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2CCheckpoint-Accepted -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1B2CCheckpoint/accepted-review-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2CCheckpoint-Accepted -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1B2CCheckpoint/accepted-review-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2CCheckpoint-Accepted -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1B2CCheckpoint/accepted-review-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2CCheckpoint-Accepted -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1B2CCheckpoint/accepted-review-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2CCheckpoint-Accepted-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1B2CCheckpoint/accepted-review-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```

The runner uses fresh DerivedData/Phase1B2CCheckpoint-Accepted and separate Phase1B2CCheckpoint-Accepted-ReleaseTests for optimized QA. Summary/tree extraction uses xcrun xcresulttool get test-results summary/tests with the corresponding result path; exact arrays/exits are retained. Native function counts and expanded argument cases are reported separately.

### Checkpoint scope and readiness

The reviewed checkpoint contains exactly nine paths: AGENTS.md; Docs/Phase1B/ARCHITECTURE.md, SECURITY-BOUNDARIES.md and this completion report; Domain/WorkspaceObservation.swift; SystemOperations/ReadOnlyWorkspaceBroker.swift; Workspace/WorkspaceSnapshotBuilder.swift; WorkspaceTests/ContextObservationTests.swift; and WesleyFlow.xcodeproj/project.pbxproj. No generated Evidence, DerivedData, credentials, private file content or unrelated change is staged. Complete staged content is checked against the reviewed working files before the single authorized local commit. The commit cannot embed its own hash; the final response and ignored checkpoint.json record its actual hash and post-commit clean status.

Approved checkpoint message: `feat(workspace): add secure read-only project context`. No push or remote creation. **Ready for separately authorized Phase1B.3 work with privacy/selection consent and provider/token/resource/cancellation gates still required before live disclosure/inference.** Not ready for unrestricted AI coding or productive file/command effects. Stop after this checkpoint; no Phase1B.3 implementation.
