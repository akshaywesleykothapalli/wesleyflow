# Clipboard-dependent insertion repair

20 October 2026. The user confirmed ChatGPT Mac app and Apple Terminal, declined Terminal draft typing, then reported that WhatsApp and other apps had stopped inserting while Settings still worked.

## Actual evidence

Wesley Flow's own recent History showed captured WhatsApp targets with UNSUPPORTED_TARGET. The app's detail explained that the clipboard contained a format that could not be safely backed up. Capture therefore succeeded for those attempts; the failure was before paste, not microphone permission, speech recognition or missing focused field. Settings can use direct AX insertion and therefore bypasses this clipboard-only blocker. The exact offending clipboard representation in those old attempts was not recorded; it must not be invented. No actual clipboard payload, ChatGPT conversation or terminal screen was inspected or copied into evidence.

Independent reproduction confirmed a defect: NativeDictationPasteboard.install writes the private local.wesleyflow.dictation-owner marker, but snapshot rejected that same marker. If an uncertain paste left its marker across a restart, subsequent snapshots rejected it. This is a confirmed implementation defect and a plausible cause of the reported clipboard failure, not proof of the precise old clipboard format.

## Changes

- Permit a previous Wesley Flow marker only if it contains a bounded, valid UUID. Preserve it as ordinary snapshot data; do not reconstruct/adopt its old ownership lease. New publication creates a fresh UUID, and restoration changes the revision so the old lease remains invalid.
- Support bounded public.utf16-plain-text backup/restore alongside the existing representations. Item/type/aggregate byte limits remain16/16/1MiB. Unknown/private/unavailable/oversized representations still reject before clearing. Diagnostic messages contain sanitized, length-limited format names/capability information, never representation payloads.
- If clipboard backup is unavailable, an already captured and validated editor can use a clipboard-free Unicode text path. This is NOT the declined unverified Terminal mode: full readable field/caret observations and the complete expected text change remain required. It grants no app-wide fallback when capture is unsupported.
- Literal typing is limited to4KiB UTF-8, chunks of at most16 UTF-16 units without splitting surrogate pairs, at most256 down/up pairs, empty modifier flags and a private event source. All control, line-separator and paragraph-separator characters are rejected. No Return/Enter/Tab/Escape or clipboard mutation is introduced by this path. Paired events are bounded by the remaining cooperative insertion budget, cancellation and original target identity checks before each pair.
- An already posted partial sequence cannot be recalled. Only observing the exact expected full text yields INSERTED. Partial, timed-out or cancelled/unacknowledged typing yields UNCERTAIN, with no fabricated clipboard lease or automatic retry. Some applications ignore Unicode event text; they may insert the wrong text or no text, which must remain uncertain. Existing OS focus/event races and synchronous AX timeout limitations remain; no atomic or hard wall-clock guarantee is claimed.
- Apple Terminal is explicitly rejected before automatic insertion, honoring the user's manual-copy-only choice. Its transcript can still be retained/reviewed/copied. Known terminal consoles cannot use the Unicode editor fallback. No Terminal typing mode or accessibility-tree activation was added.

Domain adds defaulted diagnostic getters and a postText method whose false result guarantees no input was posted; true includes partial/uncertain delivery. Native adapter types stay in SystemOperations, UI coordination in App. No new package target, external dependency, model/inference, shell/process executor, prompt submission, browser change or native permission grant occurs. Tests construct native events only and never post them to an application.

Files changed in this repair: Domain/GlobalDictation.swift; SystemOperations/NativeTextInsertion.swift and TextInsertionService.swift; App/SystemWideDictationCoordinator.swift; AppTests/GlobalDictationTests.swift; this documentation. Prior outstanding work is preserved.

## Regression and platform evidence

Tests cover prior-session marker snapshot/restore and old-lease invalidation, invalid markers, unknown private format rejection without clipboard clearing/payload logging, UTF-16 byte preservation, verified Unicode typing without clipboard modification, unacknowledged/cancelled typing, target change during clipboard inspection, dispatch termination after identity/cancellation/deadline loss, Unicode chunk round trip, control/size rejection and the explicit Apple Terminal block. Prior editor/speech/history/Commands/task tests remain.

Primary platform contracts (not live app conformance):
- [Unicode keyboard strings](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:)) — frameworks may ignore supplied Unicode text, hence verification is mandatory.
- [Private event-source state](https://developer.apple.com/documentation/coregraphics/cgeventsourcestateid/privatestate) — independent event state, not an OS containment or delivery guarantee.

Final exact commands, timestamps, source hashes and exits are stored under ignored Evidence/Phase1C2/accepted-clipboard-final-*.json/log/xcresult; before-source/canonical snapshots and reviewed diffs/counts/promotion checks are under Evidence/Phase1C2/ClipboardRepair.

Final verification, all exit0 and source hashes match the current code:

| Check | Result |
| --- | --- |
| Focused app tests | 171 cases / 123 functions passed |
| Complete suite | 795 cases / 350 functions passed |
| Independent replay | 795 cases / 350 functions passed |
| Debug build | Passed |
| Release build | Passed |
| Optimized Release QA test compilation | Passed |

Zero failed/skipped cases; no Swift compiler warnings/errors. Existing AppIntents metadata-skip and test-host linkd connection messages remain in logs. All20 tracked pre-existing test files match HEAD. The full diff is preserved as ClipboardRepair/review.diff. Toolchain is explicitly Xcode-beta/Swift6.4/macOS27SDK with arm64 deployment26; no actual macOS26/Swift6.2.3 runtime claim.

Only after verification, the generated Run/Wesley Flow.app was updated, compared file-for-file with the Debug bundle and deep/strict signature-verified. Previous canonical bundle retained as Run/.before-clipboard-repair. Own stale build registrations were removed and canonical registered last, with absent-entry -10814 responses retained where applicable. No user files, histories or generated bundles were deleted. Promotion argv/exits/hashes are in ClipboardRepair/promotion.json.

Native UI opened the exact canonical path and retained its sidebar/history. The new ad-hoc build starts with Fn disabled and native Accessibility/microphone/speech access needing approval again; no permission grants were automated. The app is left on Settings. A human retry was requested with the clipboard unchanged, WhatsApp first then the ChatGPT Mac app last, without submitting either input. Live acceptance remains pending. No new claim of WhatsApp/browser/ChatGPT success follows from previous human acceptance or current fixtures.

There are39 outstanding tracked/untracked files including prior work; nothing staged. The exact Git status and final source checks are captured in ClipboardRepair/final-review.json. No commit, push or remote change occurred.

Exact final verification commands (DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer; SDKROOT removed):

```sh
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-clipboard-final-focused.xcresult test -only-testing:WesleyFlowAppTests
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-clipboard-final-full.xcresult test
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-clipboard-final-replay.xcresult test-without-building
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-clipboard-final-debug.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-clipboard-final-release.xcresult build
/usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1C2-ClipboardRepair-ReleaseTests -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath $REPO_ROOT/Evidence/Phase1C2/accepted-clipboard-final-release-tests.xcresult build-for-testing ENABLE_TESTABILITY=YES
```

 Live WhatsApp/browser/ChatGPT acceptance for this repaired build remains UNVERIFIED pending the human retry. No commit, staging, push or remote change.

## Subsequent human result

The user subsequently confirmed WhatsApp insertion works and ChatGPT Mac app fails on this clipboard-repair build. See [ChatGPT compatibility follow-up](PHASE1C2-CHATGPT-PASTE.md) for the narrow next change, actual verification and pending live acceptance. Earlier pending statements above describe the original report time.
