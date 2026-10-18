# Wesley Flow — Phase 0 architecture review

Status: proposed; awaiting architectural approval. Prepared 18 October 2026.

This is an independent greenfield design. No previous Wesley Flow, LocalFlow, or DailyOps application source was inspected, copied, imported, or migrated. This packet contains documentation only. No application project, repository, runtime, tests, or model integration has been created.

## Review packet

- [Architecture and dependency diagram](architecture/ARCHITECTURE.md)
- [Architecture decisions](decisions/ADRs.md)
- [Development environment evidence](ENVIRONMENT.md)
- [Directory structure and standards](DEVELOPMENT.md)
- [Testing strategy](TESTING.md)
- [Security and permissions](SECURITY.md)
- [Implementation sequence and acceptance gates](PLAN.md)
- [Project instructions](AGENTS.md)

## Approval requested

Approve or amend the module boundaries, task lifecycle, direct-distribution permission model, persistence choice, and staged delivery plan. Approval authorizes only the remaining Phase 0 foundation: independent Git repository, Xcode project, minimal native shell, foundational tests, and build/test verification. Later phases require separate direction.

The foundation will establish application lifecycle, dependency composition, a small task-state domain, and its tests. It will not claim dictation, automation, inference, coding, or verification workflows are operational.

## Current result and limitations

Environment discovery completed. Xcode beta is available through an explicit developer-directory override; the global selection points to Command Line Tools. No application builds or tests have been run. Host-reported macOS and toolchain versions are unusual relative to the requested baseline and are recorded verbatim. macOS 26 compatibility needs an actual macOS 26 test machine; this host cannot prove it. Memory capacity could not be read under the current restrictions. Permission behavior, local model suitability, process containment, signing, and distribution remain unverified.
