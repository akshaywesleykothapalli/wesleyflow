# Milestone 39 — Offline-First Intelligent Personal Assistant

29 October 2026 · **39A / build 39.0.1** · foundational implementation, not full personal-assistant acceptance.

The current user request authorizes these scoped personal-agent effects beyond the historical milestone stops in AGENTS.md. Existing proposal-only coding infrastructure remains disabled. No commit, staging, push, model download, PR operation, installed-app replacement, microphone capture, clipboard manipulation, or communication sending was performed.

## Delivered path

Commands now accepts developer text and the existing explicitly armed hold-to-talk channel. An unarmed gesture still dictates into its original guarded destination. The armed channel converts the completed on-device transcript to a **reviewable plan**, rather than immediately opening an app. Every clause must parse before anything is queued. Every plan needs the human's **Approve these actions and run** button. Native permission prompts occur only inside the approved tool. Existing app-opening buttons retain their separately explicit user action.

Try this text first, with networking disabled if desired:

```text
create note shopping then remind me review shopping in 10 minutes then open Notes
```

Capitalized `Then`, command-ending punctuation and common spoken minute words are supported. `create a note` is an alias. This is a bounded English grammar, not general language comprehension. Ambiguous dates, unknown apps/actions, shell commands and partial parses fail closed. `then` separates actions even inside note text; quoting/escaping that separator is not implemented. A note's text otherwise remains literal data.

Additional supported examples:

```text
calendar Meeting at 2026-11-01T09:00:00+05:30
timer Tea in five minutes
open safari https://example.com
music pause
spotify play
```

Calendar duration is explicitly 30 minutes; there are no attendees/invitations. Relative minute dates bind at intake and are shown before approval. ISO-8601 dates require a timezone. All dated actions reject expired dates at execution. Unsupported `next`/`previous`, singular minute grammar, arbitrary browser scripting, natural-language calendar interpretation and recurring workflows are follow-on work.

## Source and authority boundaries

| Source | Responsibility |
| --- | --- |
| `Packages/WesleyFlowCore/Sources/Domain/PersonalAgent.swift` | Sendable/Codable immutable plan and step values, closed typed tool enum, receipts/task states, whole-request deterministic parser, injected main-actor tool port |
| `Packages/WesleyFlowCore/Sources/SystemOperations/PersonalAgentEngine.swift` | One active plan, exact displayed-plan equality check, write-ahead journal, exclusive OS file lease, cancellation between effects, conservative restart recovery, explicit memory |
| `Packages/WesleyFlowCore/Sources/SystemOperations/NativePersonalTools.swift` | Fixed native adapters; EventKit, NSAppleScript, NSWorkspace and UserNotifications only |
| `App/SystemWideDictationCoordinator.swift` | Review/approve/cancel/delete composition over the existing command channel; native instance ownership check before production queue opening |
| `App/GlobalDictationView.swift` | Small controls in existing Commands page; saved task receipts and explicit memory controls; no navigation, waveform or settings redesign |
| `App/PersonalAgent.entitlements` and project build settings | Apple-event automation entitlement and explanatory Notes/Reminders/Calendar privacy keys; 39.0.1 identity |
| `Packages/WesleyFlowCore/Tools/PersonalAgentHarness/main.swift` | Default parse-only executable; optional `--execute` requires typing APPROVE for displayed actions and uses separate harness queue |
| `AppTests/CompositionTests.swift`, `Packages/WesleyFlowCore/Tests/Phase1ATests/PersonalAgent39Tests.swift` | Same agent suite consumed by native application tests and standalone package tests |
| `AppTests/GlobalDictationTests.swift` | Armed voice now stops at review; unarmed speech remains dictation; command tests use temporary isolated storage |

Existing TaskExecution/SwiftData orchestration, PermissionBroker, coding proposals and inference providers are preserved. Personal-agent effects have a separate scoped journal/service and do not weaken that broker's existing rejection of productive coding operations. This first slice puts the service beside the trusted native adapters; it does not migrate earlier task schemas or silently make coding plans executable. There is no model access to the human approval method, executor, filesystem roots or permission authority.

No new code invokes FoundationModels, Ollama, MLX, URLSession or a subprocess. The agent brain always uses the deterministic parser, including when Apple Intelligence is unavailable or the host is below the 4 GiB inference floor. Existing opt-in FoundationModels rewriting and its readiness, memory, swap, timeout and cancellation guards are unchanged. Optional model-assisted personal intent proposals are **deferred**, not claimed as implemented or physically tested. No generated model output can authorize effects.

## Native capability status

All adapters below **compile**. End-to-end native/TCC physical acceptance is **pending**, not inferred from fixtures. No permissions were automatically granted, denied or bypassed during implementation.

| Capability | Implemented operation and receipt | Current limit / acceptance |
| --- | --- | --- |
| Notes | Fixed Notes app AppleScript, escaped HTML text, UUID title/marker, returned note ID and marker readback; 10 second Apple-event timeout | Automation consent/default writable account required; marker readback does not establish complete body fidelity. Physical check pending |
| Reminders | EventKit full access requested on approved execution; default reminders calendar, title, due components, alarm, step URL; saved identifier/title/due readback | Denial/no writable list handled. Real account/TCC acceptance pending; notification delivery not inferred |
| Calendar | EventKit full access, default calendar, 30 minute event, no attendees; identifier/title/start readback | No recurring event/edit/search/invite support. Real permission/account acceptance pending |
| App opening | Existing NSWorkspace allowlist adapter; openApplication completion | Launch receipt does not prove foreground editor readiness or subsequent app action. Physical check pending |
| Safari | Fixed open-new-document template for credential-free HTTPS only, exact front-document URL readback | No JavaScript, DOM/computer control, tab search or authenticated automation. Redirect/load delays may return needsReview. Website content needs connectivity |
| Music / Spotify | Installed-app check; fixed play/pause template, player-state readback | Automation consent and playable media required; no selection/search/next/previous. Streaming/login/catalogue may require connectivity. Physical acceptance pending |
| Timers / alarms | Durable OS UserNotifications calendar trigger; pending request ID readback | Scheduling receipt only. No wake-from-sleep guarantee, critical alarm, audible delivery guarantee, snooze, timer cancellation UI or recurring scheduler. Focus/system settings can delay/suppress delivery. Physical acceptance pending |
| Mail / Messages | **Not implemented**; parser rejects these commands | Follow-on: compose-only templates and one-use final approval bound to exact recipients, channel, content and attachments, plus conservative send uncertainty. No send route exists now |
| Research / recurring background workflows | **Not implemented** | Browsing/research requires connectivity; no network fallback for the agent brain. No LaunchAgent, privileged service or background watcher installed |

The app is not App Sandboxed. Automation uses macOS TCC, the usage string and the Apple-events entitlement. EventKit uses full-access usage strings and its native consent APIs. The ad-hoc test build is not a notarized/hardened distribution claim (Xcode reports disabling hardened runtime for ad-hoc signing). Production signing/TCC identity stability remains a release gate. CLI TCC attribution differs from the app; use the app for acceptance, not an absent CLI permission prompt as proof of adapter failure.

## Durability, cancellation and truthful outcomes

- At most eight steps/plan, 4,096 input UTF-8 bytes, 2,048 bytes/step, 100 retained tasks and 4 MiB journal. One active plan holds ownership until the native call settles. File lease prevents simultaneous writers/executors for the same queue. Queue has no auto-drain; each pending plan is reviewed explicitly, including after restart.
- Before a tool call the step is atomically journaled as executing. Verified receipts are saved before advancing. Completed/review-needed/cancelled plans cannot be re-approved under the same ID. Enqueueing the same plan ID is idempotent. New human requests intentionally receive new IDs; semantic deduplication across differently worded/new requests is not claimed.
- A crash during an effect or receipt write produces needsReview/uncertain on reopening. The next step does not run. No automatic retry can duplicate an uncertain effect. There is no general exactly-once transaction across the journal and another app. Notes additionally embeds the step UUID, and notification requests use deterministic UUID identifiers.
- Native failures are conservative: even permission failure currently records uncertain/needsReview, never fake completion. Existing receipts remain visible after partial failure. The UI shows per-step state and the actual evidence strength.
- Cancellation stops remaining steps, retains successful in-flight receipts and cannot undo an external effect. Queue-record deletion does not delete Notes, reminders, events or scheduled notifications. In-flight UI task deletion/normal quit is blocked by the existing busy guard.
- This is bounded by queue/step/input sizes and fixed Apple-event timeouts, **not a fully bounded background scheduler**. Native consent callbacks or a noncooperative OS operation can hold the execution slot; there is no hard overall wall-time deadline, automatic process kill or overlap after timeout. The synchronous AppleScript adapter can temporarily block the main actor. Moving it to a contained dedicated execution service and adding independently verified reconciliation are follow-on work.
- Journal writes use atomic replacement and an exclusive advisory OS file lease. Power-loss/fsync guarantees, protection against other software running as the same user, symlink-hardening of every storage path, schema migration and encrypted storage beyond OS/file protections are not claimed. Corrupt/oversized journals fail closed and are preserved.

## Local memory and privacy

Memory is off each launch and requires the explicit toggle. It saves only the bounded text the user enters and clicks Remember for. No background observation, transcript/audio capture, clipboard capture, activity scraping, training, automatic fact extraction or model disclosure is implemented. Search, correction, per-item deletion and delete-all are real local persistence operations. Default retention is 30 days; API bounds are 1–365 days. Expired entries are excluded and purged on the next search/access, not by a wake-capable retention daemon. Disabling memory hides entries and stops writes but does not erase them; Delete all is explicit.

The approval queue separately stores the exact user-requested action text and receipts so it can recover truthfully. It is not an automatic memory source. Both journal and memory use app-specific files below `~/Library/Application Support/WesleyFlow/PersonalAgent/`, private directories/files (0700/0600), bounded reads and no content logging. The developer harness uses `harness-queue.json`, separate from `queue.json`; memory uses `memory.json`. No existing SwiftData/history schema or preferences were changed. Deletion is normal filesystem deletion/rewrite, not a forensic secure-erasure claim.

## Automated evidence

Final results are appended below after frozen-source checks. The initial complete headless run and independent test-without-building replay each passed **1,399 expanded cases**, zero failures. Review then added the voice-capitalization/number-word regression, so only the final results below apply to final-source acceptance.

The final focused suite contains 17 declarations / 27 expanded cases. It covers multi-step planning and grounded dates, spoken transcript formatting, whole-request rejection, unsafe URL/app rejection before permissions, no effects at enqueue, exact approval binding, stable-ID replay protection, persisted success, fresh restart approval, write-ahead storage failure, exclusive file leases, permission-denial/partial-failure stop, cancellation with actual receipts, crash-window uncertainty, corrupt data preservation, and explicit memory search/correction/retention/deletion/off-on-restart.

The developer harness parsed the multi-step acceptance example under `(deny network*)` without invoking any tool. The final 17-declaration / 27-case focused suite also passed inside explicit `(deny network*)` per-process restrictions. Initial `--skip-build` discovery found no tests, and a nested manifest-sandbox attempt was rejected by macOS. The successful run used normal SwiftPM discovery with its inner manifest sandbox disabled while the outer network-denial profile remained active. These failed setup attempts were retained as evidence, not counted as successes. This is evidence for this parser/core path; it is not evidence that websites or streaming work offline, or that production macOS apps are OS-network-contained. No live model generation was attempted. Existing unavailable-model/resource-policy regressions remain in the application suite.

Native full/headless tests exclude exactly the four pre-existing graphical layout/appearance tests listed in `Tools/CI/run_checks.py`. They are **not claimed passed here**. Test-host app launches by Xcode are part of verification; the user's running installed/standard copy was never replaced, force-quit or used to record/inject text. User-operated speech, physical TCC denial, live app effects, sleep/Focus delivery and current ChatGPT insertion acceptance remain pending.

## Physical acceptance instructions

1. Save any needed current transcript and resolve pending clipboard recovery through the existing UI. Quit the current app normally, only after its termination guard permits it. Do not launch two production copies. Open the prepared 39.0.1 app identified in final evidence below; verify its General diagnostic build marker includes 39A and speech38L3R3.
2. Turn networking off. In Commands enter the three-step note/reminder/open-Notes example above. Review the complete note text and reminder's absolute due time. Confirm nothing was created before pressing Approve. Approve only these disposable actions. Allow or deny native Notes/Reminders permission intentionally.
3. On allow, inspect the actual note body and reminder title/time, confirm Notes opens, and inspect each receipt. No step may say completed without its adapter receipt. Deny one permission in a separate disposable task: remaining steps must stay pending, task needsReview, no repeated request/effect on reload.
4. Load saved tasks after a normal restart. A completed plan must have no replay action. An unapproved plan requires fresh approval. For a deliberate interrupted disposable action, review the external apps manually: executing becomes uncertain/needsReview and must never auto-run. There is no automatic resume/reconcile UI for uncertain plans yet; do not blindly submit a replacement request.
5. Enable explicit memory, save a synthetic preference, search/correct/delete it. Restart: memory is off. Delete-all and task deletion affect their separate local records. Do not use real secrets for acceptance.
6. Arm the next gesture in Commands, speak the same supported request using the existing shortcut, release, then inspect the plan before approval. Repeat a short unarmed TextEdit dictation to confirm ordinary target binding, waveform and clipboard safeguards remain intact. No tools should type into ChatGPT/Codex/Terminal as part of this check.
7. Separately test Calendar, a short notification timer, Music/Spotify and HTTPS Safari navigation with disposable data. Check actual outcomes and TCC-denial behavior; offline Music requires already-local playable media. Restore internet only for explicitly requested online browsing/streaming tests. Check notification settings, Focus and sleep behavior separately; scheduled is not delivered.

No live adapter is accepted solely because its source compiled or a fake runner returned a receipt. Follow-on milestones must add broader natural-language proposal generation behind the unchanged 4 GiB policy, recipient-bound communication drafts/sends, scoped browser controls, richer playback, recurring/durable background workflows, bounded nonblocking native execution and independently reconciled partial recovery before claiming the full requested assistant.

## Primary API references

- [NSAppleScript](https://developer.apple.com/documentation/foundation/nsapplescript)
- [EventKit event store and access](https://developer.apple.com/documentation/eventkit/ekeventstore)
- [Reminder full access](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoreminders(completion:))
- [UserNotifications](https://developer.apple.com/documentation/usernotifications)
- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)

## Git preservation

Branch `feature/milestone-31-integration`, HEAD `24db5c924f8598c6971c771e41f1678262e54379`. The repository began dirty with 23 tracked modifications and five untracked speech milestone documents. Their speech range/focus work is preserved. A turn-start patch, source hashes and status snapshot are retained in local evidence. No staged content, commit, push, rebase or PR #1 operation was performed. Exact final status and byte-preservation comparison are saved beside the final evidence; see appended final checkpoint.

## Final 39A checkpoint

- **1,401 expanded headless regression cases passed**, zero failures; independent `test-without-building` replay: **1,401 passed**, zero failures. Exactly the four historical graphical checks were excluded. The CI selection validator confirmed all required pre-existing speech/focus regression identities remained present.
- Focused agent suite: **17 declarations / 27 expanded cases passed**, including a separate passing run under explicit network denial. Parse-only multi-step harness also passed under network denial.
- Final-source Debug (test build), Release and `SWIFT_STRICT_CONCURRENCY=complete` builds: **passed**, Swift 6 mode, Xcode 27.0 / Swift 6.4 / macOS 27.0 SDK, arm64. This does not establish older compiler/OS compatibility. No new Swift concurrency warning was accepted.
- CI helper: **13 tests passed**. Repository/history security scan: **passed**, 299 tracked files / 648 history objects, no issue categories. `git diff --check`: passed.
- The final progress regression verifies that published pending/running/executing/verified/completed transitions follow persisted state. The executing transition is published before tool entry; physical permission-dialog behavior remains pending.
- 56 of the 61 captured pre-existing implementation/test/project files remain byte-identical. Five narrowly extended baseline files are the Commands view/coordinator, two consumed test files and project build metadata. The package manifest adds the developer harness product/target. All speech/clipboard/provider/history implementation files and prior speech reports are preserved.
- Git: 25 modified tracked files total, including the 23 pre-existing modifications; seven new artifact/source entries in addition to five pre-existing untracked reports. Nothing staged; HEAD/branch unchanged. See `Evidence/Milestone39A/git-status.txt` and `preservation.json` for exact lists.

Prepared, **not launched**: `/Users/akshaywesley/Developer/WesleyFlow/Run/Milestone39A-39.0.1-8e03ec42/Wesley Flow.app`. Executable SHA-256: `8e03ec429d571c3ca1aa91e37bb6812a284b15b13e0bbef10a9bbc5c6835ca08`. The standard/running app has not been replaced or quit. Resolve existing transcript/clipboard recovery and normal quit through the app before opening this separate build.

Local evidence: `Evidence/Milestone39A/manifest.json`, `Final/summary.json`, full test/replay xcresults and test trees, Debug/Release/concurrency logs, focused/offline logs, turn-start patch/hashes, source hashes and Git status. Native Notes/Reminders multi-step physical acceptance, real TCC denial, Calendar/Safari/media/timer delivery and unarmed speech acceptance on 39A remain **pending**. No communication sending capability exists.
