# Wesley Flow project instructions

## Scope and approval gates

Independent greenfield native macOS application. Do not inspect, copy, import, migrate or reuse previous Wesley Flow, LocalFlow or DailyOps implementation. Platform documentation and standard APIs are allowed.

Current status: Phase 0A amended documentation complete; architectural review accepts the design with explicit implementation gates. **Architectural acceptance does not authorize implementation. Phase 0B requires separate explicit user authorization naming repository/location, minimal shell, Domain tests and build/test/launch scope.** No approval is implied by packet status or reviewer verdict. Each later phase also needs explicit authorization. Stop after this documentation task; do not create app source/Xcode project/Git repository, install dependencies, implement runtime or run application builds/tests.

## Engineering constraints

- macOS 26.0 minimum, arm64, SwiftUI/AppKit, M4/16 GB. Follow ENVIRONMENT's coherent compiler/SDK lanes, package tools 6.2 and compiler 6.2.3 source floor, explicit Swift 6 mode, strict concurrency. Shared/core defaults nonisolated; UI explicit MainActor. Record isolation/upcoming-feature flags; no extra opt-ins initially.
- Honor ARCHITECTURE's dependency allowlist and target responsibilities. Add modules/ports only with real consumer/tests. Domain has no UI/Speech/persistence/model/process dependencies. Model providers and coding runtimes stay independent.
- Voice produces editable data only; explicit review/submission does not grant effects. Website/project/transcript/model/tool content is untrusted. Only trusted approval UI can mint one-use scoped broker grants; macOS consent is separate.
- System effects go through broker; Workspace proposes, SystemOperations applies; no unrestricted executor/grant issuer in CodingAgents. Shell strings from model text are forbidden. Arbitrary processes/builds/tests remain disabled until the separate execution ADR/mode and user approval. Untrusted autonomous work requires demonstrated OS isolation; never equate XPC/process groups/signing with containment.
- One productive task/operation; FIFO 16 waiting, workspace leases/alias checks, post-await generation/state checks and immutable sequential workflow snapshots. Enforce 20 turns/50 requests/2 retries/15-minute execution/5-minute process/approval maxima; model content cannot raise limits.
- Revocation/cleanup works despite history failure. Apply 2-second graceful + 3-second escalation cleanup; report survivors, quarantine unsafe resources and reject late callbacks. Never restore approval or replay uncertain effects on restart.
- Local-only SwiftData v1 actor, explicit state+event saves, rollback/uniqueness, preservation on corrupt/migration failure. Sanitize evidence by default; sensitive patches/logs need scoped opt-in. Enforce 30-day/100 MiB retention, 10 MiB reserve, 1 MiB captured log cap and quota blocking.
- Adopt provisional 8 GiB aggregate incremental model/system speech/tool budget and 4 GiB admission headroom; include KV/scratch/load peaks. One model lease, serialize until measured, unload before heavy verification; no core model requirement. No fabricated model-fit/performance claim.
- No silent remote inference/transcription, raw audio retention or speculative OS permissions. Explicit asset provisioning only; speech fallback must be validated on-device or typed input.
- Respect user changes; no routine destructive cleanup, speculative scaffolding, empty targets, fake history or claims based on mocks.

## Verification and reporting

After separately authorized implementation, recapture exact installed environment and use explicit developer-directory override without changing global selection. G0 requires actual Debug/Release builds, exhaustive Domain and composition tests (zero failures/skips), shared scheme/results and actual launch; unavailable launch means incomplete. GC requires separate older full-Xcode and real macOS 26.0 evidence; pending lanes block compatibility claims. G1/GV/GM/GE/GR gate their corresponding features/release.

Never report code generation, test discovery or a planned command as successful execution. Preserve raw results and require independent execution-result inspection/rerun under authorized scope. Distinguish unit doubles, real integration, launch, compatibility, permissions and signing. Keep secrets/weights/build products out of Git. Explicit user requirements take precedence; explain actual conflicts and continue unaffected authorized documentation only.
