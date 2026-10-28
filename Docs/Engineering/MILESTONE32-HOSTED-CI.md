# Milestone 32 — Hosted CI and pull request validation

26 October 2026. **PUSH SUCCESS; DRAFT PR CREATED; HOSTED CI PASSED; MAIN UNCHANGED; MERGE NOT PERFORMED.**

## Publication and review

Published only `feature/milestone-31-integration` using normal non-force `git push origin HEAD:refs/heads/feature/milestone-31-integration` (exit 0). Local and remote source SHA: `23caeca630b803fddc2cd007a5159dc9839b71cf`. Remote source did not exist before publication; remote main was checked before and after and remains `b90976c305cb0eb5a32a1658cbe0408f3d8fe2b8`. Initial working tree was clean. Original CI commit `3befcf20ff60220c5f678aa1c3c1a137064b4ea3` remains an ancestor. Five intended commits, 36 changed files; published PR file list matches the local branch diff.

[Draft PR #1](https://github.com/akshaywesleykothapalli/wesleyflow/pull/1) targets main. Draft status OPEN, mergedAt null, expected base/source SHAs confirmed after CI. Body now includes actual hosted results and explicit runtime limitations. No application or workflow corrections were needed in this milestone. No new commit was made.

Reviewed branch changes cover guarded CI, preview quality contracts, isolated preview shortcuts, versioned research contracts/provenance, tests and documentation. No production agent, automatic AI insertion or new cloud provider is enabled. MIT license is unchanged; third-party notices/provenance preserved. All five commits have user authorship: Akshay Wesley Kothapalli, GitHub user noreply identity. No AI co-author trailers introduced. Basic tracked/history secret, artifact, license and workflow scan passed: 278 tracked files, 581 local history objects, zero issue categories. Published PR checkout scanned 582 history objects (including GitHub's synthetic merge), also zero issues. No model weights, personal transcripts or generated build outputs were included. Pattern scanning is not exhaustive proof against every possible secret.

## Coverage explanation

Local full suite and replay evidence from Milestone 31: 1,025 expanded cases / 477 declarations, zero failures. Hosted selection: 1,021 / 473. Exactly four native graphical methods are excluded:

- GlobalCoordinatorTests/nativePagesInstantiateInBothAppearancesWithoutStartingSpeech()
- GlobalCoordinatorTests/compactPagesAccommodateLargerTextWithoutExpandingTheMinimumWindow()
- GlobalCoordinatorTests/compactDefaultHomeAndWindowUpdatesPreserveUserGeometryWithoutVoice()
- SettingsRowLayoutTests/actualNativeControlFramesShareTrailingEdge()

These remain local graphical gates. No deterministic lifecycle regression was removed. CI runs all other tests rather than an only-testing subset, requires at least 1,021 cases, explicitly checks all 12 new regression method identifiers passed, and rejects accidental execution of those four graphical methods. Local selection already reproduced 1,021; both real hosted runs now confirm it. No microphone, physical Accessibility interaction, live Apple Intelligence, training or MLX weight download occurs in hosted CI.

## Actual hosted execution

Workflow: **Wesley Flow CI**.

| Trigger | Run | UTC interval | Total elapsed | Repository job | macOS job |
|---|---|---|---|---|---|
| Push | [40368220610](https://github.com/akshaywesleykothapalli/wesleyflow/actions/runs/40368220610) | 17:23:52–17:27:57 | 4m05s | SUCCESS, 9s | SUCCESS, 3m46s |
| Pull request | [40368267339](https://github.com/akshaywesleykothapalli/wesleyflow/actions/runs/40368267339) | 17:24:10–17:28:42 | 4m32s | SUCCESS, 11s | SUCCESS, 4m15s |

Actual macOS setup logs identify **xcode-27-arm64 image 20261023.0307.1**, runner version **20261021.618**. This is newer than the public inventory version reviewed before publication; actual execution is authoritative. Preflight in both runs returned Xcode **27.0**, Swift **6.4**, macOS SDK **27.0**, architecture **arm64**. Ubuntu image **ubuntu-24.04 20261012.334.1**.

Both runs independently reported:

| Check | Actual result |
|---|---|
| YAML / repository policies / license / artifact / basic history secret scan | PASSED |
| CI helper tests | 13 passed |
| Offline quality scorer tests | 6 passed |
| Application tests | 1,021 cases / 473 declarations, zero failures |
| Debug build | PASSED |
| Release build | PASSED |
| Complete-concurrency Release build | PASSED |
| Synthetic Model Lab | 152 passed |
| Resource-boundary contracts | 7 passed |

All workflow steps concluded success. No hosted failure logs or corrective push were necessary. Compilation does not prove runtime race freedom or physical shortcut/insertion reliability.

## Commands and evidence

Executed repository checks locally with `python3 Tools/CI/repository_checks.py` (exit 0); `git diff --check main...HEAD` and original-CI ancestry check passed (exit 0). Read AGENTS.md, Milestone 31 report, workflow, source/test/infrastructure changes and full branch file inventory. Reviewed preserved local checkpoint evidence; no source change required another local full build in this milestone.

Publication: `gh pr create --draft --base main --head feature/milestone-31-integration --title <reviewed-title> --body-file <sanitized-body>` (exit 0); `gh pr edit 1 --body-file <updated-evidence-body>` (exit 0). `gh run view <run> --json status,conclusion,jobs,url,headSha,createdAt,updatedAt`, completed `gh run view <run> --log`, `gh pr checks 1`, `git ls-remote --heads origin`, and final PR identity queries returned exit 0. An earlier request for logs while the job was running returned exit 1, “logs will be available when it is complete”; completed logs were subsequently retrieved successfully.

Hosted commands: strict yamllint; unittest discovery in Tools/CI/tests and Tools/OfflineQuality; repository_checks.py; run_checks.py preflight, test, debug, release, concurrency and model-lab. All passed. Build commands use explicit full Xcode, arm64, two jobs, disabled automatic package resolution, ad-hoc signing and no developer team/certificate. Raw logs stayed runner-local; no artifact upload was configured. Only aggregate synthetic test evidence was emitted.

## Account and safety

Private repository and correct authenticated user confirmed; Actions enabled; account plan Free. Account-wide October Actions usage API before publication reported 9 discounted Linux minutes, zero net billed usage, and discounted storage usage. This is observed usage, not a guarantee of remaining quota or budget enforcement. Actual standard runner scheduling succeeded. No paid larger runner, spending setting, signing certificate, token exposure, repository visibility change or privileged secret access was introduced. Workflow contents permission read; default workflow permission read; checkout SHA pinned with persist-credentials false. No pull_request_target or privileged write workflow.

Branch protection query returned HTTP 403: upgrade or public visibility required for this private repository. Neither was changed. Recommended when supported: require both CI jobs, PR review, disallow force push and branch deletion, after checks are working. Until then follow the documented manual PR process; no automatic protection is claimed.

## Remaining manual gates and final state

Physical Option+1/Option+2 delivery in TextEdit, ChatGPT Mac, Codex Desktop and VS Code remains UNVERIFIED at the user's request. Repeated native ChatGPT/Codex dictation insertion remains manually unverified. Four graphical tests require local verification. Live tone quality remains resource-blocked/unverified; preview fixture success is not model-quality evidence. AI opt-in and automatic insertion disabled; existing 4 GiB memory floor unchanged. No custom-model training or adapter exists. V3 contract semantic review remains pending. Terminal manual-copy and disabled accessibility-tree activation remain unchanged.

Final branch remains feature/milestone-31-integration at the published SHA. Main remains unchanged. This sanitized report is the only new untracked file, intentionally local and uncommitted. No merge, release, force push, additional application change or paid feature activation occurred.
