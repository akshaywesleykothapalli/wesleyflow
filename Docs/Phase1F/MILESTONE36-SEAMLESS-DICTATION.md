# Milestone 36 — Seamless dictation and in-place AI

27 October 2026. Implementation and automated verification complete; physical acceptance **UNVERIFIED**. In-place mode defaults **OFF**. No commit, push, merge, installed-app replacement, model download or live inference was performed.

## Waveform and HUD

The previous TimelineView sine-driven bars were decorative. The existing 84×32 panel, seven teal capsules, 3pt bars/spacing, 5–20pt height, material, positioning and nonactivating behavior are preserved. Recording now renders real microphone energy only, without Listening text, a microphone symbol, spinner or keyboard/typing insertion icon. Preparing, Transcribing and Finishing labels remain compact in the same pill; internal states and receipts remain distinct. Verified completion or accurate warning lasts 1.2 seconds before dismissal (existing explicitly enabled idle-pill preference still applies). Manual app-only capture does not unexpectedly display the pill. Reduce Motion disables interpolation while retaining actual amplitude feedback.

The existing AVAudioEngine tap feeds a fresh AudioLevelMailbox per capture. Float32 mono/planar or interleaved PCM is reduced to RMS across at most 8,192 frames × 8 channels. Nonfinite samples contribute zero; energy is bounded. One atomic UInt64 packs sequence + RMS; no retained audio, per-buffer allocation, lock, actor hop, queue, file I/O, FFT or second microphone is added by the meter. The UI reads only the latest scalar at 20Hz and keeps seven recent smoothed observations. Log mapping is (20log10(RMS)+60)/48, clamped to 0…1; gate 0.00056 RMS, attack 0.7 and release 0.25 per update. Silence/stale sequence decays to baseline. Fresh capture mailbox + session checks + cancellation reset prevent old levels crossing sessions. Unsupported PCM formats do not invent activity; they settle to baseline.

Performance findings are bounded-work/static inspection and synthetic real-PCM tests, not live microphone latency or CPU/GPU profiling. **The pre-existing speech AudioIngress converter still uses OSAllocatedUnfairLock and conversion buffers.** The new visualization path is lock-free; this milestone does not establish hard real-time guarantees for the entire pre-existing speech callback. Physical noise-floor suitability and amplitude appearance remain unverified.

## In-place workflow and provenance

Smart Formatting now has a separately persisted, default-OFF In-place AI rewrite switch; decoding old preferences keeps it OFF. Enable it before a new dictation, plus the desired existing AI feature and preview shortcuts. Option+1 routes to existing Smart Polish/tone; Option+2 routes to existing Prompt Engineering. With the switch OFF the prior selected/focused/manual preview workflow remains available. Failed in-place attempts do not silently open a preview or broaden capture.

Only the newest app-owned verified insertion can supply an anchor. Uncertain/failed insertion, pending clipboard recovery, wrong session/PID/text, or missing native capabilities cannot become an eligible target. The ephemeral anchor retains its own transcript, session ID, original process/launch, AX window/element, exact UTF-16 range, whole-context SHA256, activation epoch and monotonic 120-second expiry. It does not retain another full document copy or persist authority in history. Unrelated document text is read transiently (existing bounded reader, maximum 98,304 UTF-8 bytes) only for consistency hashing/verification. A new dictation retires the old anchor. A changed rewrite consumes it once; unchanged valid output performs no write. Historical dictation and metrics are not overwritten or double-counted.

Native preflight requires original app/window/element, unchanged full-context hash and exact span, expected caret, editable/nonsecure source, Accessibility authorization, no secure event input, writable selected-text/range APIs, and **an explicitly readable zero-length AXMarkedTextRange**. Unknown IME state is rejected, not assumed safe. Terminal remains manual-copy only. The existing Codex direct-replacement exclusion is preserved, so Codex in-place rewriting is unsupported in this milestone. ChatGPT/TextEdit/VS Code support is capability-dependent and physically unverified; application names never establish capability.

The broker sets only the exact selection range, revalidates, performs one AXSelectedText write, then verifies the complete expected result. No Command+A, Delete, Backspace, simulated keys, Return, pasteboard access or whole-field write is used for AI replacement. AXManualAccessibility/AXEnhancedUserInterface activation remains disabled.

**AX operations are not an atomic compare-and-swap.** Preflight rejection leaves text untouched. If the external editor changes after preflight, selection may already have changed; a dispatched write may be unverified. Such outcomes are explicitly uncertain, with no retry or automatic rollback. Absolute race-free replacement in arbitrary editors is not claimed. Native IME/identity/write paths have source review and existing policy coverage, not proof from real editor mutation tests. Unsupported capabilities remain a blocker rather than a keyboard fallback.

## AI safety and concurrency

The existing Apple on-device provider, availability checks and unchanged 4 GiB floor are reused; no model/provider thresholds or speech recognition behavior changed. There is one in-place operation ID; rapid duplicates are suppressed. New dictation, cancellation, shutdown and feature disable invalidate the ID and discard late output. The anchor is checked before and after generation. Source edits during inference discard replacement after generation; immediate per-keystroke cancellation is not claimed.

Already-restored Smart Polish output is checked again through the existing protected-span/ordered lexical contract. Prompt Engineering is checked against its original source lines and permitted ordered headings. Invalid, memory-blocked or unavailable generation retains the original without automatic retry. These conservative constraints can reject useful stylistic changes; they do not prove semantic/model quality. This milestone performed **no live AI generation**, no model resource measurement and no physical shortcut delivery experiment. Synthetic drivers prove routing/effects boundaries only.

## Automated verification

Toolchain: /Applications/Xcode-beta.app/Contents/Developer, Xcode 27.0, Swift 6.4, macOS SDK 27.0; target macOS 26.0 arm64. Host macOS 27.2 (26B5112a), MacBook Air M4/16 GB. This is not a macOS 26 runtime acceptance claim.

| Check | Actual result | Exit |
|---|---|---|
| focused | 137 expanded cases / 87 declarations, 0 failures, 0 skips | 0 |
| full | 1089 expanded cases / 512 declarations, 0 failures, 0 skips | 0 |
| replay | 1089 expanded cases / 512 declarations, 0 failures, 0 skips | 0 |
| recovery | 35 expanded cases / 16 declarations, 0 failures, 0 skips | 0 |
| Debug build | passed | 0 |
| Release build | passed | 0 |
| Release strict concurrency build | passed | 0 |
| Model Lab | 152 tests + 7 resource guard tests; no model inference | 0 |
| Repository/artifact/license/secret checks | passed (tracked working files/history) | 0 |
| Module boundaries | new Domain → Foundation; VoiceInput → Domain + system frameworks; Package.swift unchanged | 0 |
| Git diff whitespace | passed | 0 |

The full baseline was 1,074 expanded cases / 502 declarations; 15 cases / 10 declarations were added, yielding 1,089 / 512. New coverage includes real PCM/stride, quiet/loud/silence/stale/invalid level mapping, decay/reset, truthful HUD mapping, both AI shortcut routes, no autogeneration, exact-span surroundings and immutable history, duplicate suppression, edited/foreign/uncertain target rejection, memory/invalid output rejection, cancellation/edits during generation and preference persistence. Existing preview, voice, clipboard and recovery tests remain enabled. Native AX mutation, real engine restart/cancellation with hardware, Reduce Motion appearance and microphone latency still require physical checks.

### Failures investigated and retained

The initial full run (Evidence/Milestone36/Acceptance/full) exited 65. Three prior tests expected immediate terminal hiding; they now assert brief feedback **and** deterministic eventual dismissal with an injected HUD clock. Assertions for receipt/history/message behavior remain.

The previously intermittent lateSuccessIsDiagnosticAndCannotReplaceTimeout also reproduced: cleanupIncomplete rather than timeout, then a 60-second event wait. The fixture advanced its cleanup clock after the adapter cancellation callback but before the cancellation record committed; that callback intentionally precedes persistence. The fixture now waits for the cancelling state before advancing, preserving the timeout intent. No production TaskExecution code changed; separate storage-stall/cleanup-timeout tests remain. The final full/replay and the dedicated entire RemediationTests suite passed, including that test. This removes the fixture's unintended scheduling race, not a claim that all persistence failures are impossible.

One exact-test selector selected zero tests and is **not counted as recovery verification**. A subsequent dedicated suite attempt collided with the running Release build database and exited 65; I had scheduled overlapping builds in the same DerivedData directory. The final dedicated suite was run sequentially and passed. All failed/invalid attempt logs remain; none was hidden, disabled or counted as passing coverage.

Command/exit/timestamp records and logs: Evidence/Milestone36/FinalVerified/{focused,full,replay,debug,release,concurrency,model-lab,repository}.json and .log; native .xcresult bundles and summaries alongside. Dedicated recovery: Evidence/Milestone36/RecoveryFinal/recovery.{json,log,xcresult}. Exact commands are in each JSON argv, using:

```
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone36 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 -configuration Debug -parallel-testing-enabled NO -resultBundlePath <unique path> test
```

Focused test selections and the separate RemediationTests selection are recorded in argv. Full/replay use no test exclusions. Debug/Release use configuration + build; concurrency adds SWIFT_STRICT_CONCURRENCY=complete. Model Lab uses python3.11 Tools/CI/run_checks.py model-lab --output <evidence>; repository checks use Tools/CI/repository_checks.py. Nonblocking AppIntents metadata warnings are present (no AppIntents.framework dependency); no new Swift concurrency warning was observed.

## Physical handoff — not yet performed

The user agreed to test after verification. All actual physical acceptance rows remain **UNVERIFIED**:

| Check | ChatGPT Mac | TextEdit | Codex Desktop | VS Code |
|---|---|---|---|---|
| quiet/normal/loud/silence waveform | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| transcription / continuous HUD / verified insertion | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| Option+1 in-place polish | UNVERIFIED | UNVERIFIED | UNSUPPORTED by existing direct-write policy | UNVERIFIED |
| Option+2 in-place prompt | UNVERIFIED | UNVERIFIED | UNSUPPORTED by existing direct-write policy | UNVERIFIED |
| edited-source rejection / clipboard / no submission | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |

Verified test bundle: `DerivedData/Milestone36/Build/Products/Debug/Wesley Flow.app`. SHA256s of the executable/debug dylib are in Evidence/Milestone36/FinalVerified/test-build-hashes.json. Two older executables were running at inspection: Milestone35A and the default Xcode DerivedData build. Neither was quit or replaced. Before testing, quit both **normally** only while idle; stop on active dictation or clipboard-recovery warnings. Open the exact Milestone36 bundle. Do not run multiple instances.

Enable In-place AI rewrite before a NEW synthetic dictation; enable Smart Polish/Prompt Engineering and Preview shortcuts. Hold the configured dictation key in an empty test composer. Vary volume, pause in silence, release; inspect actual text and HUD. Invoke Option+1 on that fresh verified insertion. Use a separate new dictation for Option+2 (one-use anchor). Never submit. Repeat with a manually edited source; no replacement should occur. Inspect clipboard privately; do not send its contents as evidence. Unknown IME or exact-range support should produce a safe rejection. Resource rejection should retain original text; do not retry repeatedly. Turn experimental opt-ins back off when finished.

## Git and preserved features

Branch feature/milestone-31-integration, HEAD 23caeca630b803fddc2cd007a5159dc9839b71cf unchanged. Existing M32–35A uncommitted work and reports preserved. No files staged, no commit/push/merge; PR #1 and main untouched. Package graph unchanged; no external dependency or downloaded asset. Existing clipboard lease implementation, history, Insights, dictation hotkey conflict controls, preview capture/fallback, Command Mode, privacy and model settings remain.

Working tree before this report (this report is additionally new):

```
 M App/AppComposition.swift
 M App/ClickableDictationPill.swift
 M App/DictationPreferences.swift
 M App/GlobalDictationView.swift
 M App/SystemWideDictationCoordinator.swift
 M App/WesleyFlowApp.swift
 M AppTests/DictationTests.swift
 M AppTests/GlobalDictationTests.swift
 M Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift
 M Packages/WesleyFlowCore/Sources/Domain/PromptEngineering.swift
 M Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
 M Packages/WesleyFlowCore/Sources/VoiceInput/AppleDictationInput.swift
 M Packages/WesleyFlowCore/Sources/VoiceInput/NativeSpeechCallbacks.swift
 M Packages/WesleyFlowCore/Tests/Phase1ATests/CoordinatorTests.swift
 M WesleyFlow.xcodeproj/project.pbxproj
?? Docs/Engineering/MILESTONE32-HOSTED-CI.md
?? Docs/Engineering/MILESTONE33-ACCEPTANCE.md
?? Docs/Phase1F/CONTEXT-AWARE-TEXT-CAPTURE.md
?? Docs/Phase1F/GLOBAL-SHORTCUT-DELIVERY-FIX.md
?? Docs/Phase1F/MILESTONE35A-CAPTURE-REPAIR.md
?? Packages/WesleyFlowCore/Sources/Domain/DictationEnhancements.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/FocusedTextResolver.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AudioLevelMailbox.swift
?? Packages/WesleyFlowCore/Tests/WorkspaceTests/FocusedTextResolverTests.swift
```

## Acceptance

Automated implementation gate **PASSED**. Physical/live in-place acceptance **PENDING**, not production-verified. Broad editor support and strict IME capability are the principal compatibility blockers. Model quality/resource admission and non-atomic external AX mutation remain explicit limitations. No universal cross-app or live AI rewrite success is claimed.
