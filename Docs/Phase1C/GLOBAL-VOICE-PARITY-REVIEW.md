# Global voice parity review — 20 October 2026

Decision: PARTIAL. Source changes and automated verification pass. Reliable repeated ChatGPT/Codex insertion and the new physical-app acceptance matrix remain unresolved. The verified build has not replaced the running app, which holds a pending clipboard backup. This report is not a claim of universal dictation reliability or a completed live acceptance gate.

## Current-state reconciliation

See CURRENT_STATE.md for the pre-edit inventory and final classification. Inspected actual AGENTS, main/HEAD/status, Phase1C reports, composition/window/sidebar/settings/history, modifier monitoring, speech/audio/callbacks, insertion/clipboard, persistence, tests and package/project configuration. HEAD remains 0a3e91c731a716945853a6b84bcfaaf6d9e672d3. The claimed newer sessions had not produced a newer local commit/report than the observed repeated-insertion work. 41 files were already outstanding at entry; snapshots/hashes preserve that baseline. No unrelated work was reset, deleted or staged.

The native UI was inspected before edits: actual History/sidebar, then Dictation's UNCERTAIN/DENIED outcomes and pending-clipboard review state. This is a different binary from the newer source. Prior 802-case evidence described the earlier diagnostic source, not a deployed ChatGPT fix. No actual editor contents or clipboard representations were dumped into evidence.

## Clean-room behavioral comparison

Only [DailyOps README](https://github.com/akshaywesleykothapalli/dailyops/blob/main/README.md) and [PROJECT_CURRENT_STATE](https://github.com/akshaywesleykothapalli/dailyops/blob/main/PROJECT_CURRENT_STATE.md) were opened, on 20 October 2026 from mutable main. They describe configurable hold-to-talk, a nonactivating HUD, local speech, deterministic cleanup/spelling/vocabulary, cursor insertion and history. These are product descriptions, not independently executed evidence of DailyOps reliability. No Swift implementation, assets, tests, dependencies or clone was read/copied/imported. Wesley Flow keeps its own modules, speech adapter and verification policy.

| Behavior | Wesley Flow outcome |
| --- | --- |
| Global hold-to-talk | Existing Fn preserved; Right Option/Right Command added through public modifier APIs;250ms production hold threshold. |
| HUD and activation |84x32 nonactivating panel preserved. Optional idle-clickable mode added, off by default; capture precedes audio startup and panel never becomes key/main. |
| Local speech/fallback | Existing installed Apple modules/legacy on-device path retained; no new provider/download/cloud path. |
| Local formatting | Literal punctuation, sentence starts, conservative hesitation/repetition cleanup, optional Apple spelling, vocabulary protection and exact expansions added. No semantic rewriting. |
| Original cursor/clipboard | Existing field/PID/window/selection/secure checks and bounded clipboard representation/ownership policy preserved. No blind fallback. |
| History | Existing raw/cleaned/local outcome history retained. Vocabulary is formatting protection, not ASR training. |
| Broad editor reliability | Still partial; source tests never substitute for physical-app acceptance. |

## Gaps and independently implemented changes

- Short taps previously started audio immediately. Composition now passes250ms minimum hold into the existing coordinator. The original destination is captured at press; preparing feedback is immediate. Releasing during the threshold cancels before microphone startup; duplicate presses do not create sessions. Tests use controlled clocks, not delays. Generic fixture construction keeps zero-delay injection for existing deterministic tests; production composition explicitly selects250ms.
- The monitor previously decoded Fn only. Sendable physical-key selection now supports Fn63, Right Option61 and Right Command54. Right-side release uses selected-key state, even if aggregate modifier flags remain set from the other side. Chords/Escape cancel. Key changes cancel/fence the old generation. Listen-only monitoring never consumes another app's shortcuts. Fn can conflict with emoji/macOS Dictation; right-side modifiers can conflict with app bindings/layouts. No system shortcuts are automatically changed.
- Invalidated Mach ports are checked before re-enabling after wake/disabled-tap events. Unavailable monitoring cancels/disables and is recreated by explicit enable; healthy taps re-enable after wake. Permission refresh is also requested every2s while the main view is mounted, plus activation. Hidden/closed-view polling and physical sleep/wake remain limitations, not an always-running recovery guarantee.
- Existing pill mouseDown was inert. Optional idle display now permits explicit click/start/click/stop without activation. Default remains hold-to-talk with hidden idle pill. Closing the main window keeps an explicitly enabled idle pill alive. The waveform remains a decorative recording indicator, not a measured audio-level display.
- Formatting was whitespace-only and Dictionary was a placeholder. New Domain options/pure pipeline isolate protected ranges before transformations: backtick code, quoted paths, recognized command lines, syntax-bearing tokens, mixed-case identifiers, abbreviations, filenames, numbers and custom vocabulary. Explicit phrase expansions are protected output and are not recursively expanded/spellchecked. Output remains bounded16KiB;128 vocabulary entries/64 replacements, bounded phrase/value sizes, and at most128 spelling candidates. Oversized/invalid formatting falls back to raw rather than truncated output.
- Spelling is opt-in through NSSpellChecker, selected from available languages, with a per-document tag closed via defer. The application creates no network/provider/model client for spelling. Actual installed dictionary suggestions vary; fixtures inject corrections. Plain lowercase identifiers without recognizable syntax cannot be inferred reliably: add them to protected vocabulary or leave spelling/capitalization off. Spelling service latency is not a hard real-time guarantee.
- Punctuation is a small English literal lexicon (comma/period/full stop/colon/semicolon/question/exclamation/new line/new paragraph). No general language understanding or punctuation inference is claimed. Only hesitation interjections um/uh/erm are removed/collapsed when enabled. Conjunctions and repeated ordinary words are deliberately retained. Optional transformations start off; previous whitespace preference is preserved. Raw transcript recovery is unchanged.
- Preferences decode older v1 payloads with safe defaults and preserve unreadable future data. Existing settings persist independently; no transcript-store migration was required.
- Normal Quit now refuses an in-flight session or pending clipboard backup instead of silently losing the RAM backup. Neither this guard nor ownership tokens provide crash/force-quit survival. No clipboard backup was exported, inspected, discarded or automatically restored by this work.

The prior confirmed clipboard-pending blocker remains visible. Another unverified native paste must not be relabelled INSERTED, automatically retried, or repaired by clearing the guard. No reproducible evidence yet establishes why this ChatGPT field fails observation. Existing native ChatGPT initial-paste policy and safe diagnostic source are preserved; no speculative native dispatch change is labelled a fix.

## Stable/incremental insertion

External insertion still happens only after finalization. A deterministic test feeds revised volatile snapshots, confirms zero writes during them, then verifies one final insertion and retained raw text. The current DictationEvent.transcript carries a snapshot, not stable segment identity/range/finality. Consequently safe incremental insertion cannot be established through this contract. It remains disabled. A live HUD is not live external insertion; no deletion of independently typed text is introduced.

## Architecture, security and preserved work

New files: Domain/DictationFormatting.swift and SystemOperations/NativeDictationFormatting.swift. Existing Domain shortcut data/protocol adds a defaulted configuration method; native modifier decoding stays SystemOperations, settings/lifecycle stays App. Package.swift and dependency graph match entry baseline: no new targets, package dependencies or downloads. Speech/audio/transport/task/approval sources, history schema, existing provider admission and20 tracked pre-existing test files are unchanged. Existing untracked tests are retained with additive cases/assertions.

Terminal remains manual-copy only. Foreground AXManualAccessibility/AXEnhancedUserInterface activation stays disabled per explicit refusal. No real inference/OpenCode, agent execution, prompt submission, arbitrary shell executor or future coding phase is enabled. All insertions still require original process+launch, window/element identity, secure-input rejection, session fencing, selection/text checks and exact expected observation. Never switch to a new foreground target at release. Only Cmd+V/plain Unicode construction exists; no Return is sent. Dispatched events are UNCERTAIN until exact text observation succeeds.

Public platform references: [Apple NSSpellChecker](https://developer.apple.com/documentation/appkit/nsspellchecker), [modifier change events](https://developer.apple.com/documentation/coregraphics/cgeventtype/flagschanged), and [physical key state](https://developer.apple.com/documentation/coregraphics/cgeventsource/keystate(_:key:)). These establish API contracts, not real editor delivery or dictionary acceptance.

## Verification evidence

- focused: 200 expanded cases / 139 functions, failed0, skipped0, exit0.
- full: 824 expanded cases / 366 functions, failed0, skipped0, exit0.
- replay: 824 expanded cases / 366 functions, failed0, skipped0, exit0.
- Debug and Release builds, optimized Release test compilation: exit0.
- Swift6 mode/concurrency checking passed through both configurations; no Swift compiler warnings/errors in final logs. Existing metadata-skip and test-host linkd messages retained.
- All six source SHA256 maps match the reviewed source; package graph unchanged; git diff --check passed; staging empty.
- Actual toolchain: Xcode27.0 build27A5237l, Apple Swift6.4, SDK27.0, arm64 deployment26. Actual macOS26/Swift6.2.3 runtime compatibility is UNVERIFIED.
- Initial old-cache focused build exited65 with missing newly exported Domain symbols; fresh DerivedData resolved that cache issue. Fresh attempt2 exited65 for static-vs-instance availableLanguages usage; corrected to checker.availableLanguages. Attempt3 passed; subsequent final source changed only to complete key-generation/idle lifecycle regressions and was fully reverified. All failed logs remain. No test was deleted or weakened to pass.

Final argv, developer directory, timestamps, exit codes and source SHA256 maps: Evidence/GlobalVoiceParity/final-*.json/log/xcresult. Baseline, narrow diff, count extraction and final-review status are in the same ignored folder. Unit-hosted light/dark page bitmaps were generated by existing rendering tests and inspected for the new controls; these are fixture layouts, not proof of a deployed native app or external insertion.

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/GlobalVoiceParity -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/GlobalVoiceParity/final-focused.xcresult test -only-testing:WesleyFlowAppTests
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/GlobalVoiceParity -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/GlobalVoiceParity/final-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/GlobalVoiceParity -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/GlobalVoiceParity/final-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/GlobalVoiceParity -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/GlobalVoiceParity/final-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/GlobalVoiceParity -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/GlobalVoiceParity/final-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/GlobalVoiceParity-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/GlobalVoiceParity/final-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```

All commands set DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer and remove SDKROOT. No changing source during accepted verification.

Coverage includes native event construction without posting, focused-element/session identity, secure rejection, clipboard representations/external replacements/ownership/restoration/cancellation, duplicate prevention, raw/final history status, old callback fencing, permission loss, short/held keys, literal formatting, Unicode/ranges and protected technical spans. Native event-tap invalidation, real hardware audio, app accessibility implementations and NSSpellChecker dictionaries remain separate live gates.

## Cross-application acceptance matrix

| Target | Current live status | Evidence / next check |
| --- | --- | --- |
| TextEdit | UNVERIFIED | No current physical final-dictation acceptance. |
| Apple Notes | UNVERIFIED | No physical test performed. |
| Safari / Chrome | UNVERIFIED | Prior Brave/browser human success does not establish these named apps or the new binary. |
| ChatGPT Mac prompt | BROKEN / intermittent | Human first-delivery reports; running own History shows UNCERTAIN then DENIED repeats. No agent automation of ChatGPT/Codex UI. |
| Codex Desktop prompt | UNVERIFIED | Direct automation prohibited by tools; do not bypass through AX scripts/other mechanisms. Human-only test needed. |
| VS Code editor | UNVERIFIED | No physical test performed; integrated terminal is not an ordinary verified editor. |
| WhatsApp | Historical human success; new build UNVERIFIED | Previous source accepted by user, not retested on the new source. |
| System Settings/native controls | Historical human success; new build UNVERIFIED | Prior INSERTED receipts and human feedback. |
| Apple Terminal | Manual-copy only | Explicit user decision retained; no automatic typing test. |

No real cross-app Fn/audio/insertion test was performed by automation. The existing actual UI was inspected, but new source has not been deployed because the open canonical process still owns a RAM clipboard backup. User was asked to complete native clipboard review before an update; no response confirming restoration was received at report time. Do not force-quit or silently discard it. Verified build: DerivedData/GlobalVoiceParity/Build/Products/Debug/Wesley Flow.app. Canonical Run app unchanged and preserved. No new permission grant was automated. Fresh ad-hoc installation will require native consent review; no TCC/security modifications are authorized.

## Working tree and remaining gates

Files modified relative to this milestone's baseline:

- App/ClickableDictationPill.swift
- App/WesleyFlowApp.swift
- App/AppComposition.swift
- App/GlobalDictationView.swift
- App/SystemWideDictationCoordinator.swift
- App/DictationPreferences.swift
- AppTests/GlobalDictationTests.swift
- Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift
- Packages/WesleyFlowCore/Sources/Domain/DictationShortcut.swift
- AGENTS.md

Plus the two new formatting files, CURRENT_STATE.md and this report. The complete working tree includes pre-existing work; nothing staged or committed. Exact status is in final-review.json and appended below after report creation.

Remaining gates: safe clipboard recovery before deployment; native consent/hold key/pill acceptance; real on-device speech/final insertion in the named matrix; repeated ChatGPT insertion diagnosis; physical sleep/wake/invalid-tap/permission transitions; optional spelling dictionary behavior and formatting-user acceptance. Absolute “works everywhere” and crash-safe clipboard recovery are not established. Do not begin coding-agent execution or claim this milestone's live reliability gate complete.

```text
 M .gitignore
 M AGENTS.md
 M App/AppComposition.swift
 M App/FoundationView.swift
 M App/WesleyFlowApp.swift
 M Docs/Phase1B/MODEL-PROVIDER.md
 M Docs/Phase1B/SECURITY-BOUNDARIES.md
 M Packages/WesleyFlowCore/Package.swift
 M Packages/WesleyFlowCore/Tools/OllamaEvaluation/EvaluationMain.swift
 M WesleyFlow.xcodeproj/project.pbxproj
?? App/ClickableDictationPill.swift
?? App/DictationModel.swift
?? App/DictationPreferences.swift
?? App/GlobalDictationView.swift
?? App/SystemWideDictationCoordinator.swift
?? AppTests/DictationTests.swift
?? AppTests/GlobalDictationTests.swift
?? Docs/Phase1C/ACCESSIBILITY-ACTIVATION-PROPOSAL.md
?? Docs/Phase1C/CURRENT_STATE.md
?? Docs/Phase1C/GLOBAL-VOICE-PARITY-REVIEW.md
?? Docs/Phase1C/PHASE1C1-COMPLETION.md
?? Docs/Phase1C/PHASE1C2-CHATGPT-PASTE.md
?? Docs/Phase1C/PHASE1C2-CLIPBOARD-REPAIR.md
?? Docs/Phase1C/PHASE1C2-COMMANDS-AND-COMPATIBILITY.md
?? Docs/Phase1C/PHASE1C2-EDITOR-CAPABILITY.md
?? Docs/Phase1C/PHASE1C2-FN-REFINEMENT.md
?? Docs/Phase1C/PHASE1C2-GLOBAL-DICTATION.md
?? Docs/Phase1C/PHASE1C2-REPEATED-INSERTION.md
?? Docs/Phase1C/PHASE1C2-WHATSAPP-TEXT-COMPATIBILITY.md
?? Docs/Phase1C/TERMINAL-DRAFT-TYPING-PROPOSAL.md
?? Packages/WesleyFlowCore/Sources/Domain/AppOpeningCommand.swift
?? Packages/WesleyFlowCore/Sources/Domain/Dictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/LocalPromptRewriter.swift
?? Packages/WesleyFlowCore/Sources/Persistence/SwiftDataDictationHistoryStore.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeAppOpening.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AppleDictationInput.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AppleSpeechConfiguration.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/NativeSpeechCallbacks.swift
```

## 21 October 2026 remediation handoff update

[Repeated insertion remediation](REPEATED-INSERTION-REMEDIATION.md) records safe obsolete-backup recovery, the confirmed stale-lease correction,841-case verification/replay and installation of the exact verified build. Earlier uninstalled statements above are historical. Real repeated ChatGPT acceptance is still UNVERIFIED; no earlier result is relabelled.
