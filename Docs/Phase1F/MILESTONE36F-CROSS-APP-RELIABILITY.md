# Milestone 36F — Cross-app dictation reliability and capability diagnostics

28 October 2026. **Implementation and automated verification PASSED. Physical ChatGPT restoration and36F cross-app acceptance remain UNVERIFIED.** The exact first failing native stage in the user's ChatGPT attempt and the actual WhatsApp replacement limitation remain unknown. The user chose to continue without36E physical diagnostic metadata and will test the verified36F build afterward.

## User observations and cause limits

The user confirms visible dictation delivery into WhatsApp, no current delivery into ChatGPT macOS, and WhatsApp AI shortcuts reporting either Insertion uncertain or Editor unsupported. Earlier ChatGPT insertion worked. No physical in-place AI replacement is verified. These observations are recorded independently; they do not prove a shared cause or verified readback/range capability.

Installed identity metadata was inspected before choosing a repair:

| Fixed bundle path name | Observed bundle identifier | Version |
|---|---|---|
| ChatGPT.app | com.openai.codex | 26.1023.50603 |
| WhatsApp.app | net.whatsapp.WhatsApp | 26.38.74 |
| Visual Studio Code.app | com.microsoft.VSCode | 1.140.0 |
| TextEdit.app | com.apple.TextEdit | 1.21 |

The installed ChatGPT.app advertises **com.openai.codex**. The existing direct-edit exclusion already selects ordinary paste for that identifier. A direct AX write therefore cannot explain failure of ordinary dictation through that existing route. This metadata does not establish which binary/surface received a historical gesture. A separate /Applications/Codex.app was not found in this fixed-path inventory; that is not a claim that no other Codex installation exists. No new application-name routing rule was added.

A read-only capability-name probe requested no permission, activated no app and read no text. It returned helperAXTrusted=false / HelperNotAuthorized_NoEditorInspected. This is the helper's permission, **not** proof that Wesley Flow lacks access or that WhatsApp/ChatGPT lacks an attribute. Actual composer AX capabilities remain unmeasured by that helper. Evidence: Evidence/Milestone36F/capability-probe.json.

## Confirmed defects and narrow repairs

**Owned-container focus resolution.** NativeFocusedElementResolver previously returned the application-provided AX element as soon as its process matched. If that element was a container, the later role guard rejected it without trying the existing system-focused or bounded focused-descendant fallback, even if an owned editor was available. New deterministic container fixtures reproduce this behavior and verify resolution to an actual supported editor. Resolution now accepts a candidate only after its role is appropriate. Foreign ownership and secure controls stop resolution immediately; they never trigger fallback into another target. Window fallback still requires actual focused-editor metadata, maximum64 nodes/depth8 and the existing250ms deadline. It reads no conversation text while searching and enables no AX tree attributes. Original window/element identity is still bound and revalidated before effects.

This is a confirmed compatibility defect and a plausible capture failure mechanism, **not an established diagnosis of the user's actual ChatGPT attempt**. No physical native trace was supplied. If the composer exposes no safely identifiable/readable field under existing consent, the repaired resolver still rejects it. No blind app-only paste or capture-security relaxation was introduced.

**Stale diagnostic reuse.** When a subsequent capture failed or speech finished without calling the broker, the old summary could append broker events from the previous app/session. A previous verified WhatsApp operation could therefore appear inside the next unsuccessful capture's diagnostic timeline. The broker now tags diagnostic metadata with its session; the coordinator includes it only for its current matching operation and snapshots only current capture events. Begin clears old diagnostic state. A new regression performs verified paste, then failed capture, and proves the second report contains no previous PASTE_DISPATCHED or INSERTION_VERIFIED event. This repair changes diagnostics, not delivery authority.

**Delivery vs replacement classification.** The native adapter now records the captured field's advertised selected-text and selection-range writability as available/unavailable/unknown, separate from delivery. These are capability snapshots, never replacement authority. Missing exact-range setters or an existing policy exclusion does not prevent an otherwise validated ordinary direct insertion/paste. After actual readback verifies, the coordinator may still withhold AI authority because precise replacement is unsupported. Conversely, a visible but unverified paste never creates an anchor. Known unsupported replacement is reported as such for the same original process instead of merely reporting a missing receipt; clipboard recovery remains pending and untouched if required.

Composition/readback uncertainty is not automatically called unsupported replacement. Unknown composition now has an Editor state unknown label. Exact text/context mismatch has SOURCE_TEXT_CHANGED; different target has INSERTION_TARGET_CHANGED. Disabled features, configuration conflict, pending clipboard recovery, rejected input and cancelled generation have their own current-stage codes, so an old memory failure is not reused for a new rejection.

Pre-insertion native text comparison now uses the same exact UTF-16 policy as completion/range verification instead of Swift canonical-equivalent string equality. Canonical differences are not silently accepted as unchanged context. No normalization or permissive range search was added.

## Ordinary ChatGPT delivery and focus audit

Final36F preserves the existing ordinary direct/paste route selection and the com.openai.codex exclusion. It adds no second write, paste retry, new delay or app activation. A failed or uncertain direct update is not followed by a paste. The existing1500ms/32-observation/50ms bounded read-only verification window is unchanged.

Reviewed sequence: global gesture → capture destination → publish preparing/HUD state → existing Apple microphone/transcription → deterministic formatting → validate original app/launch/window/element/text/caret → chosen direct or PID-bound paste → exact readback → receipt/history → optional strict anchor admission → same coordinator's Option+1/2 route. The same formatted text is used for insertion and verification. Speech, meter and shortcut implementation were not edited.

Capture occurs synchronously before preparing/recording or HUD presentation. The pill remains a nonactivating panel whose canBecomeKey and canBecomeMain are false. No unexpected WhatsApp activation or new NSApplication activation call was found in this route. Native paste uses the original process and original bound editor validation; focus switching or changed/stale elements rejects delivery. These are source/fixture findings, not proof of real-app focus behavior. No arbitrary timing workaround was introduced.

## WhatsApp: four independent questions

| Question | Current evidence |
|---|---|
| A. Did dictated text appear? | YES, user-reported before36F;36F not yet physically tested |
| B. Did programmatic readback verify it? | UNKNOWN; user-reported uncertainty is not verification |
| C. Is its exact original insertion range known? | UNKNOWN for the real composer |
| D. Is safe precise replacement supported? | UNKNOWN; prior unsupported message lacked enough context |

WhatsApp's observed bundle is net.whatsapp.WhatsApp; no hardcoded WhatsApp insertion exception was added. The new adapter records role/subrole availability, actual AX readback/error categories, selected-range validity and writable API flags during explicit user dictation. The independent helper inspected no real composer. No claim is made that WhatsApp lacks a particular AX API.

An unavailable precise replacement capability can coexist with verified ordinary delivery. Available means APIs were advertised at capture, not that they work or that replacement is authorized. Full safe anchor construction additionally requires unchanged exact text/context, caret, original identity, subrole/composition and live writable ranges. A missing composition state remains a safe rejection. Capability changes require a fresh validated context; there is no app-wide support promise.

## General diagnostics and accurate categories

The existing development-only Text verification diagnostics now splits:

- DICTATION_DELIVERY: no effect dispatched, dispatched/unverified, or actually verified bound readback.
- INSERTION_VERIFICATION: verified, unavailable readback, missing/invalid range, changed target, or unverified result.
- REPLACEMENT_CAPABILITY: unknown, API advertised, or safe replacement unsupported.
- AI_GENERATION: not requested, requested, completed, memory blocked, failed or cancelled.
- REPLACEMENT_RESULT: not attempted, verified, or uncertain attempted replacement.

Required codes are implemented: DICTATION_NOT_DELIVERED, DICTATION_INSERTED_UNVERIFIED, ACCESSIBILITY_READBACK_UNAVAILABLE, INSERTION_RANGE_UNAVAILABLE, INSERTION_TARGET_CHANGED, EDITOR_REPLACEMENT_UNSUPPORTED, VERIFIED_INSERTION_AVAILABLE, SOURCE_TEXT_CHANGED, MODEL_MEMORY_BLOCKED, GENERATION_FAILED and REPLACEMENT_VERIFIED. DICTATION_INSERTED_UNVERIFIED means **an attempted dispatch with unverified delivery**, not proof that text visibly appeared. Additional exact conditions retain NO_INSERTION_RECEIPT, receipt expiry/consumption, clipboard/configuration/feature rejection and GENERATION_CANCELLED.

Build36F, lifecycle/stage enums, random content-independent operation identifier, target-match state, native AX response codes, focus/ownership rejection, dispatch/readback/eligibility outcomes and measured capture/insertion/readback milliseconds are available. Unknown checks remain unknown/notChecked. Millisecond arithmetic handles overflow without granting success. Role/capability data and bounded current-session capture/broker samples supplement the native exact-range diagnostic stages.

Only enums, booleans, numeric errors, lengths/ranges/timing and a random nonce are recorded. No transcript, conversation, full AX text value, clipboard content, private title, prompt, credential or recoverable content hash is logged. Source/binary SHA256s in evidence identify artifacts, not user content. No diagnostic metadata grants permission or edit authority; AX handles remain RAM-only.

## Safety and preserved behavior

No replacement is allowed merely because history contains a dictation or an API was advertised. Unverified/failed/cancelled delivery still has no eligible anchor. Verified receipts require the same session/PID/formatted text, no pending lease and unchanged strict native checks. One authoritative coordinator retains one120-second anchor; normal HUD teardown retains it, expiry/conflict/consumption invalidates it, and stale generation cannot modify text.

Windowless Option+1/2 remains unchanged; rejection never opens a preview, sheet or manual-input window. No blind selection, Command+A, deletion, Return/Enter or message submission. No relaxed source identity, range, secure-input or IME checks. Terminal remains manual-copy; direct edits for com.openai.codex remain excluded by the existing policy. Since this installed ChatGPT-branded bundle uses that ID, its ordinary paste and its unavailable precise direct-edit path must not be conflated. No exclusion was bypassed to manufacture AI success.

Clipboard acquisition, revision ownership, restore-only-after-verification, retained recovery backup and newer-clipboard protection remain unchanged. Known unsupported replacement can reject before a clipboard guard because it performs no effect; it neither clears recovery nor permits generation. The native readonly readback and lease machinery from36E remains intact.

Byte comparisons to the captured36F baseline prove ClickableDictationPill, AppleDictationInput, NativeSpeechCallbacks, AudioLevelMailbox and Package.swift unchanged (AcceptanceFinal/preservation.json). No waveform design, meter, hold-to-talk behavior, typing icon, model prompt/tone, model integration, preference default, dependency graph or4GiB floor change. No cloud fallback, downloads, training, agent execution or AI-generated file effects.

Changed for36F: App/SystemWideDictationCoordinator.swift (separate states/current-session metadata), App/WesleyFlowApp.swift (marker), AppTests/GlobalDictationTests.swift, Domain/GlobalDictation.swift (capability and correlation metadata), SystemOperations/NativeTextInsertion.swift (resolver/capture diagnostics/exact precheck), SystemOperations/TextInsertionService.swift (diagnostic session/timing only), and this report. Existing work was preserved.

## Actual automated verification

Xcode27 / Swift6.4 / SDK27 at /Applications/Xcode-beta.app/Contents/Developer, deployment macOS26 arm64. Actual tests ran on MacBook Air arm64 / macOS27.2 (26B5112a); macOS26 runtime acceptance is not established.

| Gate | Actual result | Exit |
|---|---|---|
| focused | 368 expanded cases / 192 declarations; 0 failures, 0 skips | 0 |
| full | 1237 expanded cases / 563 declarations; 0 failures, 0 skips | 0 |
| replay | 1237 expanded cases / 563 declarations; 0 failures, 0 skips | 0 |
| Debug build | passed | 0 |
| Release build | passed | 0 |
| Strict concurrency Release | SWIFT_STRICT_CONCURRENCY=complete passed | 0 |
| Debug bundle signature | codesign --verify --strict passed | 0 |
| Repository/license/artifact/basic secret checks | passed | 0 |
| Whitespace and unchanged index | passed | 0 |

The1215-case /551-declaration baseline is retained. Added22 cases /12 declarations cover owned containers and safe fallbacks, foreign/secure candidate rejection, ordinary direct/paste delivery independent of precise replacement, capture before recording/HUD state, stale focus rejection, visible paste with unavailable readback, verified paste without unsupported replacement authority, both windowless shortcuts, missing receipts, genuine source mismatch classification, memory vs generation failures, cancellation/late output, failed capture after prior successful paste, and disabled features after earlier memory rejection. Existing repeated/cancelled dictation, history, clipboard lease/newer-copy, no duplicate/no submission, waveform and recovery tests remain enabled. Fixtures do not constitute real-app acceptance.

Initial Acceptance/focused exited65 because newly added assertions placed actor awaits inside Boolean autoclosures. The awaits were separated while preserving every assertion. Production compiled; this was test syntax, not a demonstrated production actor race. The failure log is retained. FocusedRepair and Final focused runs passed before the final diagnostic correlation/status refinements. AcceptanceFinal covers the exact final source; no tests were removed, weakened or skipped.

Historical recovery-test flakiness remains explicit: lateSuccessIsDiagnosticAndCannotReplaceTimeout had a prior fixture clock/persistence race addressed before36F. No Phase1A recovery source/test was edited here. It passed the final full suite and replay; no intermittent runtime test failure reproduced in36F. Compiler failure above is reported separately. Existing linkd.autoShortcut/AppIntents warnings remain nonblocking and do not prove physical delivery.

Exact commands, timestamps and exits: Evidence/Milestone36F/AcceptanceFinal/{focused,full,replay,debug,release,concurrency}.json and .log, with xcresults/summaries. All builds sequential. Common argv: xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone36F-FinalVerified -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2. Tests add -configuration Debug -parallel-testing-enabled NO -resultBundlePath <unique bundle> test; focused selectors are in JSON. Full/replay exclude nothing. Builds use Debug/Release build; concurrency adds SWIFT_STRICT_CONCURRENCY=complete. Hygiene commands/results and source/binary hashes are alongside. No hosted CI run or remote update was performed.

## Running build and safe handoff

Initial inspection found PID23779 at the default Xcode DerivedData Wesley Flow path, not the isolated test path. Its on-disk debug dylib SHA256 was ae5dc9a2913b2c32ec72d42cf215ce6cf87b224d3813e72c2042e3fe971fa6f5. Initial three-byte marker flags are not authoritative version proof; the file may also have been rebuilt after process launch. No assumption was made that it matched the inspected source or that its clipboard state was idle.

After all final gates, no older instance was running. The exact verified development app was opened normally (open exit0), and a subsequent process check confirmed DerivedData/Milestone36F-FinalVerified/Build/Products/Debug/Wesley Flow.app/Contents/MacOS/Wesley Flow. Evidence: AcceptanceFinal/safe-handoff.json. No process was killed/force-quit, installed bundle replaced or clipboard read. General/Smart Formatting's route identifies36F; the executable/debug-dylib SHA256s identify the final artifact.

## Physical acceptance matrix and next test

The user said “Continue; physical diagnostics unavailable” for the prior36E metadata and “I’ll test after verification finishes” for36F. No36F physical outcome has yet been supplied.

| Test | Physical result |
|---|---|
| A. ChatGPT harmless dictation in intended composer, no send | UNVERIFIED — required to accept restoration |
| B. WhatsApp unsent draft delivery | Prior user observation PASS;36F UNVERIFIED |
| C. WhatsApp readback/exact range/Option+1 and Option+2 | UNVERIFIED |
| D. TextEdit ordinary insertion and possible AI replacement | UNVERIFIED |
| E. Switch focus: no unintended insertion, clipboard preserved | UNVERIFIED |
| Codex Desktop and VS Code live capability/dispatch | UNVERIFIED |

First focus an empty ChatGPT draft, hold/release the actual dictation key and confirm whether text appears without submission. Only afterward inspect General and report delivery/readback/capability codes and concise status, not private content. Repeat WhatsApp with an unsent harmless draft and TextEdit as control. For AI, use a **new** dictation and invoke Option+1/2 before opening General; switching to General first invalidates the native original focus context. Use separate fresh dictations for each shortcut, source-edit rejection and nearby-content preservation. Stop without retrying a model resource rejection. Do not press Enter or send. A focus-switch test must not redirect text to another app.

No global keys, microphone input, real message insertion or private-conversation UI automation was generated by this task. No live model inference was attempted; fixture resource failures are not host resource observations. The unchanged4GiB floor still applies to a human-triggered real generation.

## Remaining blockers, Git and stop

**Actual ChatGPT regression root cause: UNKNOWN. Restoration: UNVERIFIED.** The owned-container resolver failure is repaired and tested, but has not been correlated with a real failed composer capture. WhatsApp's precise unsupported/readback condition is UNKNOWN until the app-owned native diagnostic trace is provided. The independent helper's missing permission is not an app capability finding.

Strict original target/readable-context requirements can still block ordinary insertion when the composer exposes no safely bindable field. No blind fallback or accessibility-tree activation was authorized or added. Advertised setters do not guarantee precise replacement; strict IME/range checks can still reject an editor. External AX mutation is not atomic compare-and-swap; attempted uncertainty is not retried or rolled back. Universal cross-app support and physical in-place success are not claimed.

Branch feature/milestone-31-integration; HEAD23caeca630b803fddc2cd007a5159dc9839b71cf unchanged. No staging, commit, push, rebase, merge, remote query/mutation or PR#1-state change. All previous uncommitted work remains. Stop after36F investigation/repairs/verification; physical final acceptance is pending user results, not passed by fixture tests.

Final working tree, including all pre-existing changes:

```text
 M App/AppComposition.swift
 M App/ClickableDictationPill.swift
 M App/DictationPreferences.swift
 M App/GlobalDictationView.swift
 M App/SystemWideDictationCoordinator.swift
 M App/WesleyFlowApp.swift
 M AppTests/DictationTests.swift
 M AppTests/GlobalDictationTests.swift
 M Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
 M Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift
 M Packages/WesleyFlowCore/Sources/Domain/PromptEngineering.swift
 M Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
 M Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
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
?? Docs/Phase1F/MILESTONE36A-INPLACE-ROUTING.md
?? Docs/Phase1F/MILESTONE36B-WINDOWLESS-AI.md
?? Docs/Phase1F/MILESTONE36C-TEXT-VERIFICATION.md
?? Docs/Phase1F/MILESTONE36D-DICTATION-PROVENANCE.md
?? Docs/Phase1F/MILESTONE36E-INSERTION-VERIFICATION.md
?? Docs/Phase1F/MILESTONE36F-CROSS-APP-RELIABILITY.md
?? Packages/WesleyFlowCore/Sources/Domain/DictationEnhancements.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationVerification.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/DictationSpanVerification.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/FocusedTextResolver.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/AudioLevelMailbox.swift
?? Packages/WesleyFlowCore/Tests/WorkspaceTests/FocusedTextResolverTests.swift
```
