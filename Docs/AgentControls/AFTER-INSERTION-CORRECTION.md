# Replace the dictation after Fn

The user clarified that Option+2 must replace the already inserted Fn dictation with a prompt. Option+1 must polish that same inserted span. The previously selected next-recording workflow does not meet that request. The handoff restores `formattingShortcutAction=lastInsertion`; the optional before-insertion mode is preserved but is not selected.

## Replacement changes

The ordinary initial dictation insertion route, including Codex's existing paste-only exception, is unchanged. Later replacement is evaluated separately using actual writable selected-text and selection-range capabilities. The blanket Codex identity exclusion is removed only from this later verified-span path; this is eligibility to attempt the operation, not evidence that a particular editor supports it successfully.

A missing optional AXSubrole no longer rejects an otherwise editable supported text control. Exposed secure/password subroles, secure event input, disabled/read-only fields and consoles remain excluded. No accessibility-tree activation is added.

Composition information remains required for input methods. When an editor explicitly reports AXMarkedTextRange unsupported/noValue, a narrow alternative permits committed-text replacement only while the same Apple keyboard layout remains selected and a gesture-scoped input fence is installed and untouched. Malformed ranges, positive marked lengths, timeouts, denial and invalid elements do not use this alternative. This is a conservative application policy, not proof that every editor exposes all composition state. Physical editor acceptance remains necessary.

The fence retains only a Boolean and its event monitor token. Typing, mouse clicks or scrolling invalidate the anchor even if subsequent edits restore the original bytes. Only the exact Option+1/2 key gestures are exempt. It records no typed characters, coordinates or event history. Removal is tied to anchor lifetime. Existing app/window/element identity, launch identity, exact original UTF16 span, full-document digest, caret, cancellation, 120-second expiry and final pre-write validation remain. The anchor is consumed before selecting/writing. There is one selected-text mutation and exact final readback, with no retry after an uncertain dispatch. No pasteboard write or submit gesture is added.

## Verification

The native suite passed: 843 declarations / 1,918 expanded cases, zero failures. A new integration fixture follows actual registered Fn press/release then registered Option+2, proves the old span is replaced by the generated prompt, retains surroundings, performs no second recording, opens no preview, leaves the clipboard untouched and rejects a duplicate shortcut. This uses a fake provider/editor; it does not prove a physical editor write or real model generation.

New capability tests cover missing descriptive subroles, secure/read-only rejection and every stable-keyboard/untouched-input combination for unavailable composition. The input-gesture policy rejects ordinary typing, mouse events and other modifier combinations. Existing generation cancellation, changed source, provider resource rejection and English/Telugu regressions remain in the full suite.

An initial native build failed because Swift rejects covariant Self in a stored-property initializer. The initializer was corrected to use the concrete class name; the full rerun passed. No user data was accessed by tests. No physical keys, microphone capture or external-app accessibility inspection/injection were automated. Release, package regressions and handoff results are recorded below when complete.

Release complete-concurrency build passed. Actor-checked deterministic speech/Agent/Unicode/audio/provider regressions passed. Repository checks passed (409 tracked files / 1,087 history objects); CI helper 15 tests and local packaging 3 tests passed. The first packaging test invocation selected the wrong directory and ran zero tests; the corrected invocation passed all three.

The guarded native AI diagnostic reported readiness=ready, then polish=resourceBlocked after 4,503 ms. Original synthetic input was retained; prompt generation was not attempted after that blocked result. No memory threshold was changed and no further generation was retried. The initial diagnostic launch hit a nested SwiftPM sandbox conflict before running any tests; the corrected launch kept the outer network denial and disabled only the redundant nested SwiftPM sandbox. A passed diagnostic test confirms correct rejection, not successful generation.

## Handoff

Installed and reopened 45.0.9 at `/Applications/Wesley Flow.app`. The previous 45.0.8 app accepted normal Quit and is preserved under ignored `Evidence/AfterInsertionCorrection/PreviousInstalled45.0.8.app`. No force quit or clipboard inspection was used. The explicit existing app-local ad-hoc signing helper was reused; strict/deep signature verification passed and the installed process survived the 15-second check.

Only `formattingShortcutAction` changed from `nextRecording` to `lastInsertion`; all other existing preferences were checked equal after launch. Implementation commit: `cabe6ec`. Ignored provenance: `Evidence/AfterInsertionCorrection/handoff.json`. The two shortcut behaviors remain selectable, but the installed user's selected behavior is replacement of the last dictated span. No further recording is required after pressing Option+2.

Physical acceptance sequence: click inside the destination editor, hold Fn and speak English, release, wait for the insertion, then press Option+2 without typing/clicking/moving the cursor. Expect replacement of only the last own dictated span if editor verification and local generation both succeed. The current synthetic local generation check was resource-blocked; no successful live model/editor replacement is claimed. Option+1 uses the same provenance route for polish. Failures retain their explicit blocker and never silently arm another recording or open a preview.
