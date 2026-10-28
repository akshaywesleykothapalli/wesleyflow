# Milestone 35 — Context-aware text capture

27 October 2026. Implementation prepared; physical application compatibility remains UNVERIFIED pending the user's agreed manual test. No commit, push or merge.

## Existing source and architectural change

Read AGENTS.md, preview/shortcut composition and lifecycle, permission/insertion contracts, preferences/privacy UI, clipboard boundaries, previous delivery report and tests. Milestone34 edits and prior local reports are preserved. The user reports selected-text shortcut operation works on their current running configuration. The checked-out preview source, however, used only supplied Wesley Flow text or an explicitly chosen saved dictation; no external selected-text acquisition existed there. This milestone adds an explicit read-only resolver without removing those original controls or claiming to have reproduced the user's prior external-selection behavior.

`FocusedTextResolving` and `NativeFocusedTextResolver` live in SystemOperations, which already owns native Accessibility integration. Domain and providers gain no AX types or dependencies. App composition injects the resolver only into production; tests use controlled fixtures. Existing Carbon registration, virtual-key mapping, global delivery, dictation target binding and clipboard broker remain unchanged.

A valid enabled shortcut with its original process identity opens the same preview immediately, then requests bounded capture. Resolution priority: explicit nonempty selection; opted-in short editable draft; opted-in complete current paragraph in a bounded neighborhood; manual input. Existing explicitly supplied/history input remains a manual fallback if capture yields nothing. The resolver is not called by in-app ordinary preview controls or background monitoring. Unknown origin never triggers external text access.

## Privacy setting and retrieval policy

New persisted setting, default OFF: **Use focused text when nothing is selected**. Migration defaults old preferences to false and preserves existing defaults. The Smart Formatting setting explains gesture-scoped short-draft/paragraph reads, Accessibility and unsupported-field fallback. Selection reads require the user's explicit enabled shortcut; unselected content additionally requires this opt-in.

Native resolution:

- Requires existing Accessibility trust; does not prompt, enable access, write AXManualAccessibility/AXEnhancedUserInterface, or enumerate windows/children.
- Binds to the original foreground PID and launch identity. Observes only application-activation metadata to invalidate captures, including away-and-back changes. The worker resolves only that application's focused element and verifies owner, same focused element and selection/count at completion.
- Keeps AX objects worker-local. Synchronous AX messages run in a detached worker, never on MainActor. Only one capture may be active per resolver. Messaging timeout80ms per target; total cooperative deadline700ms checked before calls. An in-flight call can finish after that deadline by its message timeout; this is not a hard OS real-time guarantee. Cancellation cancels the worker and fences late completion with coordinator tickets.
- Checks supported attributes, role/subrole, enabled/editable capabilities, secure-input mode and marked text when exposed before requesting text. Rejects secure/password fields, read-only/disabled controls and Terminal/iTerm screen capture. Non-ASCII-capable input sources conservatively fall back to manual input. AX does not uniformly expose IME marked-state; ASCII-capable composition detection is not universally provable and remains a limitation, not a verified cross-editor guarantee.
- Requires character count and selected range. Selected range is preferred and cannot exceed1,024 UTF-16 units. Unselected whole-draft reads require count<=1,024 UTF-16 units. Longer content is observed only through a1,024-unit window near the caret; only a complete paragraph with both boundaries proven is accepted. A long unbroken paragraph or clipped boundary fails to manual input. No entire long document fallback.
- Uses AXStringForRange where supported. If unavailable, selected text may use AXSelectedText only with a bounded reported selection; a short field may use AXValue only with bounded reported count. An advertised range reader that fails is not silently replaced by a broader value read. Returned range length must match UTF-16 count; accepted final input must fit2,048 UTF-8 bytes. Unicode/CRLF boundaries are tested. A buggy remote AX server can return more data than requested before client validation; AX is not an adversarial memory-containment boundary.
- A bounded reread must agree before accepting text; final focus, range/count, secure/marked status and original app identity must still match. This reduces races but is not an atomic editor snapshot or proof against every same-value mutation/ABA race.

No Command+A/C, keyboard injection, clipboard scraping, source mutation, selection mutation, text logging, automatic persistence, cloud call or model download was added. Messaging timeout configuration affects this AX client, not source text. Capture data is ephemeral preview state and is cleared on dismissal/close, not written to history/preferences.

## Preview and lifecycle

Source labels: Selected text, Focused draft, Current paragraph, Manual input. Text is shown in the existing panel with editable input, Original and the existing result/Reject/Copy/Cancel controls. **Captured input is reviewed first; Generate preview is explicit.** No model is invoked merely to inspect captured text. Editing marks the source Manual input and cancels stale generation. Existing supplied/history preview buttons retain their prior behavior.

The panel still does not activate or take key focus when a shortcut arrives. Because editing requires keyboard focus, **Edit input** is an explicit user action that permits the existing nonactivating panel to become key. It does not activate the source application or rewrite its selection. Physical focus return after deliberate editing must be verified manually; no blanket focus-preservation claim is made for user clicks. Panel cannot become main.

Capture and generation have separate cancellation fences. Repeats during capture or generation cannot replace source/kind. Opt-out, feature disablement, sleep, secure-input notification, dismissal, new dictation and close cancel pending capture appropriately. Existing generation cancellation, settling ownership, eight-second provider deadline, lexical protections and4GiB memory floor remain. No automatic insertion, replacement, Return or submission. Explicit Copy still goes through the existing lease-aware broker.

## Application limitations and manual matrix

No application text was accessed during development verification; only synthetic fixtures were used. No app instance was replaced, terminated or force-quit. Running-process dictation/clipboard safety was not established, so safe handoff is user-operated. Prepared bundle: `DerivedData/Milestone35/Build/Products/Debug/Wesley Flow.app`.

Before opening it, quit the older instance normally only while idle; stop on any clipboard/dictation warning. Enable both preview features, Preview shortcuts and the new focused-text opt-in. Use a harmless draft, e.g. “Please review the sample button. Keep keyboard access unchanged.” Do not select text; invoke Option+1 and Option+2. Inspect the capture without Generate to avoid inference. Then test selected text, caret in a multiline long document, empty input and fallback editing. Confirm clipboard marker privately in scratch space, no automatic typing/submission, correct source labels, cancellation and no stale/duplicate output. Restore prior settings afterward.

| Application | Short draft, no selection | Explicit selection | Long paragraph | Empty/manual input | Focus/clipboard/cancel |
|---|---|---|---|---|---|
| TextEdit | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| ChatGPT macOS | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| Codex Desktop | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| VS Code | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |

The user agreed to test after verification; no results have been supplied. TextEdit needs supported editable metadata/range. ChatGPT/Codex/custom/Electron editors may not expose the focused element, reliable subrole, count, editable capability or range; those fall back to manual input. VS Code cannot cause a whole-file read through the long-document path. Accessibility-tree activation remains disabled by the user's earlier decision. No special-case compatibility success is claimed. Terminal stays manual-copy only.

## Verification evidence

Initial focused compilation failed with exit65 because CFRange has no direct == conformance. Corrected to explicit location/length comparison; evidence preserved. A subsequent focused run passed; final verification after consistency/session refinements is recorded below. No tests removed or weakened. Existing1,028-case Milestone34 baseline preserved. Regression tests cover selection priority, consent, short drafts, paragraph boundaries, oversized/partial/empty text, UTF-16/CRLF, unsafe metadata, preference migration, unsupported/denied/stale manual fallback, feature disablement, controlled cancellation and repeat suppression, and explicit generation without source target capture/copy/insertion. Native permission denial/stale AX behavior is source-reviewed and represented by fixture outcomes; it is not claimed physically reproduced in another app.

### Final executed results

All final runs below are from the same final source and explicitly include the new policy test file in WorkspaceTests. During inspection, the first added test file was found missing from the Xcode target despite existing in the package directory; explicit project membership was added. Earlier1,041-case success did not cover those policy tests and is not the final gate.

| Check | Actual result | Exit |
|---|---|---|
| focused | 46 expanded cases / 28 declarations, 0 failures, 0 skips | 0 |
| full | 1055 expanded cases / 495 declarations, 0 failures, 0 skips | 0 |
| replay | 1055 expanded cases / 495 declarations, 0 failures, 0 skips | 0 |
| debug | PASSED | 0 |
| release | PASSED | 0 |
| concurrency | PASSED | 0 |

Final evidence: ignored `Evidence/Milestone35/Acceptance/`, with full argv, timestamps, exit codes, logs, test bundles and parsed summaries. Core command: `/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone35 -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2`, explicit DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer. Debug tests use parallel testing NO and distinct result bundles. Builds use Debug or Release; concurrency adds SWIFT_STRICT_CONCURRENCY=complete. Counts from xcresulttool summary, not counting source functions. Independent replay means a separate test process/result bundle, not independent human acceptance. Existing1,028 cases plus27 new expanded cases =1,055. No dependencies added; SystemOperations remains the native boundary.

### Preserved failed/intermediate evidence and remaining reliability issue

One broader run (`Evidence/Milestone35/Complete/full.json`, exit65) failed the unchanged Phase1A `RemediationTests/lateSuccessIsDiagnosticAndCannotReplaceTimeout()` assertion: storage failure observed instead of timeout, then60-second limit exceeded. TaskExecution and Phase1A tests have no diff. The fixture advances a shared manual deadline while persistence and cleanup tasks are asynchronous; a timing/synchronization race is a possibility, not an established root cause. No unrelated production or test logic was changed. Both later final full runs executed this exact method successfully. An isolated exact-method check in `Evidence/Milestone35/RecoveryExact/` executed1 case, passed, exit0. This does not fix or erase the observed intermittent failure; investigate separately before relying on unconditional regression stability.

An initial isolated filter without Swift Testing parentheses executed zero cases despite exit0. It was rejected as evidence and corrected to `-only-testing:Phase1ATests/RemediationTests/lateSuccessIsDiagnosticAndCannotReplaceTimeout()`. Earlier CFRange compilation failure and missing-target coverage are also preserved, not relabeled success. An attempted SIGINT to the already-exited test xcodebuild PID returned “no such process”; no signal was delivered and no running product was terminated. Existing AppIntents/linkd diagnostic warnings were present; successful test outcomes are taken from result bundles.

## Remaining issues and Git state

Physical capture, focus after manual editing, IME behavior and custom-editor AX compatibility remain UNVERIFIED. Strict missing metadata/range policy can require manual input in otherwise usable editors; it deliberately does not activate accessibility trees or guess whole-document scope. The unchanged recovery test had an intermittent failure as detailed above. No live AI quality result is claimed in this milestone.

Cumulative tracked changes (including preserved Milestone34 work): AppComposition, DictationPreferences, GlobalDictationView, SystemWideDictationCoordinator, WesleyFlowApp, GlobalDictationTests, and Xcode project test membership. New source/test: SystemOperations/FocusedTextResolver.swift and WorkspaceTests/FocusedTextResolverTests.swift. New report: this file. Prior Milestone32/33 and shortcut-delivery reports remain untracked and preserved. No changes to speech capture, NativeTextInsertion, NativePreviewShortcuts, ModelProviders, Domain, permissions, clipboard broker, or TaskExecution. Git diff whitespace check passed.

Branch feature/milestone-31-integration; HEAD23caeca630b803fddc2cd007a5159dc9839b71cf; local mainb90976c305cb0eb5a32a1658cbe0408f3d8fe2b8. No commit, push, merge or repository visibility change performed. PR#1 was not modified. Published hosted CI results remain for the earlier committed checkpoint, not this uncommitted implementation.

Prepared Debug library SHA256: `a9122752346d781c2102aa1ff18421c6beaf2f0a67750f5c0ec430a2a93e5a39`. Use the exact Milestone35 bundle path; the older running app was left untouched.
