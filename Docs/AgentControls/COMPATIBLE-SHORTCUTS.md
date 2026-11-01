# Command reference and compatible formatting shortcuts

The user rejected per-command “Use command” buttons and reported that Agent capture produced no action. They confirmed that Option+1/2 displayed “editor unsupported” in Codex/ChatGPT and Apple Notes. They then explicitly approved formatting the next recording before initial insertion.

## Changes

Command Mode now shows commands beside descriptions. No per-command action button remains. A compact command-key/status control remains, and optional typed requests are collapsed. The latest recognised request is visible, and speech failures retain their actual diagnosis instead of the generic incomplete-command notice. A diagnostic copy action is available when a command fails.

Agent recognition now prefers the installed modern Apple speech engine, matching the working English dictation path. Previously it preferred the legacy recognizer whenever one was available, bypassing modern readiness inspection. The legacy path remains an offline fallback. Modern Agent sessions receive bounded local command/application vocabulary through AnalysisContext. Ordinary English dictation does not receive that context and retains its existing selection policy. The old physical failure was not captured with a full command diagnostic, so a specific legacy-engine defect is not claimed as proven.

The existing after-insertion replacement path explicitly excludes Codex and requires metadata such as composition state that Notes does not always expose. These restrictions were not bypassed. The new **Next recording · local formatting** mode avoids that operation:

1. In the destination app, press and release **Option+1** for Smart Polish or **Option+2** for a structured prompt.
2. A nonactivating pill says **Polish armed** or **Prompt armed**.
3. Hold **Fn**, speak English after capture is ready, then release.
4. Local formatting runs before the existing insertion pipeline dispatches the text once.

This mode uses deterministic formatting, not AI generation. Polish performs bounded cleanup with protected-span and word-fidelity checks. Prompt formatting uses the existing extractive contract: original source units remain in order under headings inferred only from explicit prefixes. No requirements, commands or facts are generated. This is a local baseline, not a claim of AI prompt quality or broader semantic rewriting.

An armed action expires after two minutes, is bound to the destination process and is consumed by one Fn gesture. Agent and manual capture do not consume it. Escape/cancellation clears the armed action; cancellation during recording cannot carry it to another gesture. A changed target uses ordinary dictation. Telugu and unsupported/oversized inputs retain ordinary text with an explicit notice. English-only local formatting is labelled in the UI. Pending clipboard recovery, secure-field rules, original-target binding and uncertain-delivery safeguards remain intact. Terminal remains manual-copy only.

The previous **Last insertion · on-device AI** mode remains available with its unchanged model/editor/resource guards. Existing preferences missing the new field decode to that old behavior; the installed user's new mode is selected explicitly during the approved handoff. No global default migration silently changes other installations. No automatic preview or clipboard-copy fallback was added.

## Verification

- Actor-checked deterministic local formatting: four test declarations / six expanded cases passed, covering filler/punctuation cleanup, code, numbers, negation, repetition, exact extractive prompt rendering, and rejection of unsafe/oversized prompt input.
- The full deterministic speech/Agent gate passed, with real-model flags stripped. Agent, English/Telugu routing, callback, downmix, Unicode and rewrite regressions remain covered.
- Real recorded Agent command recognition passed with the installed modern SpeechTranscriber en-IN, AnalysisContext and production three-channel ingress. Locally generated Samantha recordings were recognised exactly as “Switch dictation to Telugu only.”, “Switch dictation to English.” and “Show battery status.” and mapped to their typed command meanings. All three completed in 1.008 seconds overall, with networking denied. No physical microphone, key injection or Mac action was used.
- Final CI-selected native suite: **840 declarations / 1,915 expanded cases passed**, zero failures. Required new regressions were validated. The normal four graphical tests were excluded from that count.
- Integration fixtures prove that both formatting shortcuts work with an editor whose rewrite-anchor creation is unsupported, perform one normal formatted insertion, never invoke the AI provider, and do not open a preview. They also cover duplicate completion, cancellation, target changes and legacy preference decoding.
- Native page rendering in both appearances passed with the new mode enabled. The command reference and Smart Formatting renders were visually inspected. Images use fixture settings/status, not the user's running permission state. Source search confirms no “Use command” button remains.

Evidence is under ignored `Evidence/CompatibleShortcuts`, with the native Agent recording log and local unit output copied there. No user audio or transcripts are committed. Physical Agent recognition and text delivery in the user's Notes/Codex fields still require user-operated acceptance. The new route reuses ordinary insertion already confirmed by the user; a synthetic fixture is not proof of new live-editor delivery. No claim of successful live AI generation is made, and the AI memory reserve was not changed.


## Handoff

Release build with complete concurrency checking passed. Native page rendering passed in both appearances. CI helper tests: 15 passed; local packaging-policy tests: three passed. The final installed application passed strict/deep signature verification and survived a 15-second launch check.

Installed and reopened **45.0.8** at `/Applications/Wesley Flow.app` after 45.0.7 accepted normal Quit. The prior bundle is preserved under ignored `Evidence/CompatibleShortcuts/PreviousInstalled45.0.7.app`. The user-approved `formattingShortcutAction` was set to `nextRecording` through CFPreferences only after the old app quit. Every other existing JSON preference was checked for equality afterward; the Agent key remains Right Command. No history reset, clipboard access or forced quit was used. The existing explicit local-ad-hoc signing helper was reused. Implementation commit: `5304b6d`; provenance is in `Evidence/CompatibleShortcuts/handoff.json`.

User acceptance: hold Right Command, speak a listed command and release; verify the visible Heard/Understood result. In an ordinary Codex/Notes draft, press and release Option+1 or Option+2, wait for its armed pill, then hold Fn, speak English and release. Verify one locally formatted insertion. Previously inserted text is not rewritten by this selected mode. The live microphone and physical editor insertion were not driven by verification scripts.
