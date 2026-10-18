# Architecture decision records

All decisions below are proposed pending architecture review.

| ID | Decision | Rationale and consequences | Revisit when |
|---|---|---|---|
| 001 | Independent native SwiftUI app with selective AppKit | Fits macOS lifecycle and accessibility; avoid cross-platform UI overhead. New source only. | A concrete platform requirement demands another approach |
| 002 | App target plus local Swift package, modules added incrementally | Enforce useful boundaries without empty-module proliferation. Domain starts independently testable. | A boundary gains its first production consumer |
| 003 | Swift 6, explicit MainActor UI and actor-owned mutable services | Catch data races at compile time; introduces careful value conversion and cancellation work. Do not rely on implicit default isolation. | Compiler/framework constraints require a documented narrow exception |
| 004 | Voice produces transcripts; coordinator owns execution | Recognition errors never directly trigger privileged effects. Adds interpretation and confirmation boundary. | Never bypass for convenience |
| 005 | Independent model and coding-runtime ports | Swappable inference artifacts and runtimes; common capabilities are explicit, unsupported features fail. Avoid one universal protocol exposing every vendor option. | First two real integrations reveal justified common behavior |
| 006 | Brokered, scoped permissions and single active execution | Reduces accidental effects and simplifies resource/cancellation control. macOS consent is separate from per-task authority. | Measured requirements justify parallelism |
| 007 | SwiftData repository plus bounded artifact files | Native persistence without third-party dependencies; durable task/event writes and migrations still require tests. UI never uses persistence models directly. | Proven performance, recovery or schema constraints justify replacement |
| 008 | Direct distribution; initially no App Sandbox | Broad developer tools and cross-app automation may conflict with sandbox restrictions. Hardened Runtime and signing are later release gates. App-level controls are not OS containment. Mac App Store distribution is deferred. | Distribution requirements change, or agent containment needs a helper/sandbox |
| 009 | Native speech feasibility before engine selection | Offline support must be proven for selected language/device; forbid silent cloud fallback. Bundled engine dependency is deferred until justified by measurements. | On-device API capability/quality testing completes |
| 010 | No local inference library chosen in Phase 0 | Avoid speculative dependencies, model-memory promises and premature runtime coupling. Evaluate licensing, format, resource use and cancellation first. | Phase 3 provider spike yields evidence |
| 011 | Intent/outcome events with interrupted recovery | External effects cannot be transactionally committed with history. Never automatically replay unknown outcomes. | Recovery requirements demand stronger isolation |
| 012 | Approval gates before implementation and later phases | Phase 0 currently produces reviewable design; shell follows approval. No feature claims without executed verification. | User explicitly authorizes the next gate |

Alternatives considered: monolithic application (weak dependency boundaries); one target per conceptual subsystem immediately (unused structure); cloud-first recognition/inference (violates local-first baseline); embedded autonomous agent with unrestricted shell access (cannot enforce scoped operations); raw SQLite (more mapping and lifecycle work initially); SwiftData in views (couples UI to storage); App Sandbox from day one (needs a concrete tool/automation feasibility study). None is adopted implicitly.
