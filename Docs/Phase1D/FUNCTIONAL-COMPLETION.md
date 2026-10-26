# Phase 1D — Functional completion review

2026-10-26 · main · HEAD `0a3e91c731a716945853a6b84bcfaaf6d9e672d3`

**Outcome: PARTIAL.** Preview implementation and deterministic regressions pass. Native Option shortcut registration passes. Actual tone quality and Prompt Engineering model output are **BLOCKED by unchanged memory admission**. Physical shortcut delivery is **NOT VERIFIED**, explicitly requested by the user. This is not a claim of fully verified functional completion.

## Inspection and precise original blockers

Read AGENTS.md, Phase1D rewrite/evaluation/settings reports, actual Domain protection contracts, Apple provider, global dictation/hotkey coordinator, preference storage, UI and existing tests. Confirmed the original 964-case baseline before edits. Existing uncommitted application/lab/voice/clipboard/UI work was preserved.

Originally: tones shared one narrow lexical gate and lacked live distinct-output evidence; Prompt Engineering had no validated transformation; Option-number controls were inert because the voice monitor only handled held modifiers. Replacing that monitor or weakening preservation was unnecessary.

## Implementation

- Added a preview-kind discriminator to the existing provider request, defaulting to polish for compatibility. One actor-owned provider, unchanged 8-second deadline, 250ms resource watcher, single settling slot and cancellation semantics.
- Five distinct tone instructions are forwarded to the actual Apple generator. The original ProtectedRewriteText implementation is byte-for-byte unchanged. Names, numbers, identifiers, paths, URLs and configured vocabulary remain protected. English prose only; unsupported input/language retains the original.
- Prompt Engineering is **conservative extractive organization**, not unrestricted paraphrasing. A fresh Apple session classifies masked, numbered source lines into Objective, Context, Requirements, Constraints and Expected output. An exact five-key JSON plan is checked for duplicate/escaped keys, integer indices, limits, every line exactly once and original increasing order. Only nonempty headings are rendered with original source lines verbatim. Maximum 16 nonblank lines, 2,048 input bytes and 4,096 output bytes. Code fences and recognizable shell-style inputs are rejected. Source-line content is never model-generated. Missing requirements/context cannot be supplied. One-line input can produce only Objective. Category relevance still requires human review; structural validation is not proof of semantic quality.
- Supplied text and an explicitly selected eligible saved dictation are supported. No external app text/selection or clipboard is read to obtain input. Draft and preview text are session-only, not persisted or added to history. Eligibility excludes speech failure/cancellation/deadline records; completed transcripts with unsuccessful insertion remain eligible. Deletion, source selection/input changes, disabling the active feature, dictation, cancellation and close invalidate stale previews. Existing reliable latest-dictation preview remains available.
- Prompt opt-in and shortcut opt-in persist with backwards-compatible defaults OFF. Existing settings/defaults are unchanged. Output stays in preview; the existing explicit lease-aware copy action is reused. No insertion, task submission or generated-code effects.
- Added exclusive native Carbon Option+1 / Option+2 registration inside SystemOperations, conforming to a Domain port. Only opted-in features register. The existing dictation monitor is preserved. Registration checks enabled system shortcuts and current numeric keyboard mapping; right-Option hold-to-talk conflicts fail closed. Bounded event queue fails closed on overflow. Key-down/release state suppresses repeats and unmatched releases, invalidates on focus switch/Secure Input/extra modifiers. No global text monitor, focus activation, synthetic keys, Return, clipboard access or accessibility-tree activation.
- Registration and preview status/cancellation are exposed in existing settings/menu surfaces. No page, sidebar, typography, speech or pill redesign.

## Tone contracts and live status

| Tone | Explicit contract within the unchanged fidelity gate | Actual new model output |
|---|---|---|
| Natural | Conversational rhythm, ordinary sentence punctuation, isolated hesitation removal | BLOCKED before generation |
| Professional | Restrained complete-sentence punctuation/capitalization, no added greetings/emphasis | NOT RUN after admission rejection |
| Concise | Remove hesitation fillers, minimal punctuation, preserve all content words | NOT RUN after admission rejection |
| Friendly | Gentle punctuation, retain conversational wording, no added sentiment | NOT RUN after admission rejection |
| Direct | Clear statement boundaries, no exclamation or changed politeness | NOT RUN after admission rejection |

These instructions are distinct; actual tonal differentiation is **not verified**. The existing lexical contract intentionally rejects broad rewording. A picker or prompt difference is not evidence of model quality.

## Actual bounded native inference attempt

The diagnostic links the current production Domain/ModelProviders/SystemOperations frameworks, forwards kind and tone to AppleRewriteGenerator, uses fresh SystemLanguageModel.default sessions with no tools, and runs under the existing client network-denial profile. No cached MLX load, download, cloud selection or training.

Natural synthetic input:

> um please review saveButton in /tmp/Example.swift and keep 12 items

Status: `resourceBlocked`, reason `host-reserve-or-observation`. Actual masked model output: **null**. Original text was retained exactly. Native readiness passed before host admission. No inference session was created. Total call latency: 0.021420 seconds; model generation latency unavailable.

| Observation | Before | After |
|---|---:|---:|
| Conservative available bytes | 4253335552 | 4252942336 |
| Approximate GiB | 3.9612 | 3.9609 |
| Memory pressure normal | true | true |
| Swap bytes | 1216413696 | 1216413696 |

Required available floor remains 4,294,967,296 bytes (4 GiB), normal pressure, no increase from per-request initial swap. No estimate from MLX was reused. Stopped immediately, with no repeated measurement/load attempts. Professional, Concise, Friendly, Direct and Prompt Engineering were not attempted. Planned synthetic prompt input was five explicit lines (button-animation objective, Wesley Flow context, protected identifier/path, no-download constraint, explanation output); **no real transformed output exists**. The deterministic prompt fixture results are not live model evidence.

Cleanup: diagnostic exit 0, worker reaped; no generation to cancel. Raw command/output/source: `Evidence/Phase1D/FunctionalLive/` (`live-compile.json`, `live.json`, `live.stdout.jsonl`, `live-source.swift`). The sandbox denies this client’s network; it is not proof of containment of Apple's system-managed services.

## Shortcut registration and interaction

Actual independent native probe: numeric layout supported, Secure Input false, no enabled system-chord conflict; both registrations succeeded. A second exclusive owner was rejected with OSStatus -9878. Repeated disable and re-registration succeeded. Probe exit 0; no key events synthesized. Evidence: `Evidence/Phase1D/FunctionalHotkeys/{compile.json,probe.json,source.swift}`.

System enumeration does not include every application-specific menu shortcut. Opt-in reserves these chords globally and can override app shortcuts. Unsupported layouts and registration failures remain explicit; no silent inert success. Physical key delivery, focus behavior while physically pressing, Secure Input interaction in another app and real cross-app repeat behavior: **NOT VERIFIED**. The user explicitly selected “Leave physical shortcut delivery unverified.” Pure focus/repeat/Secure Input logic and coordinator cancellation are covered by deterministic tests, not represented as physical evidence.

Actual app opened from `DerivedData/Phase1DFunctional/Build/Products/Debug/Wesley Flow.app`. Smart Formatting was inspected through native accessibility and screenshot views: five-tone picker, supplied/saved source control, explicit input, prompt opt-in, disabled empty-input actions and review-only notice were present. Both feature opt-ins observed OFF; no generation invoked from UI. The previous active Xcode-built app exited by ordinary guarded Quit; no force termination. Canonical Run bundle was not replaced. No clipboard copy/paste, dictation, system permission changes or history modifications were performed in this manual inspection.

## Automated verification

Full toolchain: `/Applications/Xcode-beta.app/Contents/Developer`; Xcode27 beta5 / Swift6.4, SDK27, macOS26 arm64 deployment. Host macOS27.2 Apple Silicon / 16GiB. CLI developer selection unchanged. Swift6 builds and explicit complete-concurrency build are separate from runtime race proofs.

| Run | Expanded cases | Declarations | Failed | Exit |
|---|---:|---:|---:|---:|
| functional-baseline | 964 | 448 | 0 | 0 |
| functional-focused-final | 642 | 350 | 0 | 0 |
| functional-verified-full | 990 | 460 | 0 | 0 |
| functional-replay | 990 | 460 | 0 | 0 |

Original tests are exact unchanged prefixes; 26 expanded cases / 12 declarations added. No tests deleted/weakened. Tests cover strict plans, escaped/duplicate keys, invented output, absent/reordered/duplicated/out-of-range indices, shell/code/oversized input, exact content preservation, empty input, kind dispatch, invalid-output fallback, memory rejection without model call, opt-in migration/persistence, explicit-only input, no capture/copy/insertion/history effects, selected completed history and deletion, late cancellation/source replacement, repeated previews, registration conflict, Secure Input, matching release, repeat suppression and focus invalidation. Existing provider timeout/noncooperative cancellation and clipboard/network regressions remain passing.

Commands are recorded verbatim with times/exit codes in `Evidence/Phase1D/functional-*.json`; all final result bundles/logs retained. Common build/test prefix:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild \
  -project WesleyFlow.xcodeproj -scheme WesleyFlow \
  -destination platform=macOS,arch=arm64 \
  -derivedDataPath DerivedData/Phase1DFunctional \
  -disableAutomaticPackageResolution -skipPackageUpdates
```

Focused adds `-configuration Debug -resultBundlePath <bundle> test -only-testing:WorkspaceTests -only-testing:WesleyFlowAppTests`; full/replay omit the only-testing filters. Final full/replay bundles are `functional-verified-full.xcresult` and `functional-replay.xcresult`. Debug/Release add their configuration and `build`. Explicit concurrency adds `SWIFT_STRICT_CONCURRENCY=complete` to Release build.

Build results: Debug exit 0; Release exit 0. Explicit complete-concurrency Release exit 0 (`functional-concurrency.json/log`).

Initial development failures retained: functional-wiring exit65 (Carbon parameter Int vs UInt32), functional-regressions exit65 (new fixture missing required clock), functional-final-full exit65 (new synthetic history duration nil vs Int64). Each corrected in new code/tests; final full/replay/builds pass. The older full run before the last two tests also passed. Existing Release warnings: unused withLock result in unchanged ApplicationNetworkPolicy and skipped AppIntents metadata extraction. No concurrency error was suppressed and no unsafe continuation/lock introduced.

Dependency check: package/project dependency configuration unchanged during this task; no added external package. Domain imports Foundation, ModelProviders imports Domain/Foundation/FoundationModels, new native shortcut implementation imports Domain/AppKit/Carbon. Clipboard/insertion/speech/pill/task orchestration and app-owned network policy sources match task-start hashes. ProtectedRewriteText unchanged; memory/lifecycle safety thresholds unchanged. Audit evidence: `functional-boundaries.json` contains exact source hashes and preservation/staging checks. `git diff --check` exit 0; staging empty.

## Files changed this task

- `App/WesleyFlowApp.swift`
- `App/AppComposition.swift`
- `App/GlobalDictationView.swift`
- `App/SystemWideDictationCoordinator.swift`
- `App/DictationPreferences.swift`
- `AppTests/GlobalDictationTests.swift`
- `Packages/WesleyFlowCore/Sources/SystemOperations/NativePreviewShortcuts.swift`
- `Packages/WesleyFlowCore/Sources/ModelProviders/AppleTranscriptRewriter.swift`
- `Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift`
- `Packages/WesleyFlowCore/Sources/Domain/PromptEngineering.swift`
- `Packages/WesleyFlowCore/Tests/WorkspaceTests/ProviderTests.swift`

New report: `Docs/Phase1D/FUNCTIONAL-COMPLETION.md`. Synthetic diagnostic sources/commands/results are in ignored Evidence, not staged. Extensive earlier uncommitted work remains intact.

## Remaining blockers and next action

- Live tone comparison and real Prompt Engineering output: BLOCKED by resource admission; not quality-verified. A separately scheduled test can run after safely freeing enough memory to satisfy the unchanged native guard immediately before generation. No app is automatically terminated and no reserves are reduced.
- Broad stylistic paraphrasing remains intentionally outside the current lexical preservation gate. This milestone supplies tone contracts and safe previews, not a claim of unrestricted tone rewriting.
- Physical Option shortcut behavior remains unverified at user request. Registration success does not prove delivery across applications or every keyboard layout.
- Native FoundationModels cancellation is cooperative; the existing provider retains its single slot until the framework settles. No unlimited replacement sessions.
- No live preview was copied/inserted; no automatic AI insertion is enabled. Existing deterministic voice/insertion acceptance is not re-claimed from these fixture tests.

## Final Git status

No commit, staging, push, remote or source deletion. Branch main and HEAD unchanged. Current short status (includes all preserved prior work):

```text
 M .gitignore
 M AGENTS.md
 M App/AppComposition.swift
 M App/FoundationView.swift
 M App/WesleyFlowApp.swift
 M Docs/Phase1B/MODEL-PROVIDER.md
 M Docs/Phase1B/SECURITY-BOUNDARIES.md
 M Packages/WesleyFlowCore/Package.swift
 M Packages/WesleyFlowCore/Sources/ModelProviders/OllamaTransport.swift
 M Packages/WesleyFlowCore/Tests/WorkspaceTests/ProviderTests.swift
 M Packages/WesleyFlowCore/Tools/OllamaEvaluation/EvaluationMain.swift
 M WesleyFlow.xcodeproj/project.pbxproj
?? App/ClickableDictationPill.swift
?? App/DictationModel.swift
?? App/DictationPreferences.swift
?? App/GlobalDictationView.swift
?? App/SystemWideDictationCoordinator.swift
?? AppTests/DictationTests.swift
?? AppTests/GlobalDictationTests.swift
?? Docs/ModelLab/
?? Docs/Phase1C/
?? Docs/Phase1D/
?? ModelLab/
?? Packages/WesleyFlowCore/Sources/Domain/AppOpeningCommand.swift
?? Packages/WesleyFlowCore/Sources/Domain/ApplicationNetworkPolicy.swift
?? Packages/WesleyFlowCore/Sources/Domain/Dictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift
?? Packages/WesleyFlowCore/Sources/Domain/PromptEngineering.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/AppleTranscriptRewriter.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/LocalPromptRewriter.swift
?? Packages/WesleyFlowCore/Sources/Persistence/SwiftDataDictationHistoryStore.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeAppOpening.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativePreviewShortcuts.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/
```
