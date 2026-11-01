# Agent language controls and in-place shortcut diagnosis — 2026-11-01

## Request and audit

The user requested spoken English/Telugu language switching, simple dictation and everyday Mac commands, and another look at Option+1/2. They confirmed that language commands should change the **next Fn dictation**, and explicitly chose **in-place only, with the exact blocker**, rather than an automatic preview fallback.

The existing app already had separate Agent recognition, app/audio/window/battery actions, strict replacement receipts, Apple on-device rewriting, and manual previews. The saved shortcut preferences were all enabled: preview shortcut registration, Smart Polish, Prompt Engineering, in-place rewrite and focused-text access. The existing Option shortcut route deliberately does not use focused-text capture. Earlier insertion evidence showed verified delivery but unsupported precise editor replacement, which prevents an eligible rewrite receipt. Registration, insertion verification, replacement support and AI generation are separate gates.

## Implemented behavior

`FlowVoiceControl` is an exact, bounded whole-utterance parser for app-local commands. It is invoked only for Agent requests, after capture finalization or an explicit text request. Ordinary Fn dictation never executes these controls, and requests made during an active capture are ignored. Pending questions, recipient resolution and review plans keep their existing reply handling; a command-shaped note/message body stays literal. These controls do not go through an LLM or become executable saved plans.

Examples:

- “Switch dictation to English.”
- “Switch dictation to Telugu only.” (“Switch dictation to Telugu” also selects Telugu-only.)
- “Use automatic Telugu and English.”
- “Open dictation settings.” / “Show dictation history.”
- “Open my dictionary.” / “Open smart formatting.”
- “Stop saving dictation history.” / “Save dictation history.”
- “Turn on spacing cleanup.” / “Turn off spacing cleanup.”

Language preferences are updated together and apply to the next gesture. Telugu preparation uses the existing model-preparation path and does not start the microphone. English keeps its Apple engine; Telugu keeps the existing local Small pipeline; Agent recognition remains English. Turning off history changes future retention and does not delete saved entries. Navigation opens the relevant Wesley Flow page. Compound, partial, negated and destructive-history requests are not recognized by the local-settings parser.

The Command Mode page puts the request field first and exposes examples for dictation controls and existing app, volume, battery and window actions. “Use command” fills the request only; Run text request remains explicit. Added natural aliases for “turn [the/system] volume up/down”, “show battery status” and “how much battery is left” use the existing typed Mac tools. They do not introduce shell or generated-tool execution. Real Mac actions keep existing app matching, permissions, verification and review policies.

Option+1 and Option+2 still use the existing in-place-only route. A failure now remains visible on Dictation after the transient pill disappears, with a link to shortcut status. Smart Formatting begins with registration status, editor/receipt readiness, the last exact shortcut error, explicit Copy diagnostics, and a read-only local-AI readiness check. The check reports model/language, busy, memory or observation blockers without creating a generation session, inspecting an editor, opening the microphone or modifying the clipboard. Passing the snapshot does not guarantee later generation: the existing generation guards recheck resources. Manual previews remain separate explicit actions.

## Actual verification

- Xcode 27.0 / Swift 6.4 / SDK 27.0, arm64 native CI selection: **836 passed declarations / 1,910 expanded cases, zero failures**. New required-test identifiers were validated against the result bundle, including the literal-reply and provider-readiness regressions.
- Pure command parser/alias suite: five declarations / 29 expanded cases passed. All displayed local command examples parse; partial/compound/negated/literal/destructive requests are rejected by that parser.
- Actor-checked deterministic gate passed for Unicode, capture/callbacks, routing, recognition admission, Apple multichannel downmix, Agent controls and the fake-driver rewrite provider. Real-model opt-in environment flags are removed by the helper.
- Readiness tests verify zero generation calls for ready, unavailable-language/model, low-memory and failed-memory-observation checks. Native integration tests cover voice switching without insertion, busy/ordinary-dictation separation, navigation, retention without deletion, and persistent shortcut blockers with no preview fallback or generation.
- The first native run failed the new pending-note test because it lacked an isolated Agent queue; the installed app correctly prevented that fixture from acquiring production queue ownership. The fixture was given its own temporary queue and fake tool runner. The full native rerun then passed; no real note, message, volume or window action was performed by tests.

One guarded real FoundationModels diagnostic used synthetic text only, with networking denied. Readiness initially passed, but Smart Polish generation was **resourceBlocked after 517 ms**. The provider stopped under its existing memory/resource guard and retained the original synthetic input. It was not retried, the 4 GiB reserve was not lowered, and Prompt Engineering generation was not attempted after that block. This is evidence of a live resource blocker, not proof of successful live AI rewriting. Existing deterministic Prompt Engineering contract tests passed separately. No physical Option-key delivery or real cross-app AI replacement was verified in this task.

Evidence is retained under ignored `Evidence/AgentControls`, including `Final/tests.xcresult`, `Final/test-summary.json`, package/probe logs and the final handoff metadata. Hosted CI has not run. Release, page rendering and handoff results are appended when complete.

The final native run also covers a shortcut arriving during capture: it records the busy blocker without stopping recording, inspecting the focused editor or starting generation. Final page rendering in light and dark appearances passed before this metadata-only refinement; the Release build was then rebuilt with complete concurrency checking. CI helper tests: 15 passed; local packaging policy tests: three passed.


## Installed handoff

Build **45.0.7** was installed at `/Applications/Wesley Flow.app` after 45.0.6 accepted normal Quit. The old bundle is preserved under ignored `Evidence/AgentControls/PreviousInstalled45.0.6.app`; no force quit, clipboard access, history reset or settings reset was used. The existing explicit local-ad-hoc packaging helper and previously documented app-scoped signing configuration were reused. The installed signature verified, and the exact Applications process survived a 15-second launch check. Implementation commit: `bee424e`; detailed provenance is in `handoff.json`.

After restart, dictate a fresh sentence before testing Option+1/2: process-local verified replacement receipts are deliberately not restored from history. Try the spoken language commands with the separate Agent key, or use the Command Mode text request field. Physical Agent key delivery, live recognition of the new phrases and live Option-key replacement remain user-operated acceptance checks. Successful live AI rewriting is not claimed; the bounded real probe was resource-blocked.
