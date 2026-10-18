# Directory structure and development standards

## Proposed repository after approval

```text
WesleyFlow/
  AGENTS.md
  README.md
  .gitignore
  WesleyFlow.xcodeproj/       # shared app/test scheme
  App/                       # entry point, composition, native shell
  Packages/
    WesleyFlowCore/
      Package.swift
      Sources/Domain/        # task values and pure transitions first
      Tests/DomainTests/
  AppTests/                  # app composition smoke test
  Docs/                      # approved review packet and later ADRs
```

Only create populated directories. As features arrive, add Presentation, TaskExecution, VoiceInput, Persistence, SystemOperations, Workspace, ModelProviders, CodingAgents and Verification targets within the package when their dependencies and behavior warrant it. AppKit integration may remain in the app until a reusable boundary exists. The review packet lives under `outputs/` now; it is not an initialized application repository. The packet's AGENTS.md is scoped to that directory until copied to the new repository root after approval.

## Standards

- Swift language mode 6; deployment macOS 26.0; arm64 target. Explicit actor annotations, strict concurrency, no blanket concurrency suppression.
- Inject external dependencies at the composition root. Use value types and Sendable boundaries; protocols describe behavior needed by actual consumers.
- Keep pure domain logic free of SwiftUI, AppKit, SwiftData and process APIs. No UI-triggered shell calls.
- Prefer structured concurrency, propagate cancellation, bound retries and timeouts, clean up resources with clear ownership. Do not swallow errors or use forced casts/unwraps for runtime input.
- Use typed operation requests and executable-plus-argument arrays; do not construct shell strings from user/model text.
- No third-party dependency without a concrete need, license review, footprint assessment and ADR. Pin selected versions. No code generation dependency for project creation by default.
- Use platform logging with privacy annotations; never log prompt/source/audio contents by default. Persist task evidence separately from diagnostics.
- Each change states behavior, tests actually run and limitations. Keep changes small. Test doubles are identified and never described as production integrations.
- Use shared Xcode schemes; keep signing identity and machine paths out of source. Ignore build outputs, user state, local model weights and secrets.
- Accessibility labels, keyboard navigation, Dynamic Type where applicable, and clear denied/error/empty states are part of each UI feature.
- Document architectural changes with an ADR. Do not create layers, abstractions, settings, stubs or empty files for speculative features.

## Phase 0 shell contract after approval

One launchable native window identifying Wesley Flow and displaying an honest foundation status. No nonfunctional voice/agent controls. A small Domain target models permitted lifecycle transitions; unit tests cover legal and illegal transitions and terminal immutability. A composition smoke test checks that the shell's state can be constructed. Persistent history arrives in Phase 1; no fake history is presented as stored data.
