# Grammar and wording mode — 45.0.13

The supplied 45.0.12 attachment contained speech capture/transcription telemetry, not AI-generation/replacement results. It confirmed successful English recognition but could not establish why the shortcut left text unchanged. The user then explicitly chose grammar and wording improvement, while preserving meaning, names, numbers and negation, and supplied “This is a checkup if it's working or not.” This supersedes the earlier cleanup-only scope for their selected Option+1 mode.

## Behavior

Smart Polish now offers **Improve grammar and wording** and **Keep original wording**. Legacy settings and requests default to cleanup; the installed user's grammar choice is set explicitly during handoff. Normal Fn dictation, Telugu ASR/romanisation and Option+2 remain unchanged. The workflow is still dictation → insertion → Option+1 → replacement of that same span.

Grammar mode uses the same on-device model and one generation lease, but requests complete rewritten editable passages. The app owns protected-name/dictionary/code/quantity markers and reconstructs those fixed spans rather than asking the model to copy them. Common grammatical starts such as “This” are no longer automatically frozen as proper names in grammar mode; explicit dictionary terms still take priority. Cleanup retains its original protection and word-order rules. Grammar mode permits prose whitespace/punctuation boundaries around fixed spans; operators and protected contents remain checked.

The grammar checks compare numeric/spelled quantities, asserted negation, relative-day terms, speaker categories, modality and risky symbols, and reject introduced capitalized names, excessive shortening/expansion, foreign prose, marker injection and meta-explanations. Fixed spans retain exact text and order. These are observable fidelity checks, not a proof of semantic equivalence or complete named-entity recognition. Model instructions require the same meaning, tense, original ambiguity and point of view. Grammar rewriting is English-oriented; the existing language/admission checks remain. No source/file/project context is supplied beyond the dictated span and existing protected vocabulary.

Literal negation counting was too strict for the supplied sentence: optional “or not” inside an if/whether question does not assert that the subject is false. The narrow correction permits that simplification without crossing commas/sentence/paragraph boundaries. It still rejects dropping “do not”, “never”, “without”, nonconditional alternatives, or changing a positive question to a negative one. Unit cases exercise both accepted and refused forms.

A prototype model self-rating repeatedly abstained. It was removed as an unreliable gate: it is neither proof of meaning preservation nor execution authority. The concrete candidate is instead subjected to independent host checks. Backend uncertainty remains an explicit original-retained outcome if a provider raises it. Grammar replies are capped at 512 response tokens; cleanup/prompt retain 256. The 8-second timeout, 250 ms observations, 2 GiB bounded-rewrite reserve, warning/critical distinction, no swap growth and single outstanding request remain. Agent/heavy-model limits are unchanged.

## Visible results and diagnostics

Dictation now retains the last shortcut outcome after the transient pill disappears, including a clear unchanged message. Failures retain their existing persistent detail. The result/error area provides combined dictation **and AI shortcut** diagnostics, avoiding the previous speech-only copy. Release builds record the model result state rather than retaining notRequested after a completed request. These diagnostics contain metadata, not transcript/model text. A new Fn recording/shortcut clears stale outcome state; changing style cancels pending work. History and original dictation records are preserved.

## Verification

Actor-checked deterministic speech/Unicode/audio/Agent/provider checks passed. Tests cover the exact supplied rephrase, unchanged cleanup rejection of wording changes, dictionary/names/code/quantity retention, introduced facts/negation/speaker/modality refusal, passage-index/marker bounds, uncertainty, conditional alternatives and asserted negatives. App fixtures use the real rewrite provider with an injected model, prove grammar text reaches a single exact-span replacement, and check persistent unchanged results after HUD dismissal, combined AI telemetry, and backward-compatible settings decoding.

The first two live grammar prototypes returned unchanged/meaning-uncertain (4,412/4,240 ms); these were not counted as success. Subsequent concrete candidates were correctly held by the then-overly-literal negation check (3,847/3,846 ms). The opt-in diagnostic captured only the supplied non-sensitive synthetic candidate in test code; no production transcript logging was added.

After the conditional-negation correction, a real on-device request returned **rewritten in 4,305 ms**: “This is a checkup to see if it's working.” Both production fidelity validations passed. Twenty resource observations included normal and warning, minimum available bytes 2,900,606,976, maximum swap growth zero; process networking was denied. The test explicitly required rewritten and changed text. This proves this example actually changed, not merely that a rejection test passed.

Final native verification: **871 declarations / 1,953 expanded cases passed**, zero failures. Release with complete concurrency checking passed. Native pages rendered in both appearances with grammar mode configured, without speech capture. The initial Smart Formatting viewport was visually inspected; the lower style row and new result banner were not separately scrolled/snapshotted. CI helper 15/15 and local packaging 3/3 passed; repository checks passed. Physical keyboard/microphone and cross-app replacement remain user-operated acceptance, not scripted verification. Installation results follow below.

## Installed handoff

Installed and reopened **45.0.13** at `/Applications/Wesley Flow.app` after old identified Wesley Flow copies accepted normal Quit. Strict/deep signature verification and a 15-second launch-survival check passed. The user's explicit `polishStyle=grammar` selection was written through CFPreferences only after the old app quit; every other existing preference was checked equal after launch. `formattingShortcutAction` remains `lastInsertion`. No history/model changes, clipboard access or forced termination occurred.

The temporary prepared app, previous Applications backup and both temporary build caches were removed after verified launch. Logs/native result bundles remain under ignored `Evidence/GrammarPolishFix`. Implementation commit: `0fe8a36`; metadata-only handoff provenance is `Evidence/GrammarPolishFix/handoff.json`. The original strict cleanup style remains selectable.

User acceptance uses a fresh Fn recording after restart, waits for insertion, then presses Option+1 without moving/editing the original target. The existing span/identity/freshness checks remain mandatory. The recorded real test proves grammar generation and validation; physical editor replacement remains user-operated acceptance. Last outcomes stay visible in Dictation and the combined diagnostic button includes AI-generation/replacement metadata.
