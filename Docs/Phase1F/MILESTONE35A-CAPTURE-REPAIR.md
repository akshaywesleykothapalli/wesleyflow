# Milestone 35A — Focused capture repair

27 October 2026. Code/fallback repair prepared; actual ChatGPT composer capture and physical acceptance remain UNVERIFIED until user test. No commit, push or merge.

## Observed failure and identity evidence

The user reported a ChatGPT no-selection draft opened a Close-only preview with “No permitted input. Enter text or explicitly select a saved dictation in Smart Formatting, then try the shortcut again.” That exact message and Close-only layout do not exist in the current Milestone35 panel source: it already contains a TextEditor, Edit input, Generate preview and Close. This strongly indicates a different/older build or configuration, but the exact executable used during that past attempt cannot be reconstructed from this observation alone.

At the initial process inspection **no Wesley Flow executable was running**, so there was no live binary path, in-memory setting or app-owned Accessibility authorization to verify. Saved allowlisted settings: Smart Polish ON, Prompt Engineering ON, Preview shortcuts ON, focused-text preference absent. The absent preference decodes to **OFF**. This is persisted state, not proof of the setting at every earlier keypress. No settings were changed on the user's behalf. `Evidence/Milestone35A/initial-identity.json` preserves only this metadata and prior build hashes. All historical version labels are0.1.0/build1; the new panel title explicitly includes **35A** to identify the intended test UI.

The stale-build explanation is therefore suspected, not a claimed verified running-path root cause. Two additional current-source defects were confirmed by inspection and fixed below. Neither proves what ChatGPT exposed in the user's earlier attempt.

## Confirmed source defects and changes

1. **Panel requested before capture.** The previous coordinator published previewPresented before scheduling native capture. Even a nonactivating panel should not be allowed to race the focused-element snapshot. Now the original PID/launch/activation epoch and focused element are read/revalidated by the resolver before the coordinator requests panel presentation. Repeated gestures during capture do not prematurely show it or change source/kind. Cancellation and invalidated tickets cannot publish late output.
2. **Range-list failure prevented bounded AXValue fallback.** A failed AXUIElementCopyParameterizedAttributeNames returned immediately, including when the API was simply unsupported. Now supported absence outcomes allow the existing bounded short-field fallback. The actual shared read-routing function is fixture tested. AXValue is permitted only for a known short unselected editable field (<=1,024 UTF-16 units); partial selection uses only its bounded selected-text reader. Long fields never fall back to whole-field AXValue. Stale/cannotComplete/failure errors abort rather than broadening access. Advertised range success with invalid data is not silently broadened.
3. **Generic outcome discarded the reason.** Added typed statuses and capture-stage metadata: captured, disabled, permissionRequired, secure, unsupported, empty, sizeLimit, sourceChanged, cancelled, timedOut and busy. Exact user-facing messages distinguish disabled opt-in, Accessibility, empty editor, unreadable editor, size limits and source changes. These are capture outcomes, never mislabeled as model-memory errors.
4. **Manual fallback must always be actionable and explicit.** Reused the existing multiline editor, Edit input, Generate preview and Close. Added a collapsed Capture details disclosure containing only outcome/stage enums. No clipboard, text, prompts, transcript, conversation, password or application content is logged. Only the latest bounded metadata string is held in memory. Every shortcut path, including a missing resolver/origin fallback, now waits for an explicit Generate action. Two existing lifecycle tests now invoke Generate explicitly while retaining their cancellation/secure-input/late-output assertions. Ordinary in-app preview buttons retain their previous explicit-button behavior.

Panel opening remains nonactivating. Clicking Edit input explicitly permits panel keyboard focus; no source-app activation, selection modification or text replacement. Default opt-ins, stored input/history controls, dictation, clipboard leases, Carbon registration and native provider are preserved. The existing4GiB floor remains unchanged. No live AI test was run.

## Native source classification and ChatGPT investigation

The resolver reads only the original application's focused editable AX element, never window text, descendants or chat history. It validates standard text roles, known nonsecure subrole, enabled/editable capabilities, character count, range, owner, focus/launch/activation identity, deadline and a bounded reread. Compatible custom AXTextArea fields with explicit editable metadata can be accepted without claiming all custom controls support these attributes. Arbitrary groups/web areas remain rejected: they are not proof of a composer. No application-name special case was added to make text capture appear successful.

A separate metadata-only diagnostic was attempted once. It requires ChatGPT already foreground and existing helper authorization, reads only a focused-element attribute-name allowlist, never text, and does not activate apps or prompt for permission. Actual result: **NOT_INSPECTED — ChatGPT was not the foreground application; no other application inspected.** Thus no actual ChatGPT composer hierarchy or text capability is claimed. Evidence: `Evidence/Milestone35A/composer-metadata.json`. Runtime Wesley Flow authorization remains UNVERIFIED; an external helper's permission would not establish the app's permission anyway. Native app diagnostics on the user's next shortcut provide the actual failure stage without text logging.

Missing role/subrole/count/range or unproven editability still yields manual input. Secure input, marked composition, non-ASCII input-method uncertainty, read-only fields and Terminal screen capture remain excluded. Existing IME/atomic-snapshot limitations from Milestone35 remain. No AXManualAccessibility/AXEnhancedUserInterface writes, keyboard selection/copy simulation, clipboard scraping, message submission or whole-document fallback was introduced.

## Physical handoff and acceptance matrix

User agreed to test the verified build. No user-observed result for35A is supplied yet. Exact test bundle: `DerivedData/Milestone35A/Build/Products/Debug/Wesley Flow.app`. Confirm the preview title ends in **35A**. Avoid multiple instances; if an older app is running, quit normally only while idle and stop on any dictation/clipboard recovery warning. No running app was force-quit or replaced during this milestone.

Enable both AI previews and Preview shortcuts, then **Use focused text when nothing is selected** in Smart Formatting. Grant Accessibility only through the app's existing native onboarding if needed. Type a harmless draft without selecting it, press/release Option+1 then Option+2. Inspect source label/input and exact explanation/Capture details. Do not click Generate for capture-only testing. Also test selected text, a complete short paragraph inside a long document, and empty/unsupported input. Use Edit input to type/paste harmless text into fallback; generation remains explicit. Never submit a prompt. Check clipboard marker privately in scratch space; source text and selection must remain unchanged. Restore previous options afterward.

| App | Draft without selection | Paragraph | Manual fallback | Clipboard/source unchanged |
|---|---|---|---|---|
| ChatGPT macOS | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| TextEdit | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| Codex Desktop | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| VS Code | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |

Do not infer physical success from registration, fixture cases or compilation. If the editor remains unsupported, report the precise explanation and sanitized stage; do not enable accessibility trees or guess internal roles to bypass it.

## Verification

Focused regressions cover compatible custom editable metadata, actual bounded AXValue routing, selected-text precedence, missing/unsupported range APIs, stale failures, empty/denied/changed/oversize outcomes, manual input with explicit generation, no target capture/insertion/submission and unchanged synthetic clipboard. A controlled continuation test asserts capture finishes before panel presentation, including repeated gestures. Existing preview, cancellation, sleep/wake and dictation regressions remain. Native AX support is represented by fixtures/source checks, not a fabricated physical ChatGPT result.

All exact commands, exits, timestamps, logs and result bundles are ignored local evidence under `Evidence/Milestone35A/Verified/`. Results are appended below after completed runs.

| Final check | Actual result | Exit |
|---|---|---|
| focused | 65 expanded cases / 35 declarations, zero failures/skips | 0 |
| full | 1074 expanded cases / 502 declarations, zero failures/skips | 0 |
| replay | 1074 expanded cases / 502 declarations, zero failures/skips | 0 |
| debug | PASSED | 0 |
| release | PASSED | 0 |
| concurrency | PASSED | 0 |

The prior1,055-case baseline is retained;19 new expanded cases yield1,074. Source tests are explicitly included in the existing WorkspaceTests Xcode target. Initial focused run passed; final runs above include the shared bounded-reader regression and exact status refinements. No failed test was bypassed or disabled in35A. The historical intermittent Phase1A timeout/storage failure from Milestone35 remains a known separate observation; no TaskExecution logic or Phase1A tests changed here.

Commands: explicit DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer; xcodebuild project WesleyFlow.xcodeproj, scheme WesleyFlow, platform macOS/arm64, two jobs, disabled automatic package resolution/updates, DerivedData/Milestone35A. Debug tests use parallel testing NO with distinct focused/full/replay result bundles; builds use Debug/Release, with SWIFT_STRICT_CONCURRENCY=complete for concurrency. Exact argv/times/exits are in per-action JSON records. Counts were extracted from xcresulttool summaries. Replay is a separate invocation/result bundle, not independent physical acceptance. Existing linkd/AppIntents diagnostics did not prevent passing gates.

## Verified build handoff

After tests, a second process check again found no active Wesley Flow instance. Requested opening only the exact Milestone35A Debug bundle with `/usr/bin/open` (exit0); no older process was terminated or replaced. This is an authorized preparation launch, not a physical shortcut/capture test. Its debug-library SHA256 is `a798341dc12d92e2151c3d942e59f2aa629567ccf1ee97b9f73bca99e50e9687`. Confirm the35A preview title during testing. App-owned current Accessibility authorization and the focused opt-in must still be checked by the user; no runtime permission success is inferred from CLI build/launch.

## Final state and limitations

Selection-free capture in ChatGPT is **UNVERIFIED**, not claimed fixed by fixtures alone. Precise underlying composer attributes were not inspected because ChatGPT was not foreground; there was no fallback inspection of Codex or another app. The actionable manual-input fallback and new outcome handling are implemented and regression-tested. If compatible AX text remains unavailable, manual input is the supported outcome; no hidden hierarchy activation is enabled.

All existing Milestone34/35 uncommitted work and reports preserved. Cumulative tracked changes remain AppComposition, DictationPreferences, GlobalDictationView, SystemWideDictationCoordinator, WesleyFlowApp, GlobalDictationTests and Xcode test membership; new resolver/policy tests remain untracked together with the prior reports and this35A report. No new dependencies, cloud providers, model downloads, training, clipboard/source writes or automatic submission. NativePreviewShortcuts, NativeTextInsertion, speech capture, provider/memory-floor code and Domain remain unchanged.

Branch feature/milestone-31-integration; HEAD23caeca630b803fddc2cd007a5159dc9839b71cf; mainb90976c305cb0eb5a32a1658cbe0408f3d8fe2b8. No staging, commit, push, merge, main modification or PR#1 change. Published CI applies only to the earlier committed checkpoint. Final git diff whitespace check and basic new-source/report secret-pattern scan passed; neither proves exhaustive secret detection.
