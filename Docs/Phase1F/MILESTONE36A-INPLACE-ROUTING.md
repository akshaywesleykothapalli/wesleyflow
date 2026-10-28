# Milestone 36A — In-place AI routing

27 October 2026. Scoped routing hardening and automated verification **PASSED**. Actual physical shortcut owner and in-place editor/model acceptance remain **UNVERIFIED**. In-place AI remains default OFF; the user's saved preference was not changed. No app was quit/replaced, no commit/push/merge was performed, and the waveform/audio implementation was not modified.

## Actual cause and what is not established

The saved `dictation.preferences.v1` payload in `local.wesleyflow.WesleyFlow` reports:

| Flag | Observed saved value |
|---|---|
| inPlaceAIRewrite | **false** |
| offlineAIRewriting | true |
| promptEngineeringEnabled | true |
| previewShortcutsEnabled | true |

The exact current branch in SystemWideDictationCoordinator.invokeShortcutPreview is: if inPlaceAIRewrite is true, call invokeInPlaceRewrite and **return**; otherwise continue into preview resolution and publish previewPresented. Thus OFF intentionally selects the preview editor. Source inspection and registered-callback regression reproduce this branch for both shortcuts. No inverted mode check or in-place-to-preview failure fallback was found in Milestone36 source. The default-OFF migration is intentional and was not bypassed to satisfy the desired workflow.

Two Wesley Flow processes were simultaneously running at initial inspection:

| PID | Executable location | On-disk identity evidence |
|---|---|---|
| 60189 | DerivedData/Milestone35A/Build/Products/Debug/Wesley Flow.app/Contents/MacOS/Wesley Flow | debug dylib SHA256 a798341dc12d92e2151c3d942e59f2aa629567ccf1ee97b9f73bca99e50e9687; lacks inPlaceAIRewrite/result symbols |
| 70992 | ~/Library/Developer/Xcode/DerivedData/WesleyFlow-cccpncdspkgnnbgnvimlzzhfmozl/Build/Products/Debug/Wesley Flow.app/Contents/MacOS/Wesley Flow | debug dylib SHA256 75e6322ac19f89ae9b103cfecd18eb36a1ef78f0fd98e6509bcd4586aa4a85ba; contains the in-place pathway |

The separately verified Milestone36 debug dylib SHA256 was d422f78b91b1789e59cee80fa8d33b844dab4338d8da1c18646b0a680acde450. All application marketing versions remain 0.1.0/build1; that label alone cannot identify source content. The newer default-Xcode artifact is not hash-identical to that Milestone36 diagnostic build. These hashes identify **files on disk**, not proof that the file was never rebuilt after process launch.

NativePreviewShortcuts registers exclusive Carbon keys. Multiple instances can conflict, and the old35A instance cannot implement in-place mode. However, no OS key was injected, debugger attached or real keypress trace obtained. **Which process owned/received the user's reported keypress, its cached preferences at that instant, and whether it was the older instance remain unknown.** Current saved OFF status is a confirmed explanation for the current preview branch, not a fabricated historical runtime trace. No private text, history or clipboard contents were inspected.

## Changes made

Only four existing source/test files were changed for36A, preserving all cumulative uncommitted work:

- App/SystemWideDictationCoordinator.swift: bounded debug-only routing trace (32 enum metadata records), persistent-vs-memory mode disagreement rejection, explicit mode selection, dismissal of pending preview state before in-place validation, precise source/provider outcomes, and in-place cancellation when shortcut delivery becomes unavailable/disabled. The last compact AI outcome remains inspectable in the existing General shortcut-status row after the HUD dismisses.
- App/GlobalDictationView.swift: the existing In-place AI switch description now explicitly states the current route and identifies36A. No screen or control redesign; native binding/default unchanged.
- App/WesleyFlowApp.swift: existing manual-preview panel title now identifies36A rather than35A. It remains available only through preview mode/explicit actions.
- AppTests/GlobalDictationTests.swift: registered-callback mode/routing, provenance, failure and consistency regressions. No existing test removed or weakened.

The handler reads its current preference and compares it with the store before choosing a route. Conflicting saved and in-memory modes fail closed with an explanation; they never silently choose preview, rewrite, change settings or write text. This does not stop an already-running old binary from using its own old handler. Safely quitting duplicates is still required. A stale older instance may overwrite a whole settings payload if it saves changes; that possibility was not reproduced and is not presented as the observed cause.

## Execution trace and provenance

Both physical keys converge on the same production callback:

```
Carbon key 18 / 19 -> NativePreviewShortcuts delivery/gesture validation
 -> invokeFrom(polish / promptEngineering, original PID)
 -> coordinator.invokeShortcutPreview -> current/saved mode consistency
 -> ON: inPlaceSelected -> latest verified anchor -> source validation
 -> existing offlineRewriter.rewrite(original own transcript, selected kind/tone)
 -> response preservation validation -> source revalidation
 -> one exact-span AX replacement -> receipt verification -> compact HUD
```

The deterministic registered callback recorded/asserted this exact successful trace for **each** kind:
`received -> inPlaceSelected -> generationRequested -> generationReturned -> replacementRequested -> replacementVerified`.

OFF records `received -> previewSelected` and opens the existing preview without automatically generating. Missing dictation records noEligibleDictation; stale/secure/unsupported/permission failures record sourceRejected. Stale saved configuration records settingsDisagree. No diagnostic record can contain a transcript, prompt, clipboard value, document hash or source text. These are **synthetic execution traces**, not a claim of physical OS delivery.

An in-place attempt immediately cancels pending preview capture/generation and clears presentation. Failures show the existing compact warning and distinct explanations for no eligible dictation, disabled feature, pending clipboard recovery, foreign app, oversized input, unsupported editor/IME state, Accessibility denial, changed/expired source, local AI unavailable, resource admission, timeout/cancellation, invalid output, or unverified replacement. No failure automatically opens the editor.

Milestone36 provenance remains: latest app-owned **verified** insertion only; own transcript/session, PID+launch, window+field, UTF-16 range, expected full-context SHA256, activation epoch and120-second monotonic expiry. No authority is reconstructed from history. Failed/uncertain insertions and unrelated/edited text remain ineligible. Anchor is checked before/after generation and consumed before effects; history and word metrics remain original. No AI keystrokes, Enter, automatic submission, pasteboard mutation or whole-document replacement.

## Provider and editor limitations

Production composition still injects AppleTranscriptRewriter(memory:SystemInferenceMemory(), clock:SystemTaskClock()), whose generator uses the existing explicitly on-device FoundationModels session. Prompt Engineering's actual request receives the original own transcript and kind; regression assertions verify both. Complete responses pass the existing protected-text or source-unit/heading contracts before any effect. No hardcoded response was added to production. Test drivers are explicitly synthetic.

No live model generation or new memory measurement occurred in36A. Existing4GiB admission, normal-pressure and nonincreasing-swap conditions are unchanged. Model quality/readiness and a successful real rewrite are **NOT VERIFIED** by these fixtures.

Exact-range AX mutation remains conservative. Unknown AXMarkedTextRange/IME state, missing readable/settable ranges or unsafe field identity reject rewriting. Codex direct replacement remains unsupported by the existing policy; Terminal remains manual-copy only. ChatGPT, TextEdit and VS Code are capability-dependent, physically unverified. No AXManualAccessibility/AXEnhancedUserInterface activation was enabled. AX calls are not atomic compare-and-swap: preflight rejection leaves text unchanged; a failure after selection/write dispatch may change selection/text and is reported uncertain, never automatically retried or rolled back. Universal safe replacement is not claimed.

## Actual automated verification

Toolchain: /Applications/Xcode-beta.app/Contents/Developer, Xcode27.0/Swift6.4, SDK27.0, target macOS26.0 arm64. Tests run on this Mac's macOS27.2; not a macOS26 runtime compatibility claim.

| Check | Actual outcome | Exit |
|---|---|---|
| focused | 152 expanded cases / 93 declarations, 0 failed, 0 skipped | 0 |
| full | 1104 expanded cases / 518 declarations, 0 failed, 0 skipped | 0 |
| replay | 1104 expanded cases / 518 declarations, 0 failed, 0 skipped | 0 |
| debug | passed | 0 |
| release | passed | 0 |
| concurrency | passed | 0 |
| Debug bundle signature | codesign --verify --strict passed | 0 |
| Changed/new file secret/artifact scan | no issues; contents not printed | 0 |
| Git diff whitespace | passed | 0 |

Baseline1,089/512 is retained. Added15 expanded cases /6 declarations yield **1,104/518**. New tests exercise the actual coordinator registration callback for ON/OFF and both kinds, correct original request text, no unwanted panel, exact replacement with surroundings/history preserved, clipboard/no-key safeguards, typed permission/secure/unsupported/stale failures, missing recent dictation, both settings disagreement directions, and unavailable/resource-blocked/timed-out/cancelled generation. Existing invalid-output, edits-during-generation and cancellation coverage remains. These callback fixtures do not prove which running native process owns Carbon registration.

Initial36A focused verification also passed; final verification includes the additional outcome tests. No36A tests failed or were bypassed. The previously flaky Phase1A late-success timeout regression passed in full/replay with its preserved Milestone36 synchronization fix; no further recovery changes were made. Nonblocking AppIntents metadata and local com.apple.linkd.autoShortcut service warnings remain in build/test output; they are not proof of physical shortcut success/failure.

Exact commands, exit codes and timestamps: Evidence/Milestone36A/Final/{focused,full,replay,debug,release,concurrency}.json and .log. .xcresult bundles and extracted summaries alongside. All builds ran sequentially in DerivedData/Milestone36A. Every command uses:

```
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone36A -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 ...
```

Full/replay append `-configuration Debug -parallel-testing-enabled NO -resultBundlePath <unique path> test`, without exclusions. Focused argv records all suite selectors. Build actions use Debug/Release build; concurrency adds SWIFT_STRICT_CONCURRENCY=complete. No model downloads, inference, key injection or app text access occurs in tests. No dependency/package graph or speech/waveform source changed in36A.

## Physical acceptance and safe handoff

No user-operated36A result has been supplied. Request issued; all rows remain **UNVERIFIED**:

| Check | Result |
|---|---|
| TextEdit new dictation + Option+2, no panel, actual replacement | UNVERIFIED |
| ChatGPT new dictation + Option+2, no submission | UNVERIFIED |
| Option+1 Smart Polish, no panel | UNVERIFIED |
| Edit original first: no stale overwrite | UNVERIFIED |
| Real unavailable/resource-blocked model preserves original | UNVERIFIED |
| Clipboard/focus and true native hotkey owner | UNVERIFIED |

Verified bundle: `DerivedData/Milestone36A/Build/Products/Debug/Wesley Flow.app`; executable/debug-dylib SHA256s in Evidence/Milestone36A/Final/build-hashes.json. Existing instances were left untouched. No new interactive app was opened beside the two old instances, to avoid ambiguous hotkey ownership/session interference.

1. Quit **both older copies normally**, only when dictation and clipboard recovery are idle. Stop on any recovery/session warning; never force-quit.
2. Open the exact36A bundle above. Smart Formatting's In-place AI description must begin **36A**. Explicitly enable In-place AI rewrite, the desired AI feature(s), and General preview shortcuts. Verify the route description says in-place. This task left the saved switch OFF.
3. Dictate **new** harmless synthetic text into TextEdit, release and confirm verified insertion. Press/release Option+2 within120 seconds without switching field or moving the caret. Inspect that no preview opens; either verified replacement or a specific safe-rejection message is valid evidence. Never send/press Enter.
4. Repeat in ChatGPT; try Option+1 on a separate new dictation. Edit a new dictated span before invoking: it must be rejected. Unsupported editor/IME capability and resource admission should preserve text. Do not repeatedly retry a resource rejection.
5. The warning pill's tooltip/accessibility help contains the exact reason; the latest outcome also remains in General's shortcut-status row. Report the reason, not private text. Check clipboard privately. Restore optional settings afterward if desired.

If a preview still opens with the36A setting explicitly ON, capture only the build identity/mode/status and which app was active. Do not infer a provider/memory error from a wrong process or mode. Physical ownership and compatibility still require this handoff.

## Git

Branch feature/milestone-31-integration; HEAD23caeca630b803fddc2cd007a5159dc9839b71cf unchanged. Main and PR#1 untouched. Nothing staged; no commit, push, merge, reset, app replacement or preference opt-in. Prior uncommitted36/35A/application/voice/clipboard/ModelLab work remains.

Cumulative working tree (includes prior work, plus this report):

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
?? Docs/Phase1F/MILESTONE36-SEAMLESS-DICTATION.md
?? Packages/WesleyFlowCore/Sources/Domain/DictationEnhancements.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/FocusedTextResolver.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AudioLevelMailbox.swift
?? Packages/WesleyFlowCore/Tests/WorkspaceTests/FocusedTextResolverTests.swift
```

**Outcome:** intended ON/OFF routing and failure isolation are reproducibly verified in the registered app callback. Saved OFF configuration explains the current preview branch. The actual previously observed physical listener and live in-place success are not claimed fixed/verified without the single-build, opt-in user test.
