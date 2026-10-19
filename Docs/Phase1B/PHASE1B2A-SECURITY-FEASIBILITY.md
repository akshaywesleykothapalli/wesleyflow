# Phase 1B.2A — OS containment feasibility

19 October 2026 · **B. NATIVE HELPER INSUFFICIENT for the required future coding-agent boundary.**

The tested App Sandbox profile enforces useful filesystem and network restrictions. It does not supply a task-root boundary, an executable allowlist, automatic descendant termination, or resource quotas. Keep OpenCode disabled. The finalization request **adopts proposal-only inference with Wesley Flow-controlled operations** as the reduced architecture; implementation still needs separate scope approval. This finding rejects the tested helper as a complete boundary; it does not establish that every possible native XPC architecture is infeasible.

## Scope and preservation

Started on clean `main`, HEAD `08a5006bfa6c63bf52f02d1762a31f1a28e4ae79`. Reviewed AGENTS, Phase1B architecture/security/lifecycle/risks, Phase1B1 protocol/checkpoint and actual Domain runtime, fixture transport/session, permission and lifecycle contracts. The repository's design/security findings were inputs; no standalone full Nemotron audit was available locally. This is an empirical feasibility assessment, not an independent external certification.

Only a standalone experiment, this report, the containment ADR, and current-scope AGENTS guidance were added. Hash verification preserved all 83 other original tracked files, including app/package/project/test sources and previous documents. No production target, dependency, authority, permission contract or runtime wiring changed. No OpenCode, inference, personal configuration, private-data probes, privileged service, system-security changes, commit, remote or push. Native Codex approval allowed same-user fixture execution; no sudo was used.

## Options evaluated

| Dimension | Sandboxed XPC service | Sandbox-inheriting child | Isolated macOS VM | Proposal-only inference |
|---|---|---|---|---|
| OS boundary | Separate signed service sandbox; XPC alone is insufficient | App Sandbox parent plus correctly entitled embedded child; tested here | Guest boundary with deliberately restricted host integration; untested here | No untrusted tool process; model output is inert data |
| Files | Own service container; broker must mediate selected bytes | Own parent container, not a per-task subtree | Separate guest disk; no host mounts; snapshot transfer needs validation | Trusted broker reads only separately approved context |
| Processes | Separate service privileges; arbitrary descendant stop remains unproven | Inherited denials observed; system executable permitted; child survived parent death | Guest termination could close guest processes; must verify guest stop | No model-created subprocess; later broker commands need separate containment |
| Network | Omit network rights; typed trusted relay is a candidate | No-network profile denied local probes; network.client allowed changing local ports | Omit NIC or independently constrain relay; untested | WF-owned selected-provider transport; no arbitrary model-specified destinations |
| Signing | Signed embedded service and independently minimal entitlements, client authentication | Signed parent, child sandbox+inherit; demonstrated ad-hoc only | Virtualization entitlement, guest image/configuration and signing checks | Existing app signing plus any future narrowly scoped helper |
| Resource cost | Expected process/IPC overhead; not measured | Main helper ~7.64–7.80 MiB peak RSS; not aggregate | Guest RAM/disk/boot/toolchain overhead unmeasured on 16 GiB | Expected lower overhead without tool runtime/guest; model cost unmeasured |
| Complexity | Medium/high: peer validation, bounded IPC, ownership and shutdown | Small experiment; secure general worker remains substantially harder | High: provisioning, lifecycle, guest verification, transfers and networking | Smaller execution surface; secure proposal/context/broker/provider work still required |
| macOS 26 | Documented API candidate; actual macOS26 run absent | Deployment26 compiled; tested on macOS27.2 only | Documented Apple silicon candidate; no guest provisioned/tested | Native architecture compatible in principle; release/runtime lane still open |
| Maintenance | Entitlement/IPC/signing and OS regression tests | Packaging, child rights, supervisor and OS regressions | Images, guest OS/Xcode updates and resource admission | Provider schema, hostile proposal validation and broker verification |
| Disposition | Candidate for a restricted proposal component, not qualified for OpenCode | Insufficient as the complete agent boundary | Separate investigation only | Recommended reduced design, not implemented here |

Apple describes XPC privilege separation and service-specific sandboxes; this supports evaluating a minimal service, not claiming tested service behavior. [Creating XPC Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html). Apple's child entitlement rules distinguish static inherited rights from later user-granted access. [Enabling App Sandbox](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html). App Sandbox limits resource access while retaining a writable container. [Protecting user data](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox). Outgoing network entitlement covers local as well as remote connection initiation, rather than a destination allowlist. [network.client](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client). Apple's macOS VM sample documents guest provisioning; no VM was installed or measured here. [macOS on Apple silicon](https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon). Cost/production suitability comparisons above are engineering inferences, not measured Apple guarantees.

## Prototype and signing

`Experiments/Containment/` is outside all production targets. One independently written MainActor Swift executable performs fixed POSIX synthetic file/socket probes and launches only benign fixture helpers or `/usr/bin/true`. It does not accept arbitrary executable/argv requests. A token guard prevents accidental probes outside runner-created paths; every reported negative operation passed that guard and actually reached its file/socket/process call. Blocking pipe/wait operations are experiment-only, not a production supervisor design.

Three disposable app bundles use the same Debug binary:

| Profile | Main entitlements | Embedded child entitlements |
|---|---|---|
| Control | Empty dictionary, no sandbox | app-sandbox=true, inherit=true |
| Sandbox | app-sandbox=true only | app-sandbox=true, inherit=true |
| NetworkClient | app-sandbox=true, network.client=true | app-sandbox=true, inherit=true |

Ad-hoc codesign, deep/strict verification, displayed entitlements and self-inspection through SecCodeCopySelf/StaticCode/SigningInformation all succeeded. Main sandbox profiles reported sandbox=1; children reported inherit=1. Supported signing inspection establishes code metadata, not independently a kernel sandbox verdict. Effective restrictions are evidenced by actual operation results against an unsandboxed positive control and by the separately running child. Sandbox-specific NSTemporaryDirectory resolved into the profile's own container. No private sandbox APIs, sandbox-exec profiles, TCC changes or security exceptions were used.

Fixtures use fresh unique `wf-containment-<UUID>` roots. Approved/config/output directories reside under the helper's own temporary directory; denied/unrelated fixtures reside in the runner's temporary root outside its container. A second unrelated fixture inside the container characterizes granularity. No security-scoped bookmark/PowerBox access or actual host project grant was tested. Known-content files, a symlink into an outside fixture, and a symlink-plus-`..` traversal are positively readable in Control, preventing a missing-fixture false denial. The local listener binds only 127.0.0.1 and an ephemeral port; no probe contacts an external server.

## Actual boundary observations

Final run: **16 scenarios / 227 characterization assertions, zero failed assertions**, exit0. Ten boundary scenarios: three repetitions of each profile, plus one same-container sibling test. Six lifecycle scenarios are below. These assertions validate observations, including security limitations; they are not 227 security requirements passed.

| Attempt | Control | Sandbox | NetworkClient |
|---|---|---|---|
| Approved/config reads | 18 bytes, content matched | Same | Same |
| Approved/output writes | 16 bytes | Same | Same |
| Outside read/write | 18/16 bytes | -1, errno1 EPERM | -1, errno1 EPERM |
| Outside unrelated read | 18 bytes | -1, errno1 | -1, errno1 |
| Symlink escape and symlink/`..` traversal | 18 bytes each | -1, errno1 each | -1, errno1 each |
| Local socket/connect probe | result0; listener received payload | -1, errno1; zero accepts | result0; listener received payload |
| Proper inheriting child | Started, then signal5; no valid sandbox parent | Exit0; outside file and local-network denials reproduced | Exit0; file denials reproduced, local network permitted |
| Non-inheriting copied executable inside/outside | Both exit0 | Both launch attempts rejected, NSCocoaErrorDomain4 | Same rejection |
| Fixed `/usr/bin/true` outside WF executable allowlist | Exit0 | **Exit0** | **Exit0** |

The two copied executables retained the Control executable's ad-hoc signature but lacked sandbox/inherit rights. The Foundation launch errors are recorded as domain/code, not invented POSIX errno or proof that every executable is denied. Conversely, `/usr/bin/true` demonstrably ran: no general executable allowlist exists in the tested profile. The inherit-only child's signal5 under an unsandboxed parent is an observed invalid-parent disposition; no specific kernel reason was independently retrieved. The initial harness expected exit0 for that control and failed; corrected characterization retained the failure evidence rather than weakening the sandbox-parent checks.

The same-container sibling read returned 18 matching bytes in Sandbox and its child. Thus “unrelated to this task” does not imply OS-denied access inside a shared container. A fresh restricted worker with no valuable shared contents could reduce exposure, but that design and its identity/configuration lifecycle are untested.

NetworkClient reached three changing loopback ports across repetitions; parent and inheriting child each delivered a payload (two accepts/run). Sandbox had zero accepts. This proves the tested local denial and inheritance, not exhaustive WAN/UDP/Unix-socket/IPC denial. No client entitlement should be granted merely to reach local inference: a future authenticated, bounded relay must avoid granting arbitrary socket authority. No descriptor-passing network escape was tested.

## Termination and resources

The child first confirms a held exclusive synthetic lock. The runner checks that a second owner cannot acquire it, registers a kernel kqueue NOTE_EXIT notification for the exact live child PID, verifies its executable with proc_pidpath, and observes lock acquisition after exit. These are stronger than a cleanup acknowledgement. Parent processes are waited/reaped with actual exits. Signals target only the recorded owned process, never a user daemon or stale arbitrary PID.

| Scenario | Observed result | Final elapsed seconds |
|---|---|---:|
| Normal completion | All ten boundary parents exit0; fixture child results recorded | Not a performance benchmark |
| Cancellation | SIGTERM child status15, kernel exit, lock released, parent exit0 | 0.0911 |
| Operational timeout | 0.2 s readiness deadline fires; cancellation stops child, parent exit0 | 0.2925 |
| Repeated cancellation | Two stopped acknowledgements for the same exited child; parent exit0 | 0.0819 |
| Parent stdin shutdown | Cleanup runs, child exit observed, parent exit0 | 0.0836 |
| Forced child | SIGKILL child status9 observed; subsequent cancel/quit remain valid, parent exit0 | 0.0192 |
| Forced parent | Parent exit-9; child remains alive and retains lock; runner kills owned child, observes exit and lock release | 0.0192 including cleanup |

**Forced parent death did not automatically clean the descendant.** The child remains sandboxed; survival is not a demonstrated sandbox escape, but violates automatic all-resources-stopped assumptions. No `.stopped` production contract was added. This process result must not be attributed to an untested XPC service's different lifetime management.

Ordering uses pipe readiness/identity/lock handshakes and kernel events. The 0.2 s timeout is the condition under test, not a sleep to make assertions pass. Harness bounds are 8 s per input record, 2 s per cancellation acknowledgement, 3 s for parent wait/child exit; they are test watchdogs, not an implemented shared 2+3 s production cleanup budget. Observed times include setup and are not worst-case guarantees. General adversarial descendant escape, pipe floods, signal refusal, provider stop, crash reconciliation and quota exhaustion remain untested. A production supervisor must provide bounded concurrent draining/escalation and quarantine uncertainty.

All 32 final fixture roots were disposed after the tests; 34 earlier retained synthetic roots were subsequently removed using the recorded manifest. No whole sandbox container was deleted: OS-created container metadata remains. Every observed held child exited and released its lock. No content-erasure or backup guarantee is claimed.

## Verification and reproduction

Evidence root: `Evidence/Phase1B2A/` (ignored, retained locally). Final helper build `Build-2efb2c9e0463`; final run `Run-7b91a151c952/results.json`. `latest-build.json`, `latest-run.json`, `containment-invocation.json`, `review-results.json`, named command JSON/logs and xcresult bundles retain exact argv, exits and source hashes.

Host: Apple M4, Mac16,12, 17,179,869,184 bytes RAM (16 GiB), macOS27.2 build26B5112a. Toolchain: `/Applications/Xcode-beta.app/Contents/Developer`, Xcode27.0 build27A5237l, Swift6.4, SDK27.0; target arm64-apple-macos26.0, Swift6. Strict concurrency complete; no new suppression or UnsafeContinuation.

| Verification | Exit | Result |
|---|---:|---|
| Helper Debug compile (`-Onone -g`) | 0 | Strict Swift6 compilation |
| Helper Release compile (`-O`) | 0 | Strict Swift6 compilation; Release helper not executed |
| Sign/verify/inspect three bundles and children | All 0 | Exact commands and entitlement output retained |
| Final containment invocation | 0 | 16 scenarios, 227 assertions, 0 failures; security limitations reproduced |
| Complete existing suite | 0 | 113 functions / **351 concrete cases**, zero failures/skips; xcresult independently extracted |
| Application Debug build | 0 | BUILD SUCCEEDED |
| Application Release build | 0 | BUILD SUCCEEDED |
| Original-file hash comparison | 0 | Only AGENTS changed among 84 original tracked paths |

The full suite includes Domain, composition, Phase1A policy/recovery/cancellation and fixture CodingAgents tests. Passing those tests is regression evidence, not OS security evidence. AppIntents metadata warnings and host linkd diagnostics remain in logs; result extraction reports no runtime warnings. Compiler logs show the full Xcode SDK, Swift6 and existing strict-concurrency settings. App builds do not include experimental sources.

From repository root, the executed entry points were:

```sh
/usr/bin/python3 Experiments/Containment/build_probe.py
/usr/bin/python3 Experiments/Containment/run_experiment.py
/usr/bin/python3 Evidence/Phase1B2A/verification-runner.py full test
/usr/bin/python3 Evidence/Phase1B2A/verification-runner.py debug build
/usr/bin/python3 Evidence/Phase1B2A/verification-runner.py release build
/usr/bin/python3 Evidence/Phase1B2A/result-extraction.py
```

The runner copies were retained after their equivalent temporary script paths ran. For full/debug/release each underlying argv is `/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1B2A -disableAutomaticPackageResolution -skipPackageUpdates -configuration <Debug|Release> -resultBundlePath <absolute Evidence/Phase1B2A/name.xcresult> <test|build>` with explicit DEVELOPER_DIR. JSON preserves array boundaries, exact names and timestamps; use fresh evidence/result paths for another run. Result extraction uses `xcrun xcresulttool get test-results summary/tests --path <full.xcresult>`, both exit0, counting argument leaves rather than only function totals.

An unqualified SDK metadata query failed exit1 because inherited SDKROOT pointed to missing CommandLineTools SDK. No failed query is reported as successful. Corrected `xcrun --sdk macosx --show-sdk-path/--show-sdk-version` with SDKROOT removed both exit0. Final helper compilation explicitly supplies that full-Xcode `-sdk`; app compiler logs independently confirm MacOSX27.0.sdk. The original harness control expectation failed exit1, followed by successful 185-assertion characterization, then two final 227-assertion runs; the last uses the explicit SDK. A conservative old-fixture cleanup guard also stopped on the Control temporary-root spelling; it was corrected to permit only recorded experiment roots. These investigation failures remain recorded and do not indicate a passing complete security gate.

Helper source SHA256: `ea0c7c821aab5a03f659452accbe0c3e29dbc96b9618eed45812a14208c97fd8`.
Harness SHA256: `8c170494124a37aba0b0c14eb4444939de9593203d0279dc37e610cc528798fd`.

Main-process getrusage peak RSS ranged **8,011,776–8,175,616 bytes** in the final boundary runs. This excludes descendants, providers, allocator transients elsewhere and all guest/runtime/model memory. It proves neither an OpenCode budget nor the architecture's 8 GiB aggregate incremental / 4 GiB headroom gate. CPU/disk/FD caps and 30-minute sustained pressure tests were not performed. No VM performance estimate qualifies the 16 GiB device.

## Production recommendation and blockers

The accompanying ADR is **adopted by the subsequent explicit finalization request**, not authorization to implement it. Keep proposal generation without OpenCode tools; preserve Domain inward dependencies, untrusted data-only proposals, exact one-use broker authority, revocation, durable intent/receipt ordering and independent verification. No model should receive a host root, process runner, credentials, approval issuer or generic relay. Actual broker effects and build scripts remain gated until their own accepted containment and revision/evidence contracts exist.

Before any live execution: demonstrate authenticated minimal XPC/relay or a separately investigated macOS guest; close host-sharing/configuration/plugin/network/descriptor channels; enforce per-session resource limits; prove descendant/provider stop and quarantine within the shared deadline; validate distribution signing and actual macOS26 behavior; pass the 16 GiB model/worker budget; and separately authorize the exact live scope. Full Xcode26.3/Swift6.2.3 floor, stable signing/notarization, installed OpenCode packaging/conformance and native build verification isolation remain NOT TESTED.

At experiment close Git remained on the original checkpoint with AGENTS modified and the experiment/report/ADR untracked; index untouched, no commit/push. That dated status is historical. The separate finalization request authorizes one reviewed local checkpoint; see [pivot report](ARCHITECTURE-PIVOT-REPORT.md) for finalization verification and current scope. Original experiment status/preservation manifests remain retained in evidence. **Phase1B.2A ends here. Native OpenCode integration and broad Phase1B.2 remain HOLD.**
