# Empty editor focus and clipboard recovery — 45.0.19

The 45.0.18 Instagram attachment shows capture and transcription succeeded, the correct Brave web-app process/window/editor was acquired, and AXValue/selection initially reported an empty document and caret zero. One paste was dispatched, but readback remained zero through the 1500 ms deadline. The backup was retained; the later PASTEBOARD_LEASE_RESULT=RESTORED confirms clipboard recovery succeeded. It does not establish that text was inserted. Recovery intentionally never retries an uncertain paste.

The user reported success after typing first, and then reported a successful Fn-only Instagram retry while still on 45.0.18. Thus the failure is intermittent. The last reply was not a controlled Command+V comparison and does not establish an event-routing defect. No global event-posting or alternative menu-paste transport was added based on that incomplete evidence.

## Changes

Before publishing a clipboard lease for an empty guarded-paste editor, native insertion now validates the captured target, requests public AXFocused=true on that exact editor, revalidates its original document/caret/window/process and confirms keyboard focus. The SDK documents AXFocused as writable for focusable elements. No other app/window/editor is selected; no dummy character, deletion, global shortcut, private accessibility flag or app activation is used. Nonempty editors keep their existing focus. Unsupported focus, changed selection/context, denial or cancellation aborts before clipboard publication. All existing lease, timeout, target, secure-input and one-dispatch guards remain. This addresses a plausible empty-editor initialization problem; a physical cold-field reproduction remains unverified.

Text readback previously accepted a successful empty AXValue without checking character count. It now checks the independent count for empty values. A positive count requires a complete matching range/attributed-range result; a contradictory or partial result fails. Zero count confirms empty text; an empty AXValue remains usable when count is unsupported. Nonempty values retain their previous path. This prevents a stale empty primary representation from hiding readable text, but the supplied older trace did not include character-count observations, so stale AXValue is a hypothesis rather than a diagnosed fact for that attempt.

Clipboard recovery now explicitly says it restores the previous clipboard without inserting/retrying the old dictation, and directs the user back to the field for a fresh Fn recording. The old transcript remains in History according to existing settings. Successful recovery clears the pending lease and permits the next gesture. It never converts uncertain delivery into success or replays old text. The confirmation dialog explains the same distinction. Clipboard ownership and newer-copy protection are unchanged.

New bounded metadata codes report focus writability, request acknowledgement and confirmation, without field/transcript/clipboard contents. Notes/direct insertion, Fn capture, ASR, model rewriting and the guarded-paste transport are unchanged.

## Verification

The actor-checked package gate passed. The full native Xcode Debug suite passed 1992 expanded cases across 900 declarations, zero failures. The arm64 Release build passed complete Swift concurrency checking. Repository/history checks, 15 CI tooling tests and 3 local-packaging tests passed.

Tests cover focus/validation ordering, nonempty fields skipping refocus, denial/change/cancellation preventing publication, alternate range/attributed text for stale empty AXValue, malformed/partial/empty observations, and preparation before snapshot/install. A service regression proves recovery does not replay a failed paste and a later explicit insertion can succeed. The coordinator regression follows Fn refusal during pending recovery, explicit restoration, a new Fn recording, and verified delivery of only the new text. No microphone or external editor was automated; the user's reported Fn success refers to 45.0.18, not physical verification of this update.



## Installed handoff

Source commit `1fc06d2`. The initial installation stopped when the running app declined normal Quit; no overwrite or force termination was used. After the user reported closing it, installation resumed from the existing verified prepared copy. Installed 45.0.19 at `/Applications/Wesley Flow.app` with the existing explicit ad-hoc signing helper. Strict/deep signature verification and the 15-second launch observation passed. All preferences were preserved. Temporary signing/build/package copies and the previous app backup were removed after successful launch. No microphone or external editor was automated, and no real clipboard contents were inspected or modified by verification. Empty-field behavior on the actual sites remains physical user acceptance; use a fresh Fn recording after returning focus to the intended field.
