# Milestone 33 — Physical acceptance and PR readiness

26 October 2026. **PHYSICAL SHORTCUTS: UNVERIFIED. PR READINESS: READY WITH LIMITATIONS for continued draft review; physical acceptance is not complete. MAIN: UNCHANGED.**

## Repository and scope

Read AGENTS.md, Milestone 32 report, shortcut verification report, permitted-input/preview lifecycle and resource guard. Source branch `feature/milestone-31-integration` remains at `23caeca630b803fddc2cd007a5159dc9839b71cf`; published source matches. Local and remote main remain `b90976c305cb0eb5a32a1658cbe0408f3d8fe2b8`. No application logic, tests, preferences or installed bundle changed. No merge, rebase, force push, remote update, model download/training or global keyboard automation performed.

[PR #1](https://github.com/akshaywesleykothapalli/wesleyflow/pull/1) remains OPEN and DRAFT. Its five commits / 36-file diff and authors match the reviewed Milestone 32 checkpoint. Original CI commit preserved. MIT license unchanged; upstream attribution preserved. No AI co-author trailers found. Existing hosted tracked/history checks passed with no secret/artifact issue categories; model weights and personal transcripts are absent from the reviewed upload. Basic pattern scanning is not exhaustive secret detection.

## User-operated procedure

Do not replace or force-quit an app with active dictation or unresolved clipboard recovery. Use the verified development bundle from Milestone 31 only after safely closing any older instance normally. Do not launch multiple instances. No app was launched or replaced by this milestone.

1. Record existing preview/shortcut settings so they can be restored. In Wesley Flow, enable Smart Polish, Prompt Engineering and Preview shortcuts. Select user-entered input rather than saved history. Enter only: “Please review the sample button animation. Keep keyboard access unchanged.” No external selection is read.
2. To test clipboard preservation, optionally copy a harmless marker such as `WF-acceptance-33` yourself. This replaces your clipboard, so first preserve anything you need. Do not press preview Copy during the test. Check the marker by pasting manually into a disposable scratch document before and after; never paste into a prompt or terminal. No clipboard contents need to be reported.
3. In each application below, focus a blank disposable document/prompt. Press and release Option+1. Confirm one Smart Polish preview opens with the supplied synthetic source and that no text appears or submits in the foreground app. Record whether the original editor retains focus (for example its caret remains active). Then close the preview.
4. Press and release Option+2. Confirm one Prompt Engineering preview, the same authorized source, no insertion/submission and appropriate focus behavior. Close it. Do not press Return or submit any prompt.
5. Repeat each shortcut three times, closing completed previews between activations. Also try a rapid second activation while a preview is pending; verify it does not create another window/session or replace the pending source. If generation is memory-blocked, do not repeat nonempty generation attempts. Clear the Wesley Flow input and test remaining delivery/repetition checks with empty input, recording “No permitted input” instead of model success.
6. If a request remains pending long enough, click Cancel. Record whether original source survives and no delayed result or text appears after cancellation. If it completes too quickly, mark pending-cancellation UNVERIFIED; do not manufacture a slow request or repeatedly retry.
7. Verify the synthetic clipboard marker in scratch space and note focus before/after shortcuts separately from focus intentionally changed by clicking Cancel/Close. Restore prior settings and your own clipboard as needed. Stop on any unexpected insertion or submission; report only outcomes, app names and non-sensitive status, never private contents.

Input authorization matters: selecting text in another app alone is not currently a supported preview-input path. Shortcut delivery and generation are separate results. A resource-blocked model can coexist with successful shortcut delivery.

## Physical test matrix

U = UNVERIFIED, no user observation supplied during preparation. A/B = Option+1/2 correct preview; C = no insertion/submission; D = original focus; E = clipboard; F = cancel/no stale result; G = repetition/no duplicates. The matrix is not populated from unit-test or registration success.

| Application | A | B | C | D | E | F | G | User observation / model outcome |
|---|---|---|---|---|---|---|---|---|
| TextEdit | U | U | U | U | U | U | U | Not performed/reported |
| ChatGPT macOS | U | U | U | U | U | U | U | Not performed/reported |
| Codex Desktop | U | U | U | U | U | U | U | Not performed/reported |
| VS Code | U | U | U | U | U | U | U | Not performed/reported |

Reply format: `App — Option+1; Option+2; input correct; no insertion; focus; clipboard; cancel; repeats; exact non-sensitive model status`. Use PASS, FAIL or UNVERIFIED for each observation. No physical pass or fail is inferred in this report.

## Model observations and safeguards

No model was invoked or availability/resource probe run in this milestone. Current availability, pressure and headroom are therefore UNVERIFIED. Historical successful Apple on-device inference and later resource blocks do not establish present availability. Existing native guard requires normal pressure, at least 4 GiB conservative available memory and no swap growth relative to baseline; no change made. Resource observation/admission failure retains original text and reports resourceBlocked. Single-session/settling and cancellation fences remain. User should record the actual status and stop a blocked generation attempt without automatic or manual repeated retries. Cancellation cannot be marked physically verified without a pending request.

AI previews remain opt-in. Automatic AI insertion is disabled. No cloud fallback, model downloads, training, shell actions or source modifications are introduced. Preview Copy is explicit and excluded from clipboard-preservation testing.

## Hosted evidence and coverage

Both existing runs remain successful:

- [Push workflow 40368220610](https://github.com/akshaywesleykothapalli/wesleyflow/actions/runs/40368220610)
- [PR workflow 40368267339](https://github.com/akshaywesleykothapalli/wesleyflow/actions/runs/40368267339)

Each passed 1,021 expanded application cases / 473 declarations, zero failures; 152 Model Lab, 7 resource-boundary, 13 CI helper and 6 scorer tests; Debug, Release and complete-concurrency builds. Actual ARM image 20261023.0307.1 selected Xcode 27.0, Swift 6.4, SDK 27.0. These results were queried, not rerun or substituted for physical results.

Local full-suite baseline is 1,025 / 477. The four excluded methods are graphical checks for native page appearance, larger text, window geometry and actual control-frame alignment (exact identifiers in Milestone 32 report). Deterministic preview lifecycle regressions remain mandatory. Those four methods passed in the prior local full suite, but hosted CI does not establish their current physical visual acceptance. No source/test changes occurred, so no regression rerun was required or claimed.

## Documentation review and readiness

Milestone 32 report reviewed: contains synthetic/aggregate test evidence, public-style project/commit identifiers and private-repository links; no credentials, personal transcripts, model weights or private source excerpts. No sensitive content identified. Retained locally without a documentation commit to preserve the exact published checkpoint and avoid implying that existing CI applies to a newer commit. This acceptance report also remains local/uncommitted. No push was made.

READY WITH LIMITATIONS means ready to continue draft code review, not accepted for release or approved to merge. Physical cross-app delivery, focus/clipboard preservation, pending cancellation and repeat behavior remain unverified. Live tone quality remains unverified/resource-limited. Repeated ChatGPT/Codex dictation acceptance remains outside this shortcut procedure. Private branch protection remains unavailable on the current plan; no plan/visibility change made. Keep draft status until reviewers explicitly assess these limitations and manual outcomes. No merge performed.

## Commands and final Git state

Read-only checks: `git status --short`, branch/HEAD, remote head query, PR identity/commit/file/check rollup, license diff and commit bodies. Commands succeeded. Tracked worktree and index diffs empty. Only two local untracked reports: `Docs/Engineering/MILESTONE32-HOSTED-CI.md` and this file. No application changes, commits or pushes.
