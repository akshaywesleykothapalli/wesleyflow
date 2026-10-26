# Wesley Flow Model Lab 1

Standalone research, not an app feature. Never imports or reads user projects/history. Proposals and code are inert text. The Swift bridge links existing Domain/Workspace modules and calls the production codec/hash/validator. No agent, shell tool or effect broker.

Use Python 3.11 in `.venv/`. Recreate the exact macOS arm64 environment with `python -m pip install --require-hashes -r requirements.lock`; the lock contains the wheel hashes actually installed on this Mac and is platform-specific. No global packages are changed.

From the ModelLab directory, first run `.venv/bin/python build_validator.py` and `.venv/bin/python inspect_runtime.py` The first command freshly compiles production Domain/Workspace sources with strict Swift 6 concurrency checks; it does not depend on the old UI build cache. The second records actual installed CLI help and package-source hashes without loading weights. Standard-library preparation/tests work without ML dependencies. MLX tooling is installed in the dedicated venv. The pinned artifact has now been approved, acquired and hash-verified; heavy runs remain memory-gated. See Docs/ModelLab/MODEL-LAB1-REPORT.md for what actually ran.

```sh
.venv/bin/python lab.py inventory
.venv/bin/python lab.py validate
.venv/bin/python lab.py prepare
.venv/bin/python lab.py sample
.venv/bin/python lab.py dry-run
.venv/bin/python lab.py baseline
.venv/bin/python lab.py train
.venv/bin/python lab.py compare
.venv/bin/python -m unittest discover -s tests -v
```

Do not pass a hub ID to a runtime. Only a complete hash-verified local artifact is accepted. Offline env is forced; remote code/training telemetry are disabled. `acquire.py` records the bounded acquisition path; it requires exact-artifact approval and refuses to overwrite the existing verified model. It is never invoked automatically. MLX safetensors are not assumed Ollama-compatible. No automatic adapter promotion or publication.

Training smoke cap: batch1, sequence1024, rank4,2layers,4steps, seed42, validation/checkpoint every2steps, deadline120s. Inference and training admission are separate. The guard preserves4GiB system reserve and2GiB runtime allowance; training adds3GiB provisional activation/optimizer allowance. Estimates are conservative planning figures, not measured peaks.20GiB free disk required for ML setup/runs; no automatic cleanup. Resident Ollama models, unknown observations or abnormal pressure block both. Sustained swap growth >256MiB twice stops the owned child; pressure/reserve failures stop immediately. Only the Lab's own process group is terminated, never other apps/daemons.

`data/corpus.jsonl` is synthetic data with exact expected code and production-validator checks. Refusals deliberately use plain text; the existing codec maps these to typed proposalRejected/malformed, not a newly invented refusal schema. Malformed garbage alone is not scored as a correct refusal. No first-class model refusal type exists in the current app; this is an integration limitation. Adversarial proposal probes are separate from training targets. The dataset target200–500 is provisional; this smaller reviewed seed corpus is not inflated by renaming near-identical examples.

`prepare` holds the same exclusive lab lease as heavy runs. Corpus, split files, evaluation IDs, model artifacts and runtime source identities are checked before use. Expected-output replay is labeled SIMULATED and is not model accuracy. Blocked gate checks exit 0 when the guard itself ran successfully; always inspect the JSON `state`, not just the exit code.

The Python harness creates only its own fixed validator/ML worker processes. It is not an OS sandbox or production task coordinator. SIGINT/SIGTERM, deadlines and resource stops reap the owned worker; uncertain cleanup quarantines future lab runs. Parent force-kill/power-loss containment is not guaranteed. No automatic quarantine clearing or retry is supplied.

The official trainer adjusts its own process's MLX wired allowance to the device recommendation. This does not change OS sysctls or the lab system reserve; a separate MLX allocation limit and parent resource monitor remain. Their live behavior is NOT TESTED because training was blocked. No claim of measured training feasibility is made.

Current results are in `Docs/ModelLab/MODEL-LAB1-BASELINE-FOLLOWUP.md`. Run `verify.py tokenizer`, `verify.py tests`, `verify.py replay`, `verify.py baseline` or `verify.py train` using the dedicated venv to retain exact command evidence. Generation is capped at 320 tokens; full context stays at 1024. No model generation or training has yet passed admission.

## Offline baseline readiness

See `Docs/ModelLab/MODEL-LAB-BASELINE-READINESS.md` for the current verified/blocked state. `runner.py` accepts explicit local model, dataset and frozen manifest paths. Use `verify.py readiness-prepare`, `verify.py readiness-tests`, `verify.py readiness-replay`, `verify.py readiness-config`, or (once manually authorized) `verify.py readiness-smoke`. Smoke selects one frozen held-out case, enforces the existing gate and child-only network denial, and returns exit 2 on BLOCKED. Training preparation does not train; there is no runner training mode. No current numerical inference success is claimed.

## Clean-checkout regression tests

No model weights, MLX environment, network access or historical Evidence directory is needed for these checks. With a compatible full Xcode selected, from the repository root:

```sh
python3 ModelLab/build_validator.py
python3 -m unittest discover -s ModelLab/tests -v
python3 -m unittest discover -s ModelLab/NativeDiagnostics -p 'test_*.py' -v
```

The validator build uses the production Swift codec/validator, not an alternate implementation. The versioned test fixtures contain only synthetic prepared messages and fixed resource numbers; they replace dependencies on untracked run artifacts without changing assertions or benchmark answers. `NativeDiagnostics/recorded_resource_guard.py` preserves the historical standalone guard for boundary tests; production provider admission remains separate. Optional live model/training preparation still requires its original pinned dependencies, separately approved artifacts and resource gates; these test commands do not activate it.
