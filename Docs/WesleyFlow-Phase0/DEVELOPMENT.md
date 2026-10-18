# Directory structure and development standards

## Proposed repository after separate Phase 0B authorization

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
      Sources/Domain/        # pure task values and transitions first
      Tests/DomainTests/
  AppTests/                  # app composition test
  Docs/                      # approved packet and subsequent ADRs
```

This is a directory plan, not a created repository. Only populate directories with authorized behavior. Add Presentation, TaskExecution and adapter targets as they gain real consumers/tests, using the [dependency allowlist](architecture/ARCHITECTURE.md#dependency-allowlist). AppKit integration may remain in App until a real boundary exists. This packet's AGENTS.md is scoped here until copied into a separately authorized new repository; it cannot authorize that copy or implementation itself.

## Toolchain and dependency standards

Follow [ENVIRONMENT compatibility contract](ENVIRONMENT.md#compatibility-contract): minimum package tools 6.2, explicit Swift 6 language mode, source features compatible with compiler 6.2.3, arm64, deployment 26.0 in both app and package. All targets use strict concurrency; shared/core targets default nonisolated, UI explicitly MainActor, mutable services actor-owned. Record effective default-isolation/upcoming-feature settings per target; no extra upcoming-feature flags initially. An ADR is required for a feature requiring a newer floor. Swift 6 mode is not proof of compiler-version compatibility.

Keep coherent Xcode/compiler/SDK pairs and separate caches/results per lane. No UI/process/persistence/model framework imports in Domain. Compare target edges and source imports with the allowlist as modules arrive; reject undocumented edges/cycles. Domain owns only narrow consumer-driven ports; vendor configuration belongs to adapters. CodingAgents gets proposal interfaces, never an executor or grant issuer.

No third-party dependency without concrete need, ADR, license, pin, footprint and cancellation assessment. No model weights, machine paths, secrets, build products or user state in version control. No code-generation dependency for project creation by default.

## Engineering standards

- Compose external dependencies in App. Use Sendable values at isolated boundaries; do not export framework-owned model objects.
- Propagate cancellation, recheck generation/state after awaits, bound retries/streams/timeouts and resource ownership. No detached-task escape, mutable singleton, blanket concurrency suppression or unchecked Sendable to avoid a real isolation issue.
- Typed operation requests and executable-plus-argv arrays only; no interpolation of user/model text into shell commands. Effects are broker-mediated; runtime/voice adapters cannot grant authority.
- Respect SECURITY's explicit human approval and disabled general-purpose execution gate. Website, project and tool text are data.
- Pure state graph/table stays synchronized; every state/event pair and guard is tested under G0. Coordinator, repository and process tests arrive in their authorized phases.
- Logging defaults private/redacted. Store only sanitized execution evidence by default; source-containing patches/logs need scoped opt-in. Show typed errors, partial effects and limitations.
- Keep changes small and state behavior and verification actually run. Label doubles; generated code and planned checks are not execution evidence.
- Accessibility labels, keyboard navigation, system text sizing where applicable, and clear empty/denied/error states belong to each UI feature.
- No legacy app implementation references, speculative empty targets, fake history, nonfunctional controls or unrelated destructive cleanup.

## Phase 0B shell contract

Only after separate explicit user approval: one launchable native window identifying Wesley Flow and honest foundation status, composition, local Domain package with lifecycle values/transitions, exhaustive state/event and guard tests, terminal immutability, and a composition test constructing shell state. No coordinator, durable history, inference, speech, runtime, effect broker implementation or workflow engine in 0B. No feature claims from mocks. G0 requires actual Debug/Release builds, executed tests/result bundles and actual launch; unavailable launch means incomplete 0B. Compatibility lanes are tracked separately under GC; no minimum-OS claim without runtime evidence.
