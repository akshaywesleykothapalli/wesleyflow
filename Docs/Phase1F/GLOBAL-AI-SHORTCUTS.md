# Milestone 29 — Global AI shortcut verification

Date: 2026-10-26. **Implementation and automated/native registration checks passed. Physical cross-application delivery remains UNVERIFIED at the user's explicit request.** This is not a claim that Option+1/2 have been physically accepted in all four apps.

## Inspection and confirmed gaps

Read AGENTS.md, current Phase1D/1F reports, Domain shortcut/preview contracts, Carbon registrar, coordinator lifecycle, preview/settings/preferences, AppDelegate composition, speech shortcut and insertion/clipboard contracts and relevant regression tests. Preserved all uncommitted milestone-28 work. Branch remains `ci/milestone-27`, HEAD `3befcf20ff60220c5f678aa1c3c1a137064b4ea3`.

Confirmed by source inspection:

1. Shortcut invocation called the provider/status path, but never opened a preview surface. Empty input also left the user in the other app with only an unseen status update.
2. The observer named `wake` observed application activation only. No sleep cancellation or wake registration recovery existed.
3. Focus and modifier state were sampled only when the asynchronous stream consumed an event. There was no event-age/activation-generation fence preventing queued signals from being interpreted against a later context. This was a design gap, not a claimed reproduced physical misdelivery.

## Implemented behavior

- Option+1 opens a **Smart Polish** preview; Option+2 opens a **Prompt Engineering** preview. A compact nonactivating NSPanel uses the existing coordinator/results, original text, explicit reviewed Copy, Reject, Cancel and Close actions. It cannot become key or main, does not activate Wesley Flow, and never restores focus by activating another app. No Enter/Return shortcut or synthetic input is generated. Actual cross-app focus preservation still requires physical acceptance.
- Empty input opens the correct preview with clear instructions to enter/select input in Smart Formatting. It does not call the model. A rapid second chord cannot replace a pending request's kind, original source or origin process identity.
- The app stays resident after its last main window closes when the user has opted into preview shortcuts. Default preferences are unchanged.
- Global Carbon registration still uses exact Option plus physical numeric keys, current-layout translation checks, enabled macOS symbolic-shortcut conflict checks and exclusive registration. System conflicts are rechecked immediately before invoking a preview; failure disables delivery. Application-menu shortcuts are not fully enumerable and may be superseded only under the existing explicit global-shortcut opt-in/warning.
- Native callbacks enqueue metadata only: gesture, Secure Input, disallowed modifiers, observed foreground process/activation epoch and receipt time. No text, AX selection, window/document contents or clipboard is read. The C boundary uses a small `Synchronization.Mutex` metadata bridge because C callbacks cannot safely read MainActor AppKit state; this does not add locking to actor-owned lifecycle state.
- Application activation synchronously invalidates the metadata epoch before updating the new process on MainActor. Delivery checks current process, matching activation epoch, age between zero and one second, valid layout/modifiers and Secure Input. Backlogged, unmatched and invalidated releases fail closed. The one-second bound expires stale events; it is not an insertion delay or a promise of delivery under a blocked event loop.
- Gesture state suppresses repeated presses and duplicate/unmatched releases; invocation occurs on a valid release. Option need not remain held after key-up, but extra Command/Control/Shift/Fn invalidates the gesture. The Carbon registration itself requires Option.
- Sleep invalidates pending key context and cancels generation. Wake acquires fresh registrations after rechecking layout, Secure Input and system conflicts. Registration epochs fence old stream deliveries/observer callbacks. Wake failure reports unavailable and requires Retry; it never silently assumes recovery succeeded. Disabling shortcuts closes/cancels a shortcut preview. Overflow of the bounded 16-event queue fails closed instead of silently completing a damaged gesture.

Native FoundationModels cancellation, availability checks, eight-second deadline, output/fidelity checks, single settling-session ownership, 4 GiB floor and swap/pressure guard are unchanged. No model was invoked in this milestone. The milestone-28 resource block is historical evidence, not a new measurement here.

## Authorized input and permissions

Currently supported input sources are **text entered in Wesley Flow** or an **explicitly selected eligible completed dictation history entry**. The existing explicit latest-dictation button remains available. Selection in TextEdit, ChatGPT, Codex or VS Code is **not automatically read**; there is no implemented authorized external-selection reader. Those apps supply foreground context only. Unsupported, empty, disabled or inaccessible input yields a non-destructive empty/status state.

Preview opt-ins and global-shortcut opt-in remain separate and persist through the existing preference store. The hotkey registrar requests no microphone, Accessibility or Input Monitoring permission. Dictation retains its existing permission path. No AXManualAccessibility/AXEnhancedUserInterface activation, Terminal typing, arbitrary shell, cloud AI, model download or generated-code execution was added.

Clipboard writes occur only through an explicit reviewed Copy action and the unchanged lease-aware copy path. Opening, generating, cancelling, rejecting and closing do not copy or paste. No general clipboard contents were inspected for diagnosis. The deterministic fixtures assert zero target capture, copy and insertion for empty/input-authorized shortcut invocation. Existing real private-pasteboard fixture tests remain in the full suite; they do not establish native cross-app clipboard behavior.

## Actual native registration result

A brief separate process linked the current frameworks and checked native APIs without synthesizing keys, opening a model session or inspecting text. Compile exit0; probe exit0:

| Check | Actual result |
|---|---|
| Current numeric layout maps physical keys to 1 and 2 | true |
| Secure Input at probe time | false |
| Enabled macOS symbolic conflict for both chords | false |
| Register both chords | PASSED |
| Second exclusive owner of Option+1 | Rejected, OSStatus -9878 |
| Repeated disable, cleanup and register again | PASSED |
| Physical keys sent | none |

Evidence: `Evidence/Milestone29/NativeRegistration/{compile.json,probe.json,source.swift}`. Temporary registrations were released. Registration success is not physical delivery, alternative-layout support or actual sleep/wake acceptance. No system shortcut preference was changed to manufacture a conflict.

## Physical results and manual matrix

The user explicitly answered **“Leave physical delivery unverified.”** No physical key experiment, intrusive input automation, app-content inspection, prompt submission, forced quit or installed-app replacement was performed. An older Wesley Flow development build was observed running; it was left intact to avoid disrupting dictation or pending clipboard recovery.

Every cell below is an actual status, not a simulated success:

| Foreground application | Shortcut | Received | Correct preview | Authorized input | Model outcome | Focus | Clipboard | Cancel |
|---|---|---|---|---|---|---|---|---|
| TextEdit | Option+1 | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| TextEdit | Option+2 | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| ChatGPT macOS | Option+1 | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| ChatGPT macOS | Option+2 | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| Codex Desktop | Option+1 | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| Codex Desktop | Option+2 | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| VS Code | Option+1 | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| VS Code | Option+2 | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |

### Procedure for a later user-operated test

1. Quit the old app normally. If its guard reports active dictation or clipboard recovery, resolve that first; do not force quit. Open `$REPO_ROOT/DerivedData/Milestone29/Build/Products/Debug/Wesley Flow.app`. No installed app needs replacement.
2. Enable both preview features in Smart Formatting and Preview shortcuts in General. Check registration status. Begin with input empty. In a disposable blank field in each listed app, press/release each chord. Expect the correct nonactivating preview with “No permitted input,” no model call, no text insertion, no Return and the original foreground app unchanged. Close the panel between attempts.
3. For authorized-input checks, **enter the sample in Wesley Flow**, not another app. Smart Polish sample: `um please check the button`. Prompt sample: `Improve the button. Keep keyboard access. Do not add dependencies. Return a short explanation.` Return to each listed app and invoke the appropriate preview. Compare Original with the entered sample; record actual model status and result, never infer success from panel appearance. External selected text must not be imported.
4. Record whether pending generation can be cancelled/closed, whether a second rapid chord leaves the first source/kind intact, and whether late output stays discarded. If admission blocks generation, stop further nonempty/model attempts; remaining delivery checks can use empty input. A blocked outcome is not successful inference.
5. For clipboard checks, the user may explicitly copy a harmless sentinel first. Do not click Copy in the preview. Verify the sentinel remains unchanged using a disposable local field, without sharing clipboard contents. Separately test explicit reviewed Copy if desired, respecting any lease warning. Record focus and clipboard observations rather than assuming the panel's style guarantees them.
6. With only synthetic/empty input, manually test an ordinary sleep/wake cycle, held-key repeats, an app switch between press/release, and a Secure Input context. Do not alter security/system shortcut settings just to force a pass. Alternative layouts and system conflicts require separate actual observations. Finally disable preview features/shortcuts if they were enabled only for this test. Verify hold-Fn dictation separately without sending text anywhere.

Only report result/status metadata and synthetic text; private documents, conversation text and clipboard contents are unnecessary.

## Automated regression and builds

Selected `/Applications/Xcode-beta.app/Contents/Developer`, Swift6 / macOS26 deployment, arm64 test destination. The project, package dependencies and preference schema are unchanged. New deterministic tests exercise the actual delivery state machine for both chords, ten consecutive gestures with repeated down/up signals, focus mismatch, stale/future events, blocked modifiers/Secure Input/sleep, cancellation, unknown origin and valid subsequent sessions. Coordinator tests cover both empty preview kinds/origin binding with no model/copy/capture effects, rapid chord isolation, sleep cancellation, late-result rejection and non-key panel construction. These are not physical GUI tests.

| Verification | Expanded cases | Declarations | Failed/skipped | Exit |
|---|---:|---:|---:|---:|
| Final focused Workspace + application | 679 | 369 | 0/0 | 0 |
| Full suite | 1,025 | 477 | 0/0 | 0 |
| Independent full replay | 1,025 | 477 | 0/0 | 0 |
| Debug build | — | — | — | 0 |
| Release build | — | — | — | 0 |
| Explicit complete-concurrency Release | — | — | — | 0 |

The 1,013-case milestone-28 baseline is retained, with 12 expanded cases / six declarations added. Ordinary dictation lifecycle, repeated insertion, clipboard leases, preview/provider cancellation and resource rejection regressions all remain included; no tests were excluded, removed or weakened. No arbitrary sleep was added to synchronize new tests.

Exact commands, timestamps and exits: `Evidence/Milestone29/{focused-final,full,replay,debug,release,concurrency}.json` and logs. Test bundles/summaries retain expanded/declaration counts separately. Common prefix:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild \
  -project WesleyFlow.xcodeproj -scheme WesleyFlow \
  -destination platform=macOS,arch=arm64 \
  -derivedDataPath DerivedData/Milestone29 \
  -disableAutomaticPackageResolution -skipPackageUpdates
```

Focused adds `-configuration Debug -resultBundlePath Evidence/Milestone29/focused-final.xcresult test -only-testing:WorkspaceTests -only-testing:WesleyFlowAppTests`. Full/replay use their fresh result bundle and omit those filters. Builds add Debug/Release and `build`; concurrency adds `SWIFT_STRICT_CONCURRENCY=complete` to Release. Compilation is not a runtime race proof. Existing AppIntents metadata-extraction warning remains.

Initial compile failure retained as `focused-initial` exit65: deprecated GetFrontProcess/GetProcessPID APIs are unavailable in Swift. Those calls were removed, not bypassed with private APIs/unsafe actor assertions. The final metadata bridge compiled and all final checks passed. Earlier intermediate focused run also passed.

## Preservation, Git and remaining blockers

Only four production files changed **during this milestone**: `App/WesleyFlowApp.swift`, `App/SystemWideDictationCoordinator.swift`, core Domain `PromptEngineering.swift` and SystemOperations `NativePreviewShortcuts.swift`. Two existing test files have appended suites; this report is new. The earlier milestone-28 changes, evaluation set/tool/report remain intact and uncommitted. `Evidence/Milestone29/boundaries.json` records task-start hashes, preserved test prefixes, unchanged dependencies and empty staging. Speech, dictation hotkey, native target/insertion and clipboard broker, AI provider/memory logic, preference source and existing main UI match task-start hashes.

No commit, push, remote/visibility change or release. Branch/HEAD unchanged. Evidence/build products remain ignored. Working tree contains the prior milestone-28 work plus this milestone; it is intentionally not clean.

Remaining blockers:

- Physical Option+1/2 acceptance in all four apps, focus/clipboard preservation, actual panel controls, physical cancellation and wake/sleep delivery: **UNVERIFIED**, user declined testing.
- No actual model output or new resource measurement was obtained. Provider outcomes and current memory availability during real shortcuts remain unverified; prior live generation was resource-blocked.
- Application-specific shortcuts cannot be exhaustively detected. The opt-in explicitly warns about global reservation; system conflicts and exclusive ownership are checked without silently changing system preferences.
- The conservative metadata/age fences can reject a gesture during focus/layout transitions or event-loop stalls. A fresh gesture is required; there is no delayed retry or automatic insertion.
- External selected-text capture is deliberately unsupported. Use entered text or explicitly selected completed history.

**Readiness: native registration and automated regression verified; global physical shortcut reliability is not yet accepted.** Stop after this milestone.
