# Protected prompt sentences — 45.0.16

The user supplied “I wanted to add an animated UI button for this application.” and reported an Objective containing a repeated suffix: “…button for this application.UI button for this application.” The earlier Option+2 contract could accept a whole sentence as an edit to a gap before the protected UI span, then reconstruct UI and its original trailing prose. The previous per-unit fact checks did not exclude that duplication. The user's reported output does not include the raw model transport; the reconstructed boundary defect is demonstrated by deterministic cases, rather than assuming which exact reply caused the earlier attempt.

## Correction

Prompt request normalization now recognizes explicit “I wanted to …” preambles as well as the existing forms. Normalized source prose is retained even when the model supplies no wording edits. Thus this request becomes “Add an animated UI button for this application.” It does not add animation libraries, design requirements, implementation details or acceptance criteria the user never supplied.

Units containing internal fixed spans are excluded from AI prose editing. They retain their whole normalized sentence, fixed terms and source order. Other mutable prose units can still use the existing local AI provider. When no prose is eligible, the provider performs only app-owned normalization and layout, without model readiness, memory sampling, a generation session or lease. This is an input-selected deterministic operation, not fallback after rejected generation. Diagnostics explicitly report LOCAL_PROMPT_STRUCTURED and model=notRequested; coordinator revalidation and exact-span insertion guards still apply. The style/enable preferences and English-language input contract remain.

This is a deliberate limit: Option+2 will not paraphrase a sentence split by protected names/identifiers/numbers. It can still structure and normalize that sentence. No generic generated details are appended. The example needs only Objective.

Defense in depth rejects new sentence-ending punctuation immediately before a fixed span in prompt edits, and rejects newly repeated four-word phrases while preserving repetitions already present in the source. The coordinator independently checks the same repeated-phrase and protected-sentence constraints before replacement. Option+1 retains its existing rendering behavior; dictation, Codex paste and Notes insertion are unchanged.

## Verification

The focused actor-checked package gate passed. Tests cover the exact supplied request and expected prompt; both punctuated and unpunctuated suffix duplication; invalid edits to protected UI passages; intentional source repetition; and structuring while the injected model is unavailable and memory sampling would fail, with zero generator calls. A coordinator integration fixture passes this request through the actual provider, checks one exact-span replacement with surrounding text preserved, explicit no-model diagnostics, no clipboard mutation, no preview and no duplicate shortcut replacement.

The first real-model probe against the added rejection checks still proposed the bad whole-gap edit and was rejected (4840 ms, 21 samples, normal/warning, minimum available 3054436352 bytes, zero swap growth). This is a preserved failed generation test, not successful prompt-quality evidence. It motivated excluding fragmented units from inference. The final exact-example path is deterministic and verified without inference; no second real-model probe is needed or claimed. No microphone or external editor was automated.

The final native Xcode Debug suite passed: 1967 expanded cases across 884 declarations, zero failures. Repository/history checks, 15 CI tooling tests and 3 local-packaging tests passed. The arm64 Release build passed complete Swift concurrency checking.  Physical shortcut replacement still requires user acceptance.

## Installed handoff

Source commit `571c826`. Installed 45.0.16 at `/Applications/Wesley Flow.app` using the existing explicit ad-hoc local signing helper. Strict/deep signature verification passed and the canonical app survived the 15-second launch observation. All preferences were preserved. The old app accepted normal Quit; no force termination or clipboard inspection was used. Temporary signing/package/build copies and the previous application backup were removed after successful launch, while test results and the rejected-model log remain under `Evidence/PromptSpanFix`. The handoff JSON records local structuring and no model invocation for the animated-UI example. Physical editor replacement remains user acceptance; test with a fresh Fn recording and Option+2 after restart.
