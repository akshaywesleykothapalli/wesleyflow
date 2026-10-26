# Milestone 31 — Integration and CI readiness

26 October 2026. **Local integration verified; local checkpoint prepared. Hosted CI PENDING. No push, PR, merge, release, visibility change or paid-runner setup.** No new application functionality was added during this milestone.

## Starting Git state

- Branch: `ci/milestone-27`, HEAD `3befcf20ff60220c5f678aa1c3c1a137064b4ea3`.
- Local main and authenticated remote main: `b90976c305cb0eb5a32a1658cbe0408f3d8fe2b8`.
- Nine modified application/test files and 17 untracked milestone28–30 files; staging empty. CI had one existing local commit, not published. Start snapshot covered277 versionable files.
- Read AGENTS.md; inspected local/remote history, status, staged state, repository-local Git identity/configuration, workflows, source and reports. A normal fetch confirmed no unexpected remote work. No reset, stash, history rewrite or discarded file.
- Created local branch **`feature/milestone-31-integration`** from the preserved CI commit, carrying all dirty files. `ci/milestone-27` itself remains at its original commit; main remains unchanged.

Authenticated user ID255148005/login `akshaywesleykothapalli` matches the configured author. New commits use **Akshay Wesley Kothapalli <255148005+akshaywesleykothapalli@users.noreply.github.com>** for author and committer. Historical identities/copyrights are unchanged; no co-author trailer or promotional watermark was added.

## Combined phase audit

| Area | Integration result |
|---|---|
| Shared provider | Five tone cases, preview kinds and four-argument generator dispatch coexist. Prompt unit extraction uses the same Domain protection contract. No duplicate model provider or alternate proposal validator introduced. |
| Concurrency/cancellation | Single provider slot/epoch/settling quarantine preserved. Coordinator token/source/opt-out/close fences retained. Shortcut metadata bridge does not move AppKit state into C callbacks. Sleep cancellation and wake epoch fencing coexist with preview rejection. |
| Shortcut ownership | One registrar owns exclusive native refs; disable/re-registration removes old refs/handlers/observers. Fn dictation monitor remains separate and unchanged; right-Option conflict policy retained. |
| Settings | Existing opt-ins/defaults, Codable persistence and preference store unchanged. No new schema migration or automatic feature enablement. |
| Memory | Production4GiB floor/normal-pressure/no-growing-swap guard unchanged. Model Lab's separate weight+runtime+reserve policy is not substituted for Apple admission. No live inference or new host-headroom probe here. |
| Clipboard | Preview only; explicit Copy still uses the existing lease-aware path. No clipboard broker, target insertion, Terminal typing or AX-tree activation changes. |
| Voice | Speech capture, dictation monitoring, deterministic formatting, insertion services and history logic match task-start sources. Existing regression suite retained. |
| Targets/dependencies | Shared scheme includes all current tests; local package direction remains Domain-first. No external Swift dependency, project resource, entitlement or signing change. |
| Research | Five V3 supplements remain training-ineligible pending independent semantic review. Frozen V1/V2, cached model and existing data untouched; no training or generated-source effects. |

**No confirmed application-source integration defect was found.** All App/AppTests/Packages files match milestone31 task-start hashes. No unrelated refactor was made. Older milestone reports retain their historical “uncommitted/no push” status; this integration report records their later checkpoints.

## Confirmed CI/documentation gaps corrected

1. The new six-case offline evidence scorer was not in the workflow. The repository lane now executes it explicitly.
2. The old999-case application minimum and143-test Model Lab minimum were stale. They are now **1,021** and **152**, respectively. A result-tree gate additionally requires all12 new quality/shortcut regression method IDs to be Passed; a high total cannot conceal a skipped new test.
3. Workflow policy checks did not require the named build/test commands to remain present. They now reject accidental omission; four new CI helper tests cover these integration guards. No old assertion was removed or weakened.
4. New research snapshots needed explicit attribution/checksum coverage. Third-party notices and required Qwen3 license/provenance checks were extended. Two exact pinned model-card paths retain upstream Markdown whitespace through `.gitattributes`, like the existing LORA snapshot. No source/card bytes were sanitized, no broad whitespace or secret-scanner exemption was added.

Milestone31 changed seven pre-existing non-application files plus this new report: workflow, three CI helper/test files, CI baseline documentation, notices and attributes. The other270 pre-existing versionable files are unchanged. The application changes committed below are the already-implemented milestone28/29 work, not new functionality added here.

## Why999 versus1,025

Milestone27's local suite had1,003 expanded cases. CI excluded four specific rendering/window/geometry methods, yielding **999**. That number was a lower bound, not an `only-testing` selection or fixed999-case list.

Milestones28/29 added22 expanded cases. The current unfiltered suite has **1,025 cases /477 declarations**. The same four exclusions produce **1,021 cases /473 declarations**. Actual updated CI selection passed and its result tree confirmed all12 new quality/shortcut methods passed, including the non-displayed NSPanel construction/property test. No new deterministic regression is unintentionally excluded. Native key delivery, shown-window focus/appearance, physical Accessibility and microphone/model acceptance remain manual; constructing a fixture object is not physical acceptance.

The four retained exclusions are listed in `Tools/CI/run_checks.py` and `CI-BASELINE.md`; there are no whole-suite exclusions. A regression also fails if Xcode silently executes one of those excluded methods. Exact Swift Testing identifiers include their parentheses.

## Complete local verification

| Check | Actual result | Exit |
|---|---|---:|
| Full application scheme |1,025 passed /477 declarations, zero failed/skipped |0|
| Independent unfiltered replay |1,025 passed /477 declarations, zero failed/skipped |0|
| Exact updated CI selection |1,021 passed /473 declarations; four deliberate exclusions; all12 new methods passed |0|
| Exact CI Model Lab lane |152 Model Lab tests +7 resource-boundary tests |0|
| CI helper/security mutation tests |13 passed |0|
| Offline quality scorer |6 passed |0|
| Debug build |Succeeded |0|
| Release build |Succeeded |0|
| Complete-concurrency Release |Succeeded |0|
| Workflow lint |yamllint strict, Ruby/Psych parse and policy checks passed |0|
| Repository/license/artifact/history checks |Passed; no confirmed credential issue |0|
| Candidate scan including untracked files |277 candidates before this report; no secret-pattern/forbidden-artifact finding |0|
| Git whitespace checks |Passed, including each staged manifest |0|

A separate **source-only temporary copy** contained no cached weights, MLX environment, prior Evidence, prepared output or build artifacts. A fresh strict Swift validator build followed by152 Model Lab,7 resource-boundary,6 scorer and13 CI helper tests all passed there. This verifies that the new research checks do not depend on ignored local files. Replay means a separate process/result bundle, not independent human quality review.

Toolchain: full Xcode27.0 beta27A5237l, Swift6.4, SDK27.0, arm64 macOS27.2. Explicit `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`; global CLI selection unchanged. Actual build settings: Swift6, deployment26.0, ad-hoc `CODE_SIGN_IDENTITY=-`, Manual signing, no development team or signing entitlement file. No signing certificate/token/profile supplied. No external Swift packages; automatic resolution/updates disabled.

Exact argv/timestamps/exits and logs are in ignored `Evidence/Milestone31/`: `full`, `replay`, `ci-selection`, `model-lab`, `helpers`, `scorer`, `yaml`, `repository`, `debug`, `release`, `concurrency`, plus result summaries and `source-only-check.json`. Common unfiltered command:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild \
  -project WesleyFlow.xcodeproj -scheme WesleyFlow \
  -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Milestone31 \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 \
  -configuration Debug -parallel-testing-enabled NO \
  -resultBundlePath Evidence/Milestone31/full.xcresult test
```

Replay uses a fresh `replay.xcresult`. Debug/Release use their configuration and `build`; concurrency adds `SWIFT_STRICT_CONCURRENCY=complete`. CI selection/model-lab use `/opt/homebrew/bin/python3.11 Tools/CI/run_checks.py test|model-lab --output <fresh-directory>`. Python helper/scorer commands use unittest discovery in their respective directories. Lint uses `yamllint --strict -d '{extends: relaxed, rules: {line-length: disable}}' .github/workflows/ci.yml`. The existing AppIntents metadata warning remains; passing compilation is not a runtime race proof.

## Hosted CI compatibility and account assessment

The workflow retains **`runs-on: xcode-27`**, not `macos-26` or a paid `-xlarge` runner. The published ARM image inventory reviewed at `dd1a667c2b8ff5a9fb907e6087544ec48f0bbc8b` lists Xcode27.0 at `/Applications/Xcode_27.app` with the selected `/Applications/Xcode_27.0.app` alias and macOS27.0 SDK. A default27.1 also exists; the workflow explicitly selects27.0 and preflight fails if actual Swift/SDK/toolchain admission is incompatible. Hosted GA compiler behavior is **not verified** by this local beta build. [Pinned inventory](https://github.com/actions/runner-images/blob/dd1a667c2b8ff5a9fb907e6087544ec48f0bbc8b/images/macos/xcode-27-arm64-Readme.md)

GitHub announced Xcode27 GA on15October; the retained inventory still has a preview banner. The label is ARM-only. Standard private-repository runner documentation lists `xcode-27` with3 M1 cores/7GB RAM; the wrapper limits compiler jobs to2 and serializes tests. No MLX weights or live models are needed. No SDK/toolchain fallback/download is attempted. [GA announcement](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/), [standard runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

Read-only authenticated observations on26October:

- Account plan: **Free**; repository private, default main unchanged; caller has push/admin permission.
- Repository Actions: enabled, allowed actions all. Default workflow token read; cannot approve PR reviews. This workflow further limits permissions to `contents: read`.
- **Zero workflows and zero runs** currently on GitHub; the local CI commit has never been published.
- Repository-filtered October Actions usage API returned `usageItems: []`. This proves no reported usage for this filter, **not remaining account-wide minutes, payment state or budget allowance**.
- Private main branch-protection API:403, “Upgrade to GitHub Pro or make this repository public to enable this feature.” This is a **branch-protection** restriction, not evidence of an Actions execution block. No visibility/plan/protection setting was changed.

GitHub documents included private Actions usage by plan; standard macOS jobs consume the account allowance and may be billed beyond it. Current remaining quota/budget enforcement is unverified and must be checked before publishing. No supported evidence currently establishes that the account cannot schedule standard `xcode-27`; actual scheduling remains pending. No paid runner or spending setting was enabled. [Billing/availability](https://docs.github.com/en/actions/concepts/billing-and-usage), [Free plan allowance](https://github.com/pricing)

Security/cache review: SHA-pinned official checkout unchanged, `persist-credentials:false`, no signing/repository secrets supplied, no OIDC/write permissions, `pull_request_target`, privileged environment, workflow-run trampoline, cross-run cache or artifact upload. Each build uses runner-local temporary files; raw tests/source/private paths are not uploaded or printed by wrappers. The repository job prints only synthetic unit-test names/aggregate scanner results. Runtime/manual tests remain outside hosted CI. Basic pattern scanning is not exhaustive secret detection.

## Reviewed local commits and attribution

All logical manifests were explicitly staged and checked for exact names, hashes, artifacts, secrets and whitespace before commit. Four overlapping quality/shortcut files used hash-verified **index-only** earlier snapshots for the quality commit; current working files were never replaced. The subsequent shortcut commit carries their dependent additions. No blind `git add .`, squash or amended history.

| Scope | Commit |
|---|---|
| Original CI milestone27, preserved | `3befcf20ff60220c5f678aa1c3c1a137064b4ea3` |
| Offline quality —11 files | `9473abe04472986918fc609811854d089cad39ff` |
| Global shortcut safeguards —7 files | `6b5daf99639412f135d6e01611c8b817ca55d886` |
| Research/contract/provenance/notices —14 files | `18d85277723c8d39e42c9b32a37f551f02d230ad` |
| CI integration/report —6 files | Final branch HEAD; immutable SHA supplied in final handoff and `Evidence/Milestone31/ci-commit.json` |

A document cannot contain its own final Git object hash. Resolve this last checkpoint with `git rev-parse feature/milestone-31-integration`; `git log --reverse --format='%H %s' origin/main..feature/milestone-31-integration` gives the exact five-commit publication sequence. Staged manifests/diffs and verified author/committer records are retained locally. The older reports are preserved as historical records rather than rewritten to imply live quality/physical acceptance.

## Excluded files and final working state

Excluded from commits: all `Evidence/`, `DerivedData/`, canonical `Run/` app, model safetensors/weights, adapters/checkpoints, MLX virtual environment/wheels, runtime caches, prepared output, raw screenshots/audio, private transcripts, clipboard backups and machine-local diagnostic configuration. Public metadata/license snapshots and synthetic fixtures are intentionally included and attributed. No general clipboard/private conversation content was read for this audit.

The final checkpoint is intended to leave **no staged, unstaged or untracked versionable changes**. Ignored local evidence/caches remain. Final post-commit status and immutable SHAs are recorded in `Evidence/Milestone31/final-checkpoint.json` and the user handoff; source hashes bind builds to the reviewed application files. Main/original CI refs and remote remain untouched. No existing work is discarded.

## Publication plan — not executed

- Remote: `https://github.com/akshaywesleykothapalli/wesleyflow.git`.
- Proposed remote branch: **`feature/milestone-31-integration`** (absent remotely at inspection).
- Commits: the five ordered checkpoints above, based on remote main `b90976c305cb0eb5a32a1658cbe0408f3d8fe2b8`. Caller push permission and ancestry/name checks support a normal branch-creation push; this is not a pushed/dry-run result.
- Before separate authorization: recheck main/remote branch and account allowance/budget. If remote advanced, review and merge normally on the feature branch, then rerun checks; never overwrite it or force-push.
- After explicit authorization only: normal `git push --set-upstream origin feature/milestone-31-integration`. The push pattern matches `feature/**` and should start **Wesley Flow CI**. No such command was executed.
- Proposed PR into main: **“Integrate guarded AI previews, shortcut reliability and Model Lab research”**. Describe quality/resource and physical limits; link local reports. Do not create the PR until separately authorized.
- Expected jobs/checks: **Repository quality** (Ubuntu) and **macOS deterministic** (`xcode-27`). Require success on the exact proposed revision/PR merge revision, current minimums and named regression gates, Debug/Release/concurrency, Model Lab/resource/provenance/security checks. Inspect actual GitHub check names and logs before configuring protection; do not invent a hosted run URL or mark it green locally.
- Hosted failures caused by plan/budget/runner availability must be recorded with the actual run error. Do not switch SDKs, enable paid runners, expose logs, lower floors or make the repo public to bypass a failure.
- Main protection remains unavailable under the observed plan. Use PR review/check policy manually until supported; only after an actual working hosted job consider required observed checks and force-push/deletion protection. Do not create an impossible approval requirement for a solo maintainer.

Rollback: before publication, retain/hold this branch; main is unchanged. If undoing local integrated changes is separately authorized, use new reverse-order revert commits for the four new checkpoints, preserving original CI/history, and rerun verification. After a future PR merge, use a new rollback PR/revert of the merge (with the correct mainline parent), not a reset or force push. No rollback was executed.

## Outstanding acceptance and resource limits

- **Hosted CI: PENDING**, zero actual server runs. Runner inventory is compatibility evidence, not execution evidence.
- **Physical Option+1/2:** UNVERIFIED for TextEdit, ChatGPT macOS, Codex Desktop and VS Code; user explicitly declined tests in milestone29. Focus, clipboard and wake/sleep acceptance remain manual.
- **Repeated native dictation/insertion:** existing deterministic tests pass; real ChatGPT/Codex repeated acceptance is not established by these builds.
- **Smart Polish/Prompt Engineering live quality:** unverified/resource-blocked in recent attempts. No inference retry, memory-floor reduction or automatic insertion here.
- **Custom model:** cached model/datasets preserved; no successful MLX baseline/training, no genuine adapter produced, revised contracts not independently behaviorally reviewed. Research metadata does not establish numerical compatibility or training fit.
- No macOS26 runtime certification or release/signing acceptance is claimed from this macOS27 local/hosted plan.

Stop after the local integration checkpoint and this publication plan. Separate authorization is required for any push, PR or merge.
