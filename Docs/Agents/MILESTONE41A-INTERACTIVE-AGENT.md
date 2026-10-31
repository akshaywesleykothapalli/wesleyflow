# MILESTONE 41A — Interactive Agent clarification and accurate follow-ups

30 October 2026 (Asia/Kolkata). Build **41.0.1**, marketing version **0.1.0**, arm64. Implemented and verified with automated tests/builds. **Physical verification is pending and explicitly deferred by the user.** The identified bundle has not been launched. No live message, Contacts query, microphone capture or native productive action was performed during this milestone.

## Problem and resulting behavior

The separate Agent key already reaches voice-to-agent planning; the user confirmed Open Safari previously. Milestone 40A added installed-app discovery, normal quitting, browser searches, playback controls and reviewed Messages drafts. Its remaining interaction was largely one request → one plan/error. Missing fields and ambiguous recipients required restating a request; short follow-ups lacked a bounded reference; a draft could not be conveniently corrected. Model output also needed stronger checks against omitted compound actions and language that asks about an action rather than requesting it.

41A adds explicit, short-lived dialogue before the existing typed tools and durable executor. It improves supported commands without command registration or a new model requirement. It does not turn Wesley Flow into an unrestricted assistant or claim perfect natural-language understanding.

| Example | Implemented behavior |
| --- | --- |
| “Open” / “Close” | Asks which installed app. Answer by Agent key, listed choice or typed reply. Close means a normal app quit. |
| Mistyped app name such as “Open Safri” | Offers nearby installed names when available; never silently substitutes or executes the suggestion. Full installed name can also be supplied. |
| “Search YouTube” | Asks for the query. The next reply is literal search data, even when it contains action words. |
| “Create a note” | Asks for its contents; the reply becomes note text through the existing Notes tool. |
| “Text John” | Asks what it should say, then resolves the recipient or asks which address. Nothing sends before exact final review. |
| Ambiguous contact | Shows up to six candidate name/address pairs; “second”, full unique name, a button, or an explicit phone/email can resolve it. Keeps the unsent body. |
| Contacts denied/unavailable or no match | Requests an explicit phone/email instead of discarding the unsent request. Denial does not grant contact access. |
| “Open Safari”, then “Close it” | Refers only to the recently confirmed successful single-app action; otherwise asks which app. Does not guess from the foreground app. |
| “Search Google for guitar lessons”, then “Search that on YouTube” | Reuses only the recent successful single search query. |
| “Please, can you …” / “Would you mind opening Brave for me” | More courtesy and common gerund forms use the deterministic path when recognized; no model is needed for those forms. |
| “Open Brave and WhatsApp” / “Open Brave and then close Safari” | Recognized app-only lists are resolved completely and in order before enqueueing. A model proposal cannot omit or reorder a known requested step. Runtime effects are still sequential, not an atomic transaction. |
| “Change message to …” / “Change recipient to …” while reviewing a single message | Cancels the old pending draft durably and creates a new draft identity. Recipient changes resolve again. Requires fresh exact final review. |
| Typed message edit | Literal body, including punctuation/newlines. Apply or clear it before sending; unapplied edits block Send. |
| “Help” / “What can you do” | Opens existing Command Mode examples. Clears an incomplete question, preserves any durable pending draft and unapplied draft edit. |

## Request path and state boundaries

Existing Agent shortcut → on-device speech capture → key-release final transcript → `SystemWideDictationCoordinator.interactWithAgent` → `PersonalAgentDialogue` for controls, explicit missing fields and bounded references → whole-request quick parser or guarded `ApplePersonalPlanner` → native installed-app/contact resolution → durable `PersonalAgentEngine` enqueue → existing routine execution or final message review → native receipt.

Question replies can also enter through `submitAgentReply`. Buttons carry the immutable question ID so an old option cannot answer a replacement question. Questions expire after 120 seconds; backwards-clock anomalies invalidate them. Unmatched app replies are bounded to three attempts. A stale reply is rejected instead of promoted into a fresh effect. The context is ephemeral, not opt-in persistent memory: only a completed single app/search action seeds a reference, it expires after 120 seconds, and unrelated/failed requests clear it. Multi-action plans do not seed “it”. There is no generic replay command and no automatic continuation after restart.

The current compact HUD keeps “Reply needed” visible and clicking it opens the existing reply/review interface. It must not start dictation. Agent listening/understanding/execution and approval remain distinct. Existing Command Mode adds only question/options/reply, Help, a Latest request disclosure (“Your words” and “Understood”), and message correction controls. No general UI redesign.

Dictation still uses its separate existing shortcut, transcription, range/focus checks, waveform, Transcribing state and insertion path. Agent replies never enter insertion or submit a ChatGPT/Codex conversation. `NativeDictationShortcut`, speech implementations, insertion implementation and preferences are unchanged against the recorded working R1/R1.1 hashes. Coordinator/HUD changes are covered by retained hotkey, speech and no-insertion regression cases; physical isolation remains to be checked later.

## Accuracy and execution safeguards

- App suggestions require an explicit choice and exact installed identity resolution; no fuzzy auto-execution. Bounded app catalog limitations from 40A remain.
- Query, note and message replies are data. Courtesy words and action-like text inside them retain their punctuation/content rather than being interpreted as another command. Exact standalone cancellation/help words remain dialogue controls.
- Deterministically understood compound requests have their complete action signatures/order checked against generated plans. Irrelevant model fields cannot mask intent. Advice/tentative examples such as “How do I close Safari?”, “Should I open Brave?” and “Maybe quit Safari” are rejected as tool requests. These checks reduce known misclassification patterns; they are not a proof of semantic correctness for all language.
- Message recipient choices keep the original literal body and use a fresh plan/changed-step identity. A selected explicit address is not overwritten by another contact lookup. Cancellation fences check before Contacts access and discard late resolver results after cancellation.
- “Yes” or “send it” does not approve a message. The production Send button passes the exact immutable displayed plan to `approveAgentPlan(expectedPlan:)`; an old displayed draft cannot approve a replacement. Unapplied message edits are blocked in both UI and coordinator. Voice corrections also never auto-send.
- A failed durable draft cancellation restores the prior in-memory engine state and retains review rather than falsely claiming withdrawal. Native effects still cannot be undone by cancellation.
- Existing routine/message separation, journal locking, write-ahead state, conservative recovery, receipt handling and no automatic replay remain. Messages dispatch still does **not** prove delivery; inspect the actual conversation before any retry. WhatsApp sending remains unsupported; opening the installed WhatsApp app is supported.

No FoundationModels/provider/admission code changed. The 4 GiB host reserve, shared inference lease, no-cloud/no-download policy and model-unavailable transparent failure remain. **No native model probe or generation was attempted in 41A.** The prior 40A synthetic probe was resourceBlocked before generation; that remains the available native-generation evidence. Supported quick/dialogue requests work without model availability; arbitrary language still depends on an admitted available on-device model and the closed tool set. Browser/streaming/messaging services can require their own connectivity; offline planning does not make those services offline.

Existing tool limitations remain: app closing requests normal quit with save dialogs respected, not window closing or force quit; browser search verifies handoff, not result reading; music controls use supported native apps/queues; Notes/Reminders/Calendar and timers retain their existing native permissions and verification. Native AppleScript/TCC calls may wait on dialogs and are not a general bounded background automation system.

## Source changes

- New `Packages/WesleyFlowCore/Sources/Domain/PersonalAgentDialogue.swift`: explicit dialogue values, expiry, choices, recent reference, draft-edit parsing and readable action summaries.
- `Domain/PersonalConversation.swift`: courtesy/gerund handling, literal payload preservation, app-only compounds and generated-plan grounding.
- `SystemOperations/NativePersonalApps.swift`: recoverable recipient choices, explicit-address preservation and contact cancellation checks.
- `SystemOperations/PersonalAgentEngine.swift`: transactional cancellation of pending approval on persistence failure.
- `App/SystemWideDictationCoordinator.swift`: routes voice/text/replies, question expiry, review/edit identity and exact displayed-plan approval fences.
- `App/GlobalDictationView.swift`, `App/ClickableDictationPill.swift`: existing Command Mode reply/review wiring and HUD routing.
- `AppTests/GlobalDictationTests.swift`: consumed domain and integration regressions; `WesleyFlow.xcodeproj/project.pbxproj`: build identity 41.0.1.

No changes to App composition, on-device provider, admission threshold, shortcut binding defaults or speech/insertion implementation in this milestone. Existing uncommitted 38/39/40 work is preserved. `Evidence/Milestone41A/Before`, initial hashes and prior-work patch preserve the starting state; `source-hashes.json` identifies final source, and `preserved-voice-model-insertion.json` verifies 13 unchanged paths against prior evidence. `PersonalAgentEngine`'s before copy was also hash-verified against 40A.

## Automated verification

| Check on final source | Result |
| --- | --- |
| Focused Agent/core/hotkey/dialogue suites | **115 expanded cases passed**, zero failures |
| Full headless Debug build and tests | **1,491 expanded cases passed**, zero failures |
| Independent test-without-building replay | **1,491 passed**, zero failures |
| Release build | Passed |
| Swift 6 complete strict-concurrency build | Passed |
| CI helper unit tests | **13 passed** |
| Repository tracked-file/reachable-history scan | Passed; 299 tracked files / 648 history objects |
| Whitespace and staged changes | `git diff --check` passed; nothing staged |
| Packaged Release signature | `codesign --verify --deep --strict` passed |

Xcode 27 / Swift 6.4, macOS 27 SDK, arm64, deployment target macOS 26. Existing CI required-test selection was validated and the unchanged four graphical exclusions remain excluded; no graphical test success is claimed. Active architecture only, indexing disabled, dwarf information and one compiler job were used to limit disk pressure. Build logs retain the existing AppIntents/test-runner OS notices; no new Swift concurrency warning was accepted.

Eighteen expanded cases were added above the 40A baseline, covering field filling/literal payloads, suggestion choice, context expiry/backwards clock, compounds/omission/order, advice rejection, message identity/edit/newline handling, stale displayed approval, unapplied-edit blocking, Help, HUD click routing, stale question IDs, persistence failure rollback and late recipient output after cancellation. Existing focused coverage includes hotkey repetition/release/cancel, speech error/range handling, model denial, no clipboard/insertion and no duplicate execution. All native effects/model answers in these tests are fixtures; they do not establish physical macOS/TCC or model-generation success.

Early attempts failed before tests due to disk pressure and compile/test-macro errors. These logs/results are retained with prefixes and are not counted as passing. Final results are the unprefixed summaries, xcresults and build logs. Only this task's disposable scratch compilation products may be removed after packaging; no user data/model cache/application was purged or terminated.

Evidence is under `Evidence/Milestone41A/`: manifest, source hashes, preserved-path checks, baseline/source backups, verifier, logs, final summaries/test trees/xcresults, earlier diagnostic runs and signature verification. No staging, commit, push or merge. HEAD remains `24db5c924f8598c6971c771e41f1678262e54379`.

## Identified build and later user-operated acceptance

Prepared **Release build 41.0.1**, **not launched**:

`/Users/akshaywesley/Developer/WesleyFlow/Run/Milestone41A-41.0.1-b989f4ed/Wesley Flow.app`

Executable SHA-256: `b989f4edcf237d79143951be9b5fbee87a41aa463478d58d376e25da4b480206`.

These steps are for later, as requested. No physical success is inferred from fixtures.

1. Finish/cancel any active task and resolve pending clipboard recovery in the old copy. Quit normally, then open this exact bundle; avoid simultaneous production copies. Confirm build **41.0.1** and General marker **41A / speech38L3R3**. Keep the already-working Agent key; no rebind is required.
2. From a disposable TextEdit document with a clipboard sentinel, Agent-hold “Open Safari”, release, verify actual activation; Agent-hold “Close it”, release, verify normal quit. Test “Open Brave” and “Open WhatsApp” if installed. No command registration, typing/adding or normal dictation insertion should occur. Use only disposable work for save-dialog tests.
3. Say “Open”, release; expect a question and visible Reply needed HUD. Click the HUD to open choices without starting dictation. Reply “Safari” using Agent. Test an app typo and explicitly choose its suggested identity. Cancel/expire a question and confirm old buttons/replies do not execute.
4. Say “Search YouTube”, then reply “how to close Safari” and confirm it remains a query. Separately search Google for a harmless term, then “Search that on YouTube”; verify the exact query. Browser handoff does not mean results were read.
5. Say “Set a timer for two minutes” and “Create a note”, then give disposable note text when asked. Inspect the actual timer/notification and Notes contents/receipt; exercise native permission denial separately and expect a transparent failure. Keep notification timing and actual native outcome distinct.
6. With a consenting test recipient or your own test address, say “Text [name/address]”; answer the body question. Test ambiguous contact choice or Contacts denial with explicit-address reply. Inspect recipient/address/body. Say “Change message to …”, verify a new reviewed draft and no send. Type a different edit without applying and confirm Send is disabled; apply and reread. Reject first. Only in a separate deliberate test click **Send this reviewed message** once and inspect Messages; delivery remains unverified. No voice “yes” should send.
7. Test Help during an incomplete question and during reviewed/unapplied message edit; the draft must remain unsent. Test cancellation/rapid repeat, stale controls and restarting with a pending draft; nothing should resume/send automatically.
8. Repeat ordinary dictation of “Open Safari” into TextEdit: it must insert text without creating an Agent task. Test hotkeys back-to-back, cross-app focus, secure-field refusal, 5/20/45-second Agent recordings, release/cancel, partial/error speech paths and clipboard preservation using the earlier R1 acceptance procedure. No speech engine/range fix is claimed from this milestone.

Pending: physical microphone/hotkey/HUD rendering, actual Contacts and native app permissions/effects, save dialogs, timer delivery, message dispatch/delivery, live websites/music and native admitted-model quality. The previous user confirmation of Open Safari applies to the earlier working build, not this one.
