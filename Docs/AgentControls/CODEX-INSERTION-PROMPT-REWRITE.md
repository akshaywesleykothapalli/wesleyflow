# Codex insertion and prompt rewriting — 45.0.15

The supplied 45.0.14 diagnostics identify `com.openai.codex`, not the separate ChatGPT app. Speech completed successfully. Initial insertion was DISPATCHED_UNVERIFIED, no verified anchor existed, and the Option+1 provider was not requested. The user reported unchanged text and explicitly authorized a Codex-only guarded clipboard paste route. They also chose Option+2 rewriting and structuring the request without invented requirements.

## Delivery

Codex previously advertised writable selection metadata but had direct initial AX replacement disabled. Native targets opted into clipboard-free Unicode delivery, and this attempt exhausted the 1500 ms verification budget without the expected readback. Dispatch alone does not establish delivery, nor do these diagnostics establish why Codex did not consume the events.

Codex now selects the existing guarded paste service before any Unicode dispatch. It requires complete original text and selection, exact target identity and a safe clipboard snapshot. It publishes once, dispatches one paste and verifies the complete expected document under the existing deadline. Verified delivery restores the original clipboard if ownership remains; a newer external clipboard copy is preserved. Uncertain delivery retains the backup for explicit recovery, prevents another clipboard transaction and never sends a second paste or Unicode fallback. Snapshot failure refuses delivery rather than trying the known-unverified text route. Other app routing, Notes direct insertion, Terminal exclusions, ASR and declined AX tree activation are unchanged. No script inspected/automated the Codex or ChatGPT UI.

Release builds now retain the existing bounded metadata-only capture/insertion/rewrite diagnostics, rather than empty Debug-only traces. They contain codes, lengths, ranges and timing, not field/transcript content.

## Option+2

On-device AI now edits prose passages for a clearer request, and the app owns sentence order, headings and fixed spans. A narrow explicit request preamble can be removed. Leading recognized action verbs are protected so a request cannot silently become just a problem statement. Explicit constraint sentences beginning Keep/Preserve/Do not/Don't/Never/Without/Constraints remain exact. Names, dictionary terms, code and quantities remain app-owned spans. The existing observable negation, modality, speaker and quantity checks also apply; these are not proof of semantic equivalence or complete factual preservation.

Global editable passage indices map back to their original unit and local passage. Missing edits retain source passages. Unknown/duplicate indices, invalid spans, extra lines, changed fixed content and incomplete reordered unit plans are rejected. App-owned layout uses existing source cues for Objective/Context/Requirements/Constraints/Expected output, omits empty sections and keeps source order. It may leave a short request under Objective only. The explicit local formatter remains extractive. There is no silent model-failure fallback: rejected generation keeps the original field. The coordinator independently revalidates restored prompt text before one exact-span replacement. Memory reserves, 8-second deadline, cancellation, single generation lease and replacement-anchor checks remain unchanged; response transport is capped at 512 tokens.

## Verification and iteration evidence

The first prototype combined model-generated section indices and wording edits. Real probes returned duplicated/missing indices (6679 and 6283 ms) and were rejected. A positional prototype still omitted a unit (3689 ms), also rejected. A prose-only prototype passed structural checks in 5092 ms but changed an action into a statement; review caught this, leading to protected actions and immutable constraints. Logs of these failures are retained, not counted as successful prompt improvement. The diagnostic initially checked safe retention rather than successful generation; its opt-in prompt assertion now requires rewritten output and checks the leading action, retained constraint and negation.

The final bounded network-denied local-model probe produced:

> ## Objective
> Check the save button because it is not working.
>
> ## Constraints
> Keep the current layout.
>
> ## Expected output
> Return a short report.

Input began “I want you to check …”. Provider generation took 4129 ms, with 19 samples, normal/warning pressure, minimum available 3059040256 bytes and no swap growth. This is one synthetic run, not a universal model-quality guarantee. No audio or external editor was used. Deterministic package checks passed. New fixtures cover guarded paste selection, refusal without original readback/clipboard backup, uncertainty retaining a backup without retry, prompt fact/marker/negation/index checks and actual-provider/injected-model Option+2 replacement of one dictated span with surrounding text preserved and duplicate invocation refused.

The final native Xcode Debug run passed 1963 expanded cases across 880 declarations, zero failures. Actor-checked focused checks passed. Repository/history checks, 15 CI tooling tests and 3 local-packaging tests passed. The arm64 Release build passed complete Swift concurrency checking.  Physical Codex paste and after-insertion AX replacement remain user acceptance. No settings UI changed.

## Installed handoff

Source commit `83d586a`. Installed 45.0.15 at `/Applications/Wesley Flow.app` with the existing explicit ad-hoc local signing helper. Strict/deep signature verification passed and the canonical app survived the 15-second launch observation. The previous app accepted normal Quit; no force termination or clipboard inspection was performed. All preference values were preserved, including grammar mode and `lastInsertion`. Temporary app/build/package caches and the previous app backup were removed after successful launch; evidence logs and result bundles remain. Physical Codex insertion/replacement is still unverified and requires a fresh user Fn recording after restart, followed by Option+1 or Option+2 in the same field.
