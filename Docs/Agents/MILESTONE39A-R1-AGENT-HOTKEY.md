# MILESTONE 39A-R1 — Separate press-and-hold Agent voice hotkey

Latest correction: **39A-R1.1 / 39.0.3**. The user reported no response from Right Control or Right Command in 39.0.2. That build is **not physically accepted**. See the follow-up below; 39.0.3 physical acceptance is pending.

Date: 29 October 2026 (Asia/Kolkata). Build: 39.0.2. Status: implemented; automated evidence below; physical acceptance pending.

## Root cause of the 39.0.1 report

39A implemented a text planner and an **opt-in, one-shot armed voice route**, not a second Agent shortcut. `armCommand()` set `commandArmed`; `begin(manual:fromShortcut:activation:)` selected `commandSession = fromShortcut && commandArmed` and immediately cleared the arm. Without that prior UI action, the global key captured an insertion destination and `finish(id:forced:)` ran ordinary dictation insertion/history. Speaking an agent-like sentence did not select the agent. A failed or consumed arm reverted the next gesture to dictation. The compact HUD also used the dictation waveform/Transcribing/Ready resolver for both routes, obscuring the distinction. There was no independently configured Agent event source. This explains the routing defect in the source; it is not a retrospective measurement of the user's physical recognition session.

## Implemented route and authority

- Existing dictation monitor → existing press/release handler → `begin(...agent:false)` → original destination binding, speech, final formatting, insertion verification, clipboard recovery and history. Command-like words remain text. Neither `commandArmed` nor the old arm API can turn this shortcut into Agent; the compatibility method only enables the independent Agent shortcut. The old arm UI and next-gesture picker were removed.
- Separate `NativeDictationShortcut` instance → independent generation/held latch → `begin(...agent:true)` → the same `AppleDictationInput` → release → final reliable transcript → `reviewAgentCommand` → `PersonalIntentParser` → durable `PersonalAgentEngine.enqueue` → **explicit review and Approve** → existing typed native tool adapters → saved receipts. No voice callback grants approval.
- Agent transcript handling returns before insertion, target capture and dictation history. Only whitespace is cleaned; dictation vocabulary, formatting and AI rewriting cannot change the command. There is no paste, simulated typing, clipboard installation, ChatGPT/Codex submission, shell command or communications route. Existing clipboard reconciliation may retire an obsolete recovery record when a newer copy already superseded it; this does not write the clipboard or retry text.
- One coordinator/session/input owns the microphone. Agent cannot start during dictation, finalization, insertion, in-place rewriting, another Agent operation or an unresolved Agent plan. Dictation cannot start during Agent capture. Overlapping native modifier chords cancel capture rather than launching another one. Distinct press and release latches reject repeated downs; duplicate final/late callbacks are fenced by the session ID. A cancelled held Agent key must be released before another capture.
- Release while preparing cancels; release while recording finalizes once. The inherited 8-second finalization watchdog fails closed. The inherited speech adapter and its long-hold, timestamp/range, converter, resource-admission, failure and recovery behavior remain byte-identical. Unexpected completion, missing/oversized/partial speech, permission denial and all speech failures cannot enqueue a plan. Partial recovery is diagnostic/manual data, never an executable request.
- Escape/cancellation, monitor loss, wake, permission loss, disabling or rebinding Agent cancel its pending capture. Stale monitor generations cannot start or finish another session. Execution cancellation asks the existing engine to stop remaining steps and retains actual in-flight receipts; it cannot undo an external effect.

## Shortcut/default and security

Default Dictation remains the user's saved key (Fn/Globe for the existing default). Default Agent is **Right Control**, physical virtual keycode 62, delivered through flagsChanged, with physical selected-key state distinguishing down/up. It is configurable independently in General. Standalone Fn, Right Option, Right Command and Right Control remain available choices; enabled Dictation and Agent cannot share a key.

Read-only host assessment in `Evidence/Milestone39A-R1/keyboard-assessment.txt`: an attached USB RGB Keyboard advertises HID keyboard Right Control (page 7, usage E4). The native `CopySymbolicHotKeys` query succeeded and found no enabled system shortcut on keycode 62. Existing app bindings use the saved dictation modifier and optional Option+1/Option+2 preview commands, not standalone Right Control. Therefore Right Control was selected without moving dictation. HID capability establishes advertised support, not a witnessed physical key press. Some built-in keyboards lack a physical right Control; use the attached keyboard or rebind in General. Physical delivery is an acceptance gate.

Registration validates enabled macOS symbolic shortcuts and fails closed if that inventory cannot be read. Conflicts with Dictation and Option preview shortcuts are rejected, including preference changes after registration. Foreign applications' arbitrary modifier monitors cannot be exhaustively enumerated or exclusively reserved by a listen-only event tap; check any custom binding in those apps and rebind if necessary. The native monitors continue to pass key events through. Adding another key to a held modifier cancels rather than stealing normal OS chords.

Agent admission verifies Accessibility, Secure Input, focused-element security metadata, and the press-time application identity/timing against the current frontmost process. It does not read field values. Missing/denied focus metadata fails closed. Security is rechecked during capture, on transcripts, and before planning; entering a secure field cancels without execution. No AXManualAccessibility/AXEnhancedUserInterface writes or permission bypass were added. Native microphone/speech consent remains in the existing input adapter, only after a deliberate physical capture gesture. Launch restoration only starts monitors when already authorized. Tests inject monitors/security/tool ports and do not record audio or inject global keys.

## Compact UI and execution

Agent uses the existing 84×32 HUD with “Preparing agent…”, **“Agent listening”** (audio-reactive teal bars), **“Processing command”**, **“Approval required”**, and **“Result verified”** or explicit failure/review/cancel status. Ordinary dictation retains its waveform and **Transcribing…** states. Agent capture/approval stays visible even if the dictation pill preference is off. Planning success is never labeled execution success. Approval requests select the existing Command Mode page and request the main app window; clicking the approval HUD requests that page again. If the window is closed or macOS declines activation, open Wesley Flow from its menu and choose Command Mode. No new approval design was added.

All plans, including app opening, require the existing explicit Approve action. Notes, Reminders, Calendar, Safari navigation, notifications and media remain the existing typed adapters, permission gates and receipt semantics. Verified app opening means NSWorkspace completed app launch; it does not prove subsequent app readiness. A verified timer receipt means a pending notification request was read back; it does not prove future delivery. Native adapter effects and TCC permission paths still need physical testing.

Two narrow acceptance grammar additions: “Open Safari” maps to the fixed Safari app identity; “Set a timer for two minutes” maps to a timer with an intake-bound absolute due date. Existing “timer Tea in two minutes” and “Create a note …” remain supported. Unsupported natural language fails visibly with no plan, no insertion, no fake completion and no dictation fallback.

No FoundationModels/Ollama/MLX invocation, model download or cloud API was introduced. The deterministic parser works without an on-device model. Existing model availability and 4 GiB admission safeguards are unchanged; no model was loaded to validate this correction. Broader language understanding is deferred.

## Code map

| Path | Correction |
| --- | --- |
| `Sources/Domain/DictationShortcut.swift` (inside WesleyFlowCore) | Right Control identity/label |
| `Sources/SystemOperations/NativeDictationShortcut.swift` | Keycode/flag decode, security/focus metadata checks, symbolic shortcut conflict inventory; separate instances reuse the event-tap/FIFO/wake implementation |
| `App/DictationPreferences.swift` | Backward-compatible Agent enable/key defaults, independently persisted |
| `App/SystemWideDictationCoordinator.swift` | Independent Agent monitor/latches, exclusive shared capture, reliable-final-only planner route, approval/result/cancel state; dictation route cannot select Agent |
| `App/ClickableDictationPill.swift` | Distinct Agent labels, audio response, review/cancel accessibility; original dictation resolver retained |
| `App/GlobalDictationView.swift` | Minimal General binding controls and existing Command Mode review navigation |
| `Sources/Domain/AppOpeningCommand.swift`, `Sources/SystemOperations/NativeAppOpening.swift` | Fixed Safari app opening |
| `Sources/Domain/PersonalAgent.swift` | Bounded spoken timer alias |
| `AppTests/GlobalDictationTests.swift` | Separate-key, no-insertion, duration/failure/collision/repeat and existing-route control tests |
| `WesleyFlow.xcodeproj/project.pbxproj` | 39.0.2 build identity |

## Automated evidence

- Final-source focused app run: **63 expanded cases passed, zero failures** (36 independent Agent voice cases plus the existing 27 agent core cases).
- Full headless Debug test build/run: **1,439 expanded cases passed, zero failures**. Independent `test-without-building` replay: **1,439 passed, zero failures**. The existing CI selection validator confirmed required regression identities and the unchanged four graphical exclusions.
- Final-source Release and `SWIFT_STRICT_CONCURRENCY=complete` builds: **passed**. Swift 6 mode, Xcode 27.0/Swift 6.4/macOS 27 SDK, arm64. No new Swift concurrency diagnostic. Existing AppIntents metadata/test-runner OS service notices do not establish AppIntents integration or live permissions.
- Focused coverage includes Agent→Dictation routing with 5/20/45-second injected clocks, unarmed command-like dictation, no target capture/insertion/history/clipboard mutation by Agent, duplicate finish/stale callback suppression, rapid repeat/release/cancel, startup cancellation, all eleven speech failure values both at startup and during capture, secure gate denial, shortcut/system conflict and rebinding, permission denial and offline grammar examples. Existing full-suite speech range/recovery, focused destination, unavailable-model/resource and durable approval/replay tests remain passing.
- Existing agent core suite under explicit `(deny network*)`: **17 declarations / 27 expanded cases passed**. This includes deterministic parsing and injected executor/permission/recovery tests; no native effect or physical audio is inferred. An additional network-denied Xcode voice-fixture replay attempt failed **before test execution** (exit 74: nested package-manifest sandbox could not be applied). It is retained as infrastructure evidence and is not counted as a passing offline voice test. The normal focused voice fixture run passed as stated above.
- CI helper: **13 tests passed**. Repository/history checks: **passed**, 299 tracked files / 648 history objects, no issue categories. `git diff --check`: passed.
- Earlier full run had one stale six-command inventory assertion after Safari became the seventh supported app; it was corrected before final-source verification. An intermediate compile exposed a duplicated metadata helper in the legacy capture class; that duplicate was removed. Initial restricted-cache build and network-denied voice replay setup failures are retained, not counted as successes.
- Evidence: `Evidence/Milestone39A-R1/Verified/summary.json`, focused/full/replay xcresults and trees, Release/concurrency logs, offline-focused log, baseline patch/hashes, preservation report and keyboard assessment. Reproduction scripts are archived alongside the evidence; their scratch paths identify the actual local runs.


The 5/20/45-second cases advance an injected clock; they are not physical recordings. All native input/TCC, real cross-app delivery, secure field transitions, actual duration/audio behavior, keyboard hardware delivery and native tool outcomes remain user-operated acceptance gates. Four historical graphical checks remain excluded from the headless suite exactly as before; none is claimed passed by this run. Xcode test-host launches are verification only. No running user app was replaced, quit or used to record/inject speech/text.

## User-operated acceptance

1. Save any needed current transcript. Resolve any pending clipboard recovery in the current copy; quit it normally only after its termination guard allows it. Do not force quit or launch two production copies. Open the identified 39.0.2 test bundle below. In General verify the **39A-R1 / speech38L3R3** build marker, unchanged Dictation key, and Agent key **Right Control**. Enable Agent if authorization is needed. Grant Accessibility/Input Monitoring through macOS; microphone/speech access is requested on actual capture. Turn network off for the local acceptance examples. Keep a disposable TextEdit document in the foreground and copy a known sentinel to the clipboard.
2. Hold **Right Control** on the attached keyboard; say **“Open Safari”**; release. Expect Agent listening while held, Processing command after release, then Approval required. No characters may appear in TextEdit and the clipboard sentinel must remain unchanged. Review the Safari app-opening step in Command Mode and press **Approve these actions and run**. Safari should open without Apple-event automation consent; inspect the launch receipt. Do not interpret a plan or “Approval required” as a completed effect.
3. Return to TextEdit. Hold the unchanged **Dictation key** (Fn by default), say “this is a dictation control test”, release. Expect the original waveform → Transcribing… → original verified insertion/manual-copy behavior. No Agent task should be created. Repeat Agent → Dictation → Agent back-to-back in TextEdit and another supported editor, then reverse the order. Check that each release belongs to its own capture and the clipboard is preserved through the existing dictation restoration rules. Never submit a ChatGPT/Codex conversation for this check; Terminal remains manual-copy only.
4. Hold Agent; say **“Set a timer for two minutes”**; release. Review the exact due time and approve. Intentionally allow/deny notification permission in separate tests; inspect the scheduled notification receipt and verify actual delivery with Focus/notification settings understood. A delivery failure must not be represented as proof of a fired alarm. Then test **“Create a note Wesley Flow R1 disposable shopping test”**. Confirm nothing exists before Approve, allow Notes automation only for this disposable action, inspect actual note body and receipt. Repeat a denied permission case: no later step should run and no automatic retry/replay may occur.
5. Separately hold Agent for **5, 20 and 45 seconds** while speaking a supported single request naturally, then release. Confirm audio-reactive bars, no stop before release, no competing microphone session and exactly one awaiting-approval task. Reject the disposable plans rather than duplicating effects. Test Escape while held, release during startup, a rapid re-press, cancellation followed by release/re-press, simultaneous Dictation/Agent modifiers, sleep/wake, microphone/speech denial and disabled/missing resources. A partial/failing recognition must never run or type text. Unknown requests such as “send a message” must visibly fail and preserve the clipboard.
6. Test secure fields and changing foreground apps: a secure/password field must not record/plan; moving into one during capture must cancel. With a normal editor foreground, switching to another nonsecure app may continue Agent capture (there is no insertion target); no transcript may be inserted into either app. At initial press, delayed or changed activation identity must fail closed. Ordinary dictation still uses its original bound destination and existing changed-target policy.
7. In General attempt to bind Agent to the enabled Dictation key; confirm rejection. Try Right Option with preview shortcuts enabled; confirm conflict/disabled status, then restore Right Control. Rebind Agent to another unused modifier and check that the old key no longer starts Agent; restore your preferred binding. Revoke Accessibility/Input Monitoring and confirm no hidden capture. Restore permission explicitly. Restart normally: completed tasks cannot replay; unapproved tasks still need fresh approval. Uncertain tasks require external inspection, never blind resubmission.

Record observed pass/fail, keyboard/app, duration, build marker, permission choice, actual external outcome and receipts. A failure should include the existing privacy-safe speech diagnostics, not an assumption that the planner or microphone succeeded.

## Limitations and preservation

The bounded English grammar, synchronous native AppleScript/TCC wait limitations, no hard overall native-effect deadline, conservative crash uncertainty, app-opening/notification receipt strength and no recurring/communications capabilities from 39A remain. Cancellation cannot undo completed effects. General AI planning, new tool features, model downloads and production release/notarization are outside this correction.

The turn began with the complete 38L3R2/38L3R3 and 39A dirty tree. Baseline patch/hashes are retained in evidence. Of 87 captured app/core/test/report/project files, **76 remain byte-identical**; eleven narrowly extended files are listed in the code map. All speech adapter/callback/range logic, insertion/clipboard services, 38 reports, 39A engine/native tools, composition and provider implementations remain byte-identical. No synced project reference material was edited. Nothing was staged, committed, pushed or merged; branch/HEAD remain unchanged. Earlier failed checks are retained separately from final-source passing evidence. Evidence duplication initially exhausted disk space; only redundant scratch build products and an incomplete duplicate archive created by this task were removed. Final xcresults, summaries/logs, source preservation hashes and the signed test bundle are retained.

## Identified test bundle

Prepared **Release build 39.0.2**, signature verified, **not launched**:

`/Users/akshaywesley/Developer/WesleyFlow/Run/Milestone39A-R1-39.0.2-a954a990/Wesley Flow.app`

Executable SHA-256: `a954a99011934c4647a9635225f926f917a7753c1e37c984031387a4fe8d89dd`.

The standard/running app was not replaced or terminated. This is an ad-hoc local test bundle, not a notarized release. Physical acceptance is pending. Use the normal-quit/clipboard-safe handoff above before opening it.


## 39A-R1.1 — No response to either right-side modifier (39.0.3)

The user physically reported that neither Right Control nor a rebound Right Command produced a response. Read-only inspection found a running **39.0.2 Debug app** at the normal Xcode DerivedData build path; General displayed Agent enabled, Right Command selected, and Accessibility/microphone/speech allowed. This rules out simply assuming an old pre-Agent build or disabled preference. It does not establish native event delivery. The old app exposed no key delivery counters, so the exact physical failing transition cannot be reconstructed retroactively.

Three concrete source defects were corrected:

1. `NativeDictationShortcut` decoded right-modifier flagsChanged by calling `CGEventSource.keyState(.combinedSessionState, ...)` at callback/delivery time. That is a separately sampled mutable state, not the transition on the event being processed. In contrast, the Fn route already decoded the event flags directly. The right modifier path now reads the **immutable event flags**, including the public left/right `NX_DEVICE*KEYMASK` bits from the SDK's `IOKit/hidsystem/IOLLEvent.h`, and preserves those raw bits through the NSEvent fallback. Right-up while its left sibling remains held cannot be misread as another right-down. Left/right combinations and other modifier chords cancel. All native sources use the same decoder. No global key-state polling remains. This removes a real native decoding dependency consistent with the two-key failure; the user's exact physical cause still needs the new counters to confirm.
2. `resumeShortcutIfAuthorized()` reconfigured Agent on every app activation. `configureAgentShortcut()` cancels an active Agent capture and replaces its event generation. Merely returning to Wesley Flow could therefore cancel it. Resume now leaves an already-active Agent monitor/capture intact; explicit disable/rebind/revocation still cancel safely. Regression coverage exercises activation during recording.
3. Window-close lifecycle considered dictation/preview preferences but omitted Agent. Agent alone now keeps the app running after the main window closes.

General now includes **Agent key delivery**: selected-key event/down/up/cancel counts, last source, and whether tap/global/local monitors were created. Counts are native delivery counts, not tasks or unique gestures; redundant sources can produce multiple counts per physical press. They contain no typed text, transcript, audio or clipboard data and are not persisted. The existing refresh updates the row. A received-but-blocked Agent press now retains its reason in the Agent status row: active operation, pending approval, secure input, Accessibility, focus change or unavailable focus security. Startup speech failure likewise retains a readable status. The menu exposes Agent status and enable/disable so a closed main window does not hide availability. These are minimal status controls; no recording, approval, tool or insertion policy was expanded.

### Follow-up verification

- **68 focused expanded cases passed**, zero failures: existing voice/core cases plus native NSEvent flagsChanged fixtures for Right Control/Right Command/Right Option, side-specific release/chord handling, lifecycle/activation and persistent blocked-key reason.
- Full Debug test build/run: **1,444 expanded cases passed**. Independent test-without-building replay: **1,444 passed**. Required regression identities and the four pre-existing graphical exclusions were validated by the existing CI selection checker.
- Release and strict Swift concurrency builds: **passed**. Existing AppIntents metadata notice only; no new Swift concurrency warning accepted. `git diff --check`: passed.
- Native event fixtures are constructed in memory and **never posted**; no global key injection, microphone recording, live model invocation, clipboard test write or native task execution was performed. These fixtures improve coverage of the real event decoder; they do not prove hardware delivery.
- Source backups, prior-work patch, logs, summaries/trees, final focused/full/replay xcresults, source hashes and manifest: `Evidence/Milestone39A-R1.1/`. The seven narrowly extended source/test/project files are listed in the manifest. Existing 38L3R2/range/speech and 39A effects/approval implementations remain preserved. No Git staging/commit/push/merge or replacement/termination of the current app occurred.

### Physical retest and troubleshooting

Prepared, signature verified, **not launched**:

`/Users/akshaywesley/Developer/WesleyFlow/Run/Milestone39A-R1.1-39.0.3-d8d63c92/Wesley Flow.app`

Executable SHA-256: `d8d63c92ff4ff09992bb189ad9ff22384de742692912a0f509de6fa2263c68cf`. General's speech marker begins **39A-R1.1**, build **39.0.3**. Keep the user's selected Agent key (Right Command at inspection); do not change dictation.

1. Resolve any pending clipboard recovery and quit the old copy normally using its menu. Open the exact 39.0.3 app above, with only one production copy running. A rebuilt 39.0.2 app from Xcode is still the old implementation.
2. Open General. Hold the selected Agent key, say “Open Safari”, then release. Expect Agent listening while held, Processing command, then approval in Command Mode. Nothing may be typed or pasted; approve only the displayed app-opening action if desired. Physical success remains **pending** until this is observed.
3. If no HUD appears, read **Agent key delivery** and the Agent status sentence. If selectedEvents/down/up stay zero, native key delivery has not reached the app; report the tap/global/local flags and verify the key/OS Accessibility/Input Monitoring assignment. If counts increase, the persistent status identifies the admission/speech/pending-plan condition. If it says another operation owns audio, release both keys and finish/cancel that operation before pressing again. If it says another app copy is running, quit the other copy normally. Do not force quit a copy holding clipboard recovery.
4. With General visible and a normal, nonsecure window, switching away/back must not reset the monitor or cancel Agent recording. Test with dictation disabled and Agent enabled: closing/reopening the window must leave Agent available. Restore the user's original dictation setting afterward. Repeat the existing Fn dictation control and clipboard check.

The app cannot guarantee detection of another application's custom modifier interception. The new counters distinguish that delivery question from planner/executor behavior. Do not mark 39.0.3 physically successful solely from the passing fixtures.
