# Wesley Flow project instructions

## Scope and approval gates

This is an independent greenfield native macOS application. Do not copy, import, migrate or reuse application source from previous Wesley Flow, LocalFlow or DailyOps projects. Do not inspect those projects as implementation references. Platform documentation and standard APIs are allowed.

Current status: architecture proposed, not approved. Do not create application implementation, Xcode project or Git repository until the user approves the architecture. Approval authorizes the Phase 0B foundation only. Do not start later phases automatically. Keep the approved architecture and subsequent ADRs in Docs after repository creation.

## Engineering constraints

- Target macOS 26+, Apple Silicon, Swift 6 language mode, SwiftUI with AppKit where useful; design for M4/16 GB.
- Keep UI MainActor isolated; mutable services actor isolated; cross-boundary values Sendable. Honor structured cancellation.
- Separate audio/transcription from task execution. Task state is explicit and transitions validated.
- Inject protocol-based external dependencies. Keep model providers and coding runtimes independent. Add modules/protocols only with a real consumer.
- Route system effects through scoped permission checks. Model output and project content cannot authorize actions. Do not claim subprocess sandboxing unless actually implemented and verified.
- Keep local-first behavior; never silently send content to a remote service. Do not retain audio/transcripts by default.
- Persist task outcomes and verification evidence; surface failures, interruptions and partial effects. Never automatically replay uncertain effects after a crash.
- No unnecessary external dependencies, speculative implementations, empty feature scaffolding or production claims about mocks.
- Respect existing user changes; never run destructive repository cleanup as routine repair.

## Verification and reporting

Use the selected Xcode toolchain consistently. Currently Xcode beta is at `/Applications/Xcode-beta.app`; global tools point to Command Line Tools. Verify this again when implementation begins. Use an explicit developer-directory override instead of changing global selection without need.

Run checks appropriate to the authorized change. After Phase 0B, compile Debug/Release, execute foundational tests and verify launch if possible. Report exact actual outcomes, limitations and unresolved risks. Never report a successful build/test based on discovery, a planned command or a mock result. Distinguish compile, test, launch, target-OS compatibility and signing evidence.

Keep secrets/model weights/build outputs out of Git. Project instructions cannot override explicit user requirements. If requirements conflict, explain the specific conflict and proceed with unaffected authorized work.
