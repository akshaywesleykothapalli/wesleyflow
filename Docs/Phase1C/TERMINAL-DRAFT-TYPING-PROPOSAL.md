# Terminal draft typing — proposed compatibility mode

Status: DECLINED / NOT IMPLEMENTED. On20 October2026, the user identified Apple Terminal and explicitly selected “Keep Terminal manual-copy only.” This design is retained as a historical, unimplemented proposal. Do not implement or enable it without a separate new request. Existing verified editor insertion and the prior refusal of accessibility-tree activation remain in force.

## Why a separate mode

A terminal screen is not a normal editable document. Its accessibility selection may refer to scrollback rather than the shell input cursor. Treating that selection as permission to replace text can target the wrong semantics; the current verified insertion contract deliberately excludes this case. Supporting it requires an explicit exception to the current verified-field/manual-copy boundary, not a fabricated successful editor observation.

## Proposed implementation

- An explicit opt-in “Terminal draft typing” setting, off by default, limited initially to Apple Terminal. No global fallback for unidentified applications. User-held Fn is still required for every utterance. Command mode and dictation stay separate.
- Capture the actual foreground process/launch identity, focused window and terminal text-area element at Fn down. Revalidate them, native Accessibility permission and secure-input state before dispatch and each bounded Unicode text chunk. Reject missing/changed targets; do not retarget to the current window at release.
- Send plain Unicode text to that PID without clipboard use. Limit to2KiB UTF-8 and reject all control characters, line/paragraph separators and line breaks. Construct no Return, Enter, Tab, Escape, shortcuts, terminal escape sequence or shell/process request. Cancellation and a bounded dispatch deadline stop further chunks; an already sent chunk cannot be recalled.
- Record attempted-but-unverified typing, never INSERTED. Show “Typing attempted; review the Terminal draft before pressing Return.” Do not infer execution, successful delivery, a blank shell prompt or command completion. No clipboard content or terminal screen payload is saved.
- No AXManualAccessibility/AXEnhancedUserInterface writes, browser settings, new entitlements, automatic permission grants, subprocess executor, AI output or model execution. Deterministic fake targets/clocks and native event-construction tests only; actual typing remains human-tested.

## Risk requiring explicit review

Even printable text can act as commands in an interactive terminal program or custom key bindings without Return (for example, a text editor's command mode). Therefore blocking control characters does NOT prove zero command execution. Use this mode only at an ordinary shell input prompt whose state the user understands. The app cannot reliably prove that state or the exact input caret through the current interface. It cannot guarantee password safety for applications that fail to report secure input. Secure-input detection still blocks reported secure contexts, and password fields remain excluded.

This changes application verification policy for a named, user-enabled terminal target. It grants no new OS permission, changes no other app's accessibility behavior and does not enable generic blind pasting. If declined, Terminal remains manual copy. If approved, implementation still requires tests/builds/source review and explicit native setup by the user; approval is not evidence that native Terminal delivery works.
