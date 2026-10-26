# Containment experiment (Phase 1B.2A only)

These files are not part of the app or Swift package. They run fixed benign probes against newly created synthetic directories and a 127.0.0.1 listener. No OpenCode/model/user-project execution is supported. Use explicit same-user approval in the execution environment; do not use sudo or alter system security.

From the repository root:

```sh
/usr/bin/python3 Experiments/Containment/build_probe.py
/usr/bin/python3 Experiments/Containment/run_experiment.py
```

The builder selects the installed full Xcode developer directory, removes inherited SDKROOT, supplies the explicit SDK, compiles Swift6 Debug/Release with complete concurrency checking, and ad-hoc signs fresh Control/Sandbox/NetworkClient bundles and sandbox-inheriting children under ignored Evidence/Phase1B2A. The fixture harness executes Debug only. An inherit-only child under the unsandboxed control is expected to terminate with signal5 on the tested host; that is characterization, not a production contract.

The harness records ten boundary and six lifecycle scenarios. Pipe handshakes, kernel exit events, exact owned executable identity and exclusive file locks establish ordering/exit/resource release. The hold child intentionally pauses until signalled, even on parent death; it does not exit merely when stdin closes. The runner explicitly kills that owned survivor. No arbitrary sleep establishes test ordering. Per-record watchdogs are experiment safeguards, not a production shared cleanup deadline.

Each run creates fresh uniquely named roots, records them, and removes only those synthetic roots after cleanup. OS-created container metadata is left intact. The outer execution-environment sandbox must not be confused with the experimental helper sandbox: run the approved harness with the native same-user permission, or report it blocked rather than interpreting outer-sandbox denials as product security.

Output: latest-build.json, latest-run.json, containment-invocation.json and run/results.json with raw operation results/errno, safe signing fields, child outputs/exits, lock/exit assertions and fixture manifests. A passing characterization includes negative security findings: same-container sibling access, permitted system executable, and child survival. It is not a production security pass. See the [feasibility report](../../Docs/Phase1B/PHASE1B2A-SECURITY-FEASIBILITY.md) and [ADR](../../Docs/Phase1B/ADR-EXECUTION-CONTAINMENT.md) for the B recommendation and untested cases.
