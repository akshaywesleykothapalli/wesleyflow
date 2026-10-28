# Milestone 37R2 — Publication review

28 October 2026. Reviewed accumulated changes from published checkpoint `23caeca630b803fddc2cd007a5159dc9839b71cf` on `feature/milestone-31-integration`. This is a draft review checkpoint, not release acceptance or permission to merge.

## Physical acceptance

The user explicitly confirms ChatGPT dictation 1 PASS, 2 PASS, 3 PASS on 37R2. These are user-operated physical results. No other editor, AI shortcut/replacement, focus-switch edge case, clipboard-recovery edge case, sleep/wake scenario or minimum-OS runtime is marked physically verified by this confirmation. Historical reports preserve earlier failures and pending gates; their opening updates point here. Automatic exact replacement in the affected ChatGPT/WhatsApp editors remains unsupported; use Smart Formatting's explicit manual preview and Copy.

## Reviewed behavior

The cumulative implementation includes bounded read-only focused text capture for explicit manual previews; windowless Option+1/2 in-place routes; default-off opt-in; expiring, single-use verified dictation anchors; exact UTF-16 text/range/context validation; typed readback and bounded settling; original target identity and activation fencing; ordinary one-shot paste without exact original text when editability is affirmed; clipboard payload/ownership validation; cancellation fencing; metadata-only diagnostics; explicit recovery Copy; real audio-energy bars and the requested 37R2 pill labels.

Ordinary paste may be dispatched without independent destination readback. It stays uncertain, retains the bounded clipboard backup and creates no rewrite authority. Repeated use can require explicit recovery or positively observed clipboard supersession. No retry, fixed-delay clipboard restoration, Enter/submission, Terminal typing or accessibility-tree activation was introduced. AI generation and replacement remain separately opt-in and capability-gated; existing memory admission and provider contracts remain. No live inference, model download/training, microphone capture or external-editor automation was performed by this review. No running app was quit, launched or replaced.

## Fresh local verification

Explicit Xcode beta 27.0 / Swift 6.4 / macOS 27 SDK, arm64, macOS 26 deployment target. Raw command/timestamp/exit evidence is ignored under `Evidence/Publication37R2/`.

| Check | Result |
|---|---|
| Full unfiltered suite | 1,256 cases / 578 declarations, zero failures/skips |
| Debug | Passed |
| Release | Passed |
| Complete-concurrency Release | Passed |
| CI helper tests | 13 passed after the guard update |
| Offline quality scorer | 6 passed |
| Synthetic Model Lab | 152 passed with freshly built validator |
| Native resource boundaries | 7 passed |

The earlier 37R2 independent replay (1,256 cases) remains historical evidence, not a second replay claimed during publication. A fresh source build passed the exact hosted selection: 1,252 cases / 574 declarations, zero failures, the same four graphical exclusions, and all 23 named required methods passed. Results are recorded in `Evidence/Publication37R2/hosted-selection/test-summary.json`. Fixtures and builds do not substitute for real editor acceptance.

Review found a stale required CI identifier for the old preview-opening behavior. The current disabled-shortcut HUD method replaces it. The reviewed CI guard now requires the current 1,252-case floor plus named opaque-paste, unsafe-target, no-typing, clipboard-mutation, no-AI-authority, cancellation, publication-mismatch, delayed-readback, expiry, windowless-routing and pill-label regressions. The guard's negative coverage test rejects 1,251 cases. Workflow permissions, pinned checkout, runner, four graphical exclusions and log-upload policy are unchanged.

## Publication hygiene and attribution

Read repository AGENTS.md and milestone/CI reports; the current user request authorizes review, logical commits and feature-branch push despite historical no-commit/no-push milestones. Reviewed source, fixtures, project wiring and documentation. No external Swift dependency, model/provider implementation, model weight, private transcript, recording, screenshot, history database, signing key or generated build output is included.

The root MIT license and copyright remain unchanged. Third-party notices and pinned upstream provenance/license hashes remain intact. New production code uses Apple system frameworks and the existing local package. No copied legacy implementation/assets or new third-party source were identified. User author/committer identity remains Akshay Wesley Kothapalli with the existing GitHub noreply address; no AI co-author trailer, promotional credit or ownership reassignment is introduced.

Changed/untracked candidate contents were scanned before staging for credential patterns and forbidden artifacts; no issues were reported. The repository's tracked-file, reachable-history, license, provenance, workflow and whitespace checks also passed. These bounded checks do not establish exhaustive absence of secrets. Raw logs, build products, model caches and original machine-local evidence remain ignored.

## Commit and remote plan

Keep the accumulated source/tests/project changes together as one buildable reliability commit; shared coordinator and test-file dependencies make reconstructed historical milestone commits misleading. Follow with a CI regression-guard commit and a documentation/physical-acceptance commit. No pre-existing change is discarded, history rewritten or commit amended.

Initial remote feature SHA matches local HEAD at `23caeca630b803fddc2cd007a5159dc9839b71cf`; remote main is `b90976c305cb0eb5a32a1658cbe0408f3d8fe2b8`. [PR #1](https://github.com/akshaywesleykothapalli/wesleyflow/pull/1) is open/draft, head `feature/milestone-31-integration`, base `main`. Use a normal explicit feature-branch push only; recheck remote head and main, retain draft status, inspect new push/PR CI for the exact final SHA, and update PR evidence. No merge is authorized.

This committed report records pre-publication verification. Final commit hashes, remote SHA and hosted conclusions belong to the final handoff and updated PR; older Milestone 32 successful runs are not evidence for this new head.
