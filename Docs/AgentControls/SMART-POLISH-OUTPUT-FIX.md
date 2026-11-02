# Smart Polish output correction — 45.0.12

The user reported Option+1 “invalid AI output” and supplied the non-sensitive example “I said this is a chuck up, it's working or not.” The original rejected model response was not captured, so its exact edit is unknown. The prior driver asked for free-text copyediting while the Domain contract rejected changed/reordered content words, markers and protected boundaries. Ordinary model paraphrasing could therefore be rejected even when readable.

## Change

Option+1 now asks the on-device model for a guided typed edit plan: token positions to capitalize, isolated um/uh/erm positions to remove, and positions for commas, full stops or questions. It does not ask the model to reproduce marker strings or compose replacement prose. The model receives readable source context and numbered tokens; opaque spans appear only as protected placeholders. The pure Swift IndexedPolishText renderer constructs output from the original masked tokens.

Only whitelisted operations apply. Protected spans and arbitrary word deletion have no authority; invalid ranges, duplicate entries, conflicting punctuation and oversized edit arrays are rejected. Word order, content words, contractions, negation and repetition remain subject to the unchanged ProtectedRewriteText gate, including the coordinator's final restored-text check. Code, paths, numbers and dictionary overrides remain opaque and exact. Marker boundaries were not relaxed. Boundary fillers are retained when deleting them would expose a protected span; all-filler requests remain unchanged rather than producing empty output.

A first prototype real result kept its word ledger but incorrectly placed a full stop inside “or not.” That was a stylistic failure despite passing the old fidelity check and is not claimed as acceptable polish. The renderer now refuses newly suggested boundaries inside common unfinished phrases, before negation/coordination, or after a nonterminal auxiliary/contraction. Capitalization applies only at an eligible start, a sentence/newline boundary or the pronoun i; accepted new sentence endings capitalize the following eligible token. These are conservative mechanical checks, not a complete grammar or semantic proof. An intermediate deterministic run failed before newline-case handling was completed; the corrected suite passed.

The model may leave an already formatted input unchanged. It cannot guess a replacement for “chuck up,” reorder “it's working or not,” or remove content words. This matches the existing UI's punctuation/capitalization/filler-only Smart Polish scope. No semantic rewrite or hidden deterministic fallback was added.

The workflow remains Fn → insertion → Option+1 → validate and replace the last own span. No next-recording arming, preview, clipboard-copy fallback or new mode was introduced. Option+2, speech recognition, romanisation, resource budgets, cancellation/expiry, original editor binding, exact-span verification and single-use replacement remain.

## Verification

Actor-checked deterministic speech/Unicode/audio/Agent/provider tests passed. New tests cover the supplied example; protected names/code/paths/numbers; contractions and repeated negations; newline and filler behavior; malformed plans; no “or. not” split; and sentence capitalization. An app integration fixture uses the actual AppleTranscriptRewriter with an injected edit-generating model and warning-state memory source. It validates restoration through the coordinator, replaces only the dictated range, preserves surrounding text and clipboard contents, opens no preview and prevents a second replacement.

Real on-device synthetic checks used production contracts, networking denied, and all existing resource checks active:

- Initial prototype: rewritten after 4,278 ms, but bad “or. not?” punctuation. This prompted the boundary correction; it is not final acceptance.
- Supplied example after correction: **unchanged**, accepted by both fidelity validations after **2,779 ms**. No invalid-output error. The wording was not rewritten.
- Rough sample “um please check this it is not done”: **rewritten** as “Please check this it is not done” after **3,931 ms**. This proves real filler removal and capitalization, not an added sentence boundary/final full stop. Eighteen observations were normal, minimum available bytes 3,495,821,312, swap growth zero.

Physical keyboard/microphone capture and external editor replacement were not automated. Full native/build/packaging and installed handoff outcomes follow when complete. Temporary app/build copies will be removed after verified installation.

Final full native verification: **862 declarations / 1,944 expanded cases passed**, zero failures. Release with complete concurrency checking passed. Repository checks passed; CI helper tests 15/15 and local signing/packaging tests 3/3 passed. No ordinary speech, resource policy or prompt contract was weakened to obtain these results.
