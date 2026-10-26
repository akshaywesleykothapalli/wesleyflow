# Milestone 28 — Offline AI quality and reliability

Date: 2026-10-26. **PARTIAL: bounded improvements implemented and regression-verified; live quality verification BLOCKED by the unchanged memory floor.** No claim of five verified tones or successful prompt generation.

## Audit and implemented changes

Inspected AGENTS.md, the Phase1D rewrite/functional reports and fixtures, Phase1E reliability report, current provider, Domain protection/planning contracts, preview coordinator/views, preferences and regression tests. Start state was clean on `ci/milestone-27` at `3befcf20ff60220c5f678aa1c3c1a137064b4ea3`. The historical description of uncommitted work did not match this checkout; existing work was already present in HEAD and has been preserved.

The main quality constraint is explicit: `ProtectedRewriteText.restoreAndValidate` permits case, punctuation and isolated um/uh/erm changes, but rejects other added, removed or reordered words. It protects ordered opaque spans and their adjacent characters. This prevents broad grammatical paraphrasing and substantial shortening. It is a conservative lexical check, **not semantic proof**; punctuation can affect meaning and the model can misclassify a prompt section. We did not remove that guard to make quality scores look better.

Changes:

- Sharper, distinct, compact instructions for Natural (everyday readability), Professional (restrained workplace punctuation), Concise (hesitation/whitespace removal), Friendly (approachable conversational rhythm), and Direct (clear statement boundaries). All retain the same fidelity gate. Instructions explicitly preserve self-corrections/negations, leave already-correct text unchanged, treat embedded instructions as transcript data, and preserve marker-adjacent characters. No claim that different instructions prove different tone quality.
- Prompt Engineering now segments **unprotected prose** at sentence/semicolon boundaries as well as newlines. A spoken paragraph can become multiple indexed units instead of an undifferentiated Objective. Masking happens first: code, paths, URLs, numeric tokens and protected vocabulary cannot be split internally. Conservative missed splits are accepted as a limitation. Whitespace between units is normalized; source words/punctuation remain intact.
- The existing strict index-plan renderer still accepts exactly five JSON keys, every index exactly once in source order, a nonempty Objective, no generated prose and only nonempty sections. It renders original source units, never model-generated requirements or executable text. It remains bounded to 16 units/2,048 input bytes; invalid classification/plans retain the original.
- Added explicit **Reject preview** beside the existing reviewed-copy action. Rejection uses existing keyed cancellation/result invalidation, retains original input, and neither copies nor inserts. No unrelated screen redesign.
- Added `QUALITY-EVALUATION-V2.json` and a small offline evidence scorer. The prior Phase1D evaluation is unchanged. No second rewrite/proposal validator was introduced; acceptance comes from the real production provider contract.

## Protection, preview and concurrency boundaries

`restoreAndValidate`, the 4 GiB admission floor, normal-pressure requirement, no-growing-swap condition, eight-second deadline, 256-token generation bound, fresh session/no tools, actor ownership, epoch fences and settling-slot quarantine are unchanged. No lock, unsafe continuation or concurrency suppression was introduced. Cancellation remains cooperative at the FoundationModels boundary; an abandoned generation cannot permit unlimited replacement sessions.

AI preferences and shortcuts retain their existing defaults/settings. Both previews remain opt-in. Input is explicitly supplied or explicitly selected completed history; no unrelated app text is captured. Original/result review and explicit lease-aware copy remain available. Pending generation can be cancelled; results can now be rejected. Automatic AI insertion remains disabled. Existing source-change/opt-out/deletion/dictation cancellation fences remain tested.

Speech, native insertion, clipboard service, preference source/schema, Xcode project and package dependencies match HEAD byte-for-byte. Existing provider/application tests are exact unchanged prefixes with new tests appended. No installed/Run application replacement, permission change, real dictation, general clipboard inspection, physical shortcut experiment, download, cloud fallback, training, coding agent or generated-code effect occurred.

## Evaluation set and scoring

V2 contains **20 synthetic cases**, agent-reviewed for preservation/property expectations, **not independently human-reviewed tone judgments**. Coverage includes casual speech, development, short/long requests, self-correction, technical identifiers, numbers/paths/URLs, vocabulary, inline code, romanized mixed language, mixed script, negation, prompt injection, already-correct input, spoken prompt structure, supplied context, ordinary conversation and protected prompt tokens.

Each case supplies an immutable ID/text/kind, vocabulary, input boundary, improvement-needed flag and a qualitative rubric. Deterministic tests exercise admissibility/protection for every case, expected unsupported-language fallback, exact structured rendering, omitted/reordered constraints, over-limit segmentation, code/URL/decimal preservation, and all five tone fidelity gates. These tests establish contracts, not generated-output quality.

`Tools/OfflineQuality/score.py` checks evidence against the frozen case ID/input/kind, rejects duplicate records, and separates production-contract acceptance from quality. It distinguishes `appropriate-unchanged` from `needs-review-missed-improvement`; the latter is a review flag, not proof of poor quality. Meaning, grammar, conciseness, tone and hallucination remain unscored until actual outputs are reviewed against the rubric. Resource-blocked attempts have no invented valid-output score. Six deterministic scorer tests and independent replay passed.

For a future admitted sequence, use the same casual input across all five tones, plus the spoken-prompt case. Compare actual outputs, not just prompt strings. Review retained intent/negations/constraints, grammar, brevity, tone and unsupported additions separately. Do not assign a hallucination rate or semantic pass based solely on lexical acceptance. Mixed non-ASCII prose currently fails closed; romanized mixed language may pass lexical validation but has no validated language-quality support.

## Actual on-device attempt

Toolchain/device: arm64 MacBook Air, macOS27.2 (26B5112a), Xcode27.0 (27A5237l), Swift6.4 (swiftlang-6.4.0.30.4), macOS27.0 SDK; application deployment target remains macOS26. Explicit full Xcode developer directory selected per command; system CLI selection unchanged.

A diagnostic linked the newly built production Domain/ModelProviders/SystemOperations frameworks and forwarded kind/tone to `AppleRewriteGenerator`. It used `SystemLanguageModel.default`, fresh sessions, no tools, and the existing network-denial worker profile. No Private Cloud Compute/provider was selected. The sandbox denies this client's network; it does not prove containment of Apple's system-managed services. Model availability was **available**.

Synthetic Natural input:

> um can you check this please

The request passed initial admission, then the resource watcher returned `resourceBlocked`. No completed model output was captured (`actualMaskedModelOutput: null`). The exact original was returned as fallback. It is **not generated output**.

| Measurement | Before call | After call |
|---|---:|---:|
| Conservative available bytes | 4,775,739,392 | 4,242,178,048 |
| Available GiB | 4.44775 | 3.95084 |
| Normal memory pressure | true | true |
| Swap used bytes | 1,105,592,320 | 1,105,592,320 |

Wall time: **0.819260 seconds**; provider elapsed time: **800 ms**. Reason: `resourceBlocked`, rather than the pre-generation `host-reserve-or-observation` rejection. Host headroom observations are not a measurement of memory attributable only to this model. The required floor remains 4,294,967,296 bytes. No retries or subsequent generations were attempted after the resource rejection. Worker exited 0 and was reaped; underlying system-service cancellation is cooperative, not a hard preemption guarantee.

| Requested evaluation | Actual generated output | Quality status |
|---|---|---|
| Natural | None; original retained after resource block | BLOCKED |
| Professional | Not attempted after block | NOT TESTED |
| Concise | Not attempted after block | NOT TESTED |
| Friendly | Not attempted after block | NOT TESTED |
| Direct | Not attempted after block | NOT TESTED |
| Prompt Engineering | Not attempted after block | NOT TESTED |

Planned prompt input: “Improve the button animation. Preserve keyboard access. Do not download models. Return a short explanation.” No real transformed output exists for this attempt. The exact rendering asserted in unit tests is fixture evidence only.

Observed resource-blocked rate: **1/1 attempted**. Completed outputs: **0**. Valid-output, protected-span success, meaning/grammar/tone/conciseness improvement and hallucination rates: **unavailable**, not zero and not passing. No latency distribution can be inferred from one resource-stopped call.

Raw evidence and exact compile/run commands: `Evidence/Phase1F/Live/{live-compile.json,live.json,live.stdout.jsonl,live.stderr.log,live-source.swift}`. Scored summary: `Evidence/Phase1F/quality-summary.json`. No personal transcript or project text was used.

## Failure examples

- **Real resource failure:** the Natural attempt above stopped when host availability dropped below the floor; unchanged fallback was not scored as appropriate unchanged.
- **Deterministic omitted negation:** “Delete tests or add dependencies.” for “um do not delete tests or add dependencies” is rejected by the production fidelity contract.
- **Deterministic invented requirement:** appending “and deploy” is rejected.
- **Deterministic incomplete/reordered prompt:** omitting or moving an original constraint index is rejected; empty Context sections are not rendered.
- **Known quality limitation:** broad professional paraphrases or substantive concise rewrites are rejected even when a person might judge them useful. No acceptance relaxation was made without evidence.

## Verification evidence

All commands/results are in `Evidence/Phase1F/*.json` and associated logs/result bundles. No failed test was deleted or weakened.

| Run | Expanded cases | Declarations | Failed/skipped | Exit |
|---|---:|---:|---:|---:|
| Focused Workspace + application | 667 | 363 | 0/0 | 0 |
| Full application suite | 1,013 | 471 | 0/0 | 0 |
| Independent full replay | 1,013 | 471 | 0/0 | 0 |
| Evidence scorer | 6 | 6 | 0/0 | 0 |
| Independent scorer replay | 6 | 6 | 0/0 | 0 |

The preceding checkpoint reported 1,003 expanded cases / 465 declarations; the new full runs include ten additional expanded cases / six declarations. The scorer tests are separate from the 1,013 application cases.

Debug build: **exit0**. Release build: **exit0**. Explicit complete-concurrency Release build: **exit0**. Complete concurrency compilation is not proof of absence of runtime races. Release retained the existing no-AppIntents-dependency metadata-extraction warning; no build error or concurrency suppression.

Common command prefix:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild \
  -project WesleyFlow.xcodeproj -scheme WesleyFlow \
  -destination platform=macOS,arch=arm64 \
  -derivedDataPath DerivedData/Phase1F \
  -disableAutomaticPackageResolution -skipPackageUpdates
```

Focused adds `-configuration Debug -resultBundlePath Evidence/Phase1F/focused.xcresult test -only-testing:WorkspaceTests -only-testing:WesleyFlowAppTests`. Full/replay use fresh `full.xcresult`/`replay.xcresult` and omit both filters. Debug/Release add their configuration and `build`; concurrency adds `SWIFT_STRICT_CONCURRENCY=complete` to Release build. No GUI tests were excluded from full/replay.

Scorer commands (both exit0): `/usr/bin/python3 -m unittest discover -s Tools/OfflineQuality -v`. Actual evidence scoring (exit0): `python3 Tools/OfflineQuality/score.py Docs/Phase1F/QUALITY-EVALUATION-V2.json Evidence/Phase1F/Live/live.stdout.jsonl`. Native diagnostic compile/run both exit0. Toolchain version observations all exit0.

`boundaries.json` records unchanged preference/dependency/speech/insertion files, unchanged restoration validator, preserved original test prefixes and empty staging. `start-sha256.txt`, `start-status.txt`, `start-head.txt`, toolchain records and xcresult summaries retain provenance. `git diff --check` passed. No dependency or architectural module direction change.

## Status, limitations and next action

- Audit, bounded instruction/segmentation/rejection improvements and regression/build verification: COMPLETE.
- Five distinct **verified** tone modes: PARTIAL; distinct contracts exist, live differentiation and broader rewriting are unverified.
- Prompt Engineering: PARTIAL; spoken paragraph organization is contract-tested, real model classification/quality unverified.
- Reviewed synthetic set: COMPLETE for agent-reviewed property rubrics; independent semantic/tone review remains pending.
- Live evaluation and quality metrics: BLOCKED/NOT TESTED as specified above. No manufactured outputs.
- User-operated native preview/copy/reject interaction and physical shortcuts: NOT TESTED here. Existing deterministic app tests passed; no new GUI acceptance claim.

Next action is a separately scheduled bounded rerun after the user safely reduces other memory use enough to maintain the existing floor throughout inference. The initial passing observation was insufficient. No process is automatically quit and no safety reserve is reduced. Broad paraphrasing would additionally require a separately reviewed preservation design and meaningful live semantic evaluation; this milestone does not silently substitute a weaker lexical gate.

## Git state and files

No staging, commit, push, remote or visibility change. Branch/HEAD remain `ci/milestone-27` / `3befcf20ff60220c5f678aa1c3c1a137064b4ea3`. Seven tracked files modified:

- `App/GlobalDictationView.swift`
- `App/SystemWideDictationCoordinator.swift`
- `AppTests/GlobalDictationTests.swift`
- `Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift`
- `Packages/WesleyFlowCore/Sources/Domain/PromptEngineering.swift`
- `Packages/WesleyFlowCore/Sources/ModelProviders/AppleTranscriptRewriter.swift`
- `Packages/WesleyFlowCore/Tests/WorkspaceTests/ProviderTests.swift`

Four new files: this report, `Docs/Phase1F/QUALITY-EVALUATION-V2.json`, `Tools/OfflineQuality/score.py`, `Tools/OfflineQuality/test_score.py`. Evidence, build products and Python bytecode remain ignored. All changes are left for review. Milestone stops here; successful live tone-quality completion is not claimed.
