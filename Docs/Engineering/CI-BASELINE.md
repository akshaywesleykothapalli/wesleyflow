# Milestone 27 — GitHub CI baseline

26 October 2026. Predecessor: `main` at `b90976c305cb0eb5a32a1658cbe0408f3d8fe2b8`.

**Hosted CI: PENDING.** This milestone creates a local reviewed commit only. No push, workflow dispatch, branch-rule update, visibility change or release publication is authorized/performed. Local results below do not establish hosted success.

## Workflow and toolchain

`.github/workflows/ci.yml` runs for pull requests targeting main, pushes to main/feature/**/fix/**/ci/**, and explicit manual dispatch. No path filters hide a required check. Per-PR/branch concurrency cancels obsolete runs; jobs have bounded timeouts.

- **Repository quality**: `ubuntu-24.04`; installed yamllint, Ruby/Psych YAML parsing, nine self-contained CI helper tests, tracked artifact/size/license/provenance checks and redacted basic secret scanning across working-tree files plus reachable commit/blob history.
- **macOS deterministic**: ARM64 `xcode-27` preview runner, explicitly selected `/Applications/Xcode_27.0.app/Contents/Developer`; runs only after repository checks pass. No `macos-latest` or Command Line Tools fallback. Preflight requires full Xcode27.0, Swift6.4+, macOS27+ SDK, ARM64 host macOS26+ and Python3.11+. Missing/incompatible software fails the job before build/test. Two compiler jobs and serial test execution limit resource use.

Official inventory reviewed at runner-images commit `6d35e16176367288d91febefafbd221cb2da6ca1`: [available labels](https://github.com/actions/runner-images/blob/6d35e16176367288d91febefafbd221cb2da6ca1/README.md), [Xcode27 ARM inventory](https://github.com/actions/runner-images/blob/6d35e16176367288d91febefafbd221cb2da6ca1/images/macos/xcode-27-arm64-Readme.md), [Ubuntu24.04 inventory](https://github.com/actions/runner-images/blob/6d35e16176367288d91febefafbd221cb2da6ca1/images/ubuntu/Ubuntu2404-Readme.md). The Mac inventory lists Xcode27.0 build27A266a and SDK27.0; the label is a public preview. This confirms published availability, not actual account scheduling, compiler execution or remaining private-repo minutes. Runtime guards verify the compiler rather than assuming its version from a label. Images/patches can change and preview capacity/stability has no production guarantee; review inventories when updating pins. No toolchain download is attempted.

The local verification lane is Xcode27 beta27A5237l / Swift6.4 / SDK27.0 on ARM macOS27.2. A hosted GA build is not claimed equivalent without execution. Deployment target remains macOS26.0; actual minimum-OS runtime acceptance remains separate.

## Security and log handling

Only external action: `actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803` (reviewed official v6 reference/action metadata, Node24). Pin updates require reviewing the upstream revision and these checks. Checkout fetches history for scanning and sets `persist-credentials: false`.

Workflow permissions are only `contents: read`; no write/OIDC/package/deployment grants, signing certificates, repository secrets, privileged environments, self-hosted runners, `pull_request_target`, `workflow_run`, cache restoration or artifact uploads. Pull request code is executed as untrusted code on ephemeral hosted runners with no supplied privileged secrets. Retain GitHub's approval requirements for external contributors and review workflow/helper changes before merging; a pull request can change its own tests, so a green check never replaces code review.

`Tools/CI/run_checks.py` captures compiler/test/Model Lab output and xcresults into runner-local temporary files, prints only aggregate results/toolchain versions, and uploads nothing. Source lines, matched credentials, transcript contents and absolute personal paths are not printed by the wrappers. Local reproduction uses ignored Evidence/CI directories. Do not enable shell tracing or add raw log/screenshot uploads. Infrastructure/checkout failures can still emit ordinary hosted runner paths; no personal user data is supplied to the hosted checkout. No recordings/private history/clipboard backups enter CI.

Basic secret checks are offline patterns, not an exhaustive credential detector. The exact SHA256 of the unchanged ContextObservationTests negative-test file exempts its isolated private-key header literal, **not its filename or changed content**. Added credentials still fail. No secret values are printed. Artifact checks preserve synthetic datasets/configuration and required source; upstream copyright/license hashes are verified. The existing single upstream Markdown whitespace exception preserves its pinned bytes and is not a secret-scan exception.

## Tests and build commands

The shared Xcode scheme compiles Swift6 app and local Domain/VoiceInput/SystemOperations/Persistence/TaskExecution/Workspace/ModelProviders/CodingAgents modules. There are no external Swift package dependencies to resolve or signing assets to install. Debug, Release and explicit `SWIFT_STRICT_CONCURRENCY=complete` Release builds run separately.

The hosted test command is the existing complete scheme with only these four exact Swift Testing identifiers excluded:

- `WesleyFlowAppTests/GlobalCoordinatorTests/nativePagesInstantiateInBothAppearancesWithoutStartingSpeech()`
- `WesleyFlowAppTests/GlobalCoordinatorTests/compactPagesAccommodateLargerTextWithoutExpandingTheMinimumWindow()`
- `WesleyFlowAppTests/GlobalCoordinatorTests/compactDefaultHomeAndWindowUpdatesPreserveUserGeometryWithoutVoice()`
- `WesleyFlowAppTests/SettingsRowLayoutTests/actualNativeControlFramesShareTrailingEdge()`

These native rendering/window/geometry tests belong to the local graphical verification lane. Other fixture-backed coordinator, repeated insertion, cancellation, clipboard, history/recovery, approval, proposal, transport/SSE, formatting, preference and AI-preview boundary tests remain selected. Synthetic audio buffers are allowed; no microphone capture or native Accessibility input automation is performed. View/binding objects used by other deterministic tests are not a claim of visual/VoiceOver acceptance.

The wrapper rejects an empty/reduced test selection (minimum 999 expanded passing cases, zero failures) and inspects the result tree to fail if one of the four excluded GUI methods actually executed. Exact parentheses matter: the first local trial omitted them and Xcode silently ran all 1,003 tests. That trial passed the full suite but **did not validate the CI selection**. The corrected identifiers and result-tree regression prevent that silent mistake from being presented as hosted success. Future deliberate baseline changes must be reviewed; do not lower the floor to hide a failure.

Model Lab CI uses Python standard-library tests and a fresh strict Swift bridge to the real production validator. No MLX/pip requirements, model weights, Ollama daemon, Apple Intelligence session, training, remote model provider, asset download or generated code execution. `build_validator.py` now honors an explicitly supplied DEVELOPER_DIR while preserving its previous local fallback. No inference/provider behavior changes.

## Local reproduction

From the repository root, select a compatible full Xcode:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
python3 -m unittest discover -s Tools/CI/tests -v
python3 Tools/CI/repository_checks.py
python3 Tools/CI/run_checks.py preflight
python3 Tools/CI/run_checks.py test --output Evidence/CI/my-test-run
python3 Tools/CI/run_checks.py debug --output Evidence/CI/my-build-run
python3 Tools/CI/run_checks.py release --output Evidence/CI/my-build-run
python3 Tools/CI/run_checks.py concurrency --output Evidence/CI/my-build-run
python3 Tools/CI/run_checks.py model-lab --output Evidence/CI/my-build-run
```

Use a **fresh test output directory** for each test invocation; existing xcresult bundles are preserved, never overwritten. Raw logs/summary JSON stay in those ignored directories for local troubleshooting. Python3.11+, Ruby/Psych and Git are needed. YAML lint uses `yamllint --strict -d '{extends: relaxed, rules: {line-length: disable}}' .github/workflows/ci.yml`; the selected Ubuntu inventory includes it. Local lint was run using pinned yamllint1.38.0 in a disposable temporary virtual environment, without global package changes. No new runtime dependency was added to the app or Model Lab.

For the full local graphical test lane, use README's unfiltered shared-scheme test command on a logged-in Mac. Keep actual microphone accuracy, native global shortcuts/Secure Input, Accessibility focus/insertion, three repeated sessions in TextEdit/ChatGPT/Codex, clipboard recovery, VoiceOver/window appearance, and real Apple on-device quality/resource tests in explicit user-operated/manual gates. See the [voice acceptance checklist](../Phase1E/CORE-VOICE-RELIABILITY.md). Never submit prompts or infer paste success from dispatched keys. Existing unresolved native/AI gates remain unresolved.

## Feature branches, review and safe merge

```sh
git fetch origin
git switch main
git merge --ff-only origin/main
git switch -c feature/short-description
# Make focused changes, run local checks, inspect diff and commit explicitly reviewed paths.
```

Keep secrets, raw evidence, models and personal captures outside Git. Review source, tests, license/provenance changes and the complete staged diff; workflow/helper changes deserve security review. Do not stage everything blindly. After separately authorizing a push, push the feature branch normally and open a pull request to main. Never force-push main or delete it. This milestone itself does not push a branch or open a PR.

Before merging: inspect the actual hosted check results for the exact proposed revision, review the diff, confirm manual acceptance where the change requires it, and ensure main has not diverged unexpectedly. Update the branch normally/merge current main and rerun checks as needed; do not overwrite unexpected remote work. Merge through the PR after checks pass, using a normal merge or reviewed squash. Keep a solo-maintainer recovery route until CI is established; do not require a reviewer who cannot exist or an unobserved check name.

## Main protection assessment

Authenticated read-only inspection on 26 October: repository remains private, main unchanged at predecessor, Actions enabled. Both branch-protection and ruleset APIs returned403 with GitHub's private-repository plan/feature restriction. No protection was enabled/disabled, no paid plan changed, and no visibility change made. GitHub [documents private protected-branch availability](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches) for Pro/Team/Enterprise plans.

When supported **and after the first successful hosted run**, require the observed checks corresponding to `Repository quality` and `macOS deterministic`, require up-to-date tested PR changes, disallow force pushes and branch deletion, and prefer PR merges. Select actual observed check names in GitHub rather than enforcing guessed names now. Require an independent approval when another reviewer is available; do not permanently lock a sole maintainer out with an impossible self-approval rule. Until protection is available, follow this documented PR/check/review policy manually; it is not server enforcement. Do not make the repository public just to gain enforcement.

## Verification record and status

- YAML lint: yamllint1.38.0, exact workflow invocation, exit0; Ruby/Psych syntax and permission policy passed.
- CI helper tests: 9 passed, including credential/privilege mutation rejection and a regression for silently ignored Xcode test exclusions.
- Repository/license/artifact/current+history secret checks: passed, no confirmed secret; only exact unchanged negative-test fixture exempted.
- Initial unfiltered trial: all 1,003 cases passed, but exclusions were ineffective; not accepted as selection verification.
- Corrected CI selection: **999 expanded cases  / 461 declarations, zero failures**; result tree confirmed the four GUI methods did not execute. The original 1,003-case suite remains intact.
- Shared Debug, Release and complete-concurrency commands: exit0.
- Fresh strict Swift validator bridge and Python Model Lab 143 + historical resource-guard 7 tests: exit0. No model loaded, inference or training.
- Final source/tool commands and source hashes are retained in ignored local Evidence/CI. Existing application source and tests are unchanged from the published baseline.

Raw local evidence is ignored under Evidence/CI. Workflow syntax was parsed with Ruby/Psych, permissions/security invariants tested, and the exact Ubuntu lint invocation passed locally. Hosted runner image/GA compiler differences, private billing/quota/preview scheduling and GitHub-server workflow execution remain **PENDING**. There is no hosted check/run to label successful because this local commit has not been pushed. No application source, UI, voice, clipboard, inference safety, dependencies or permission defaults were changed.

Commit identity: repository-local verified user, no AI co-author trailer. Commit SHA is supplied in the final handoff (a document cannot contain its own final commit hash). Remote main and private visibility remain unchanged. Stop after the local checkpoint; publishing this CI branch requires separate explicit authorization.
