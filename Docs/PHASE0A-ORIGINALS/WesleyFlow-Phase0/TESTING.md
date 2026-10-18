# Testing and evidence strategy

Current execution result: no application build or test performed. There is no application implementation in this review packet.

## Test layers

| Layer | Meaningful evidence |
|---|---|
| Domain unit | Legal/illegal lifecycle transitions, terminal immutability, typed failure and retry linkage |
| Coordinator with controlled dependencies | Approval suspension, denial, ordered durable events, cancellation at each suspension, late-result rejection, storage failure prevents effects |
| Repository integration | Temporary store reopen, task/event atomicity, migration, interrupted recovery, disk-write failure and artifact reconciliation |
| Broker/workspace integration | Outside-root rejection, symlink escape, stale approval, changed file hashes, path substitution, revoked access and denied operations |
| Process integration | Temporary fixture executables: output limits, nonzero exit, timeout, cancellation, descendant cleanup and surviving-process reporting |
| Provider/runtime contract | Capabilities, offline behavior, stream ordering, cancellation, memory pressure, load failure and normalized tool requests |
| Native app tests | Composition, launch, keyboard/accessibility and honest error states; XCTest UI tests only where user flows justify them |
| End-to-end on target hardware | Offline dictation, approved edit, build/test verification, restart history and recovery, memory and sustained thermal behavior |

Swift Testing is preferred for pure domain/package tests; use XCTest/XCUITest for app integration/UI where required. Verify library/toolchain availability when creating targets. Test doubles use deterministic clocks/events, isolated temporary directories and no real Accessibility or microphone prompts. Real macOS permission tests are manual or explicitly provisioned integration runs, with results identified separately.

## Foundation acceptance after approval

1. Create a clean independent repository and Xcode project with shared scheme.
2. Compile Debug and Release for macOS with the explicit Xcode toolchain and deployment target 26.0.
3. Run the foundational domain tests and app composition test; save test result bundles.
4. Launch the shell and check the window manually or through available UI tooling. Report separately if launch cannot be verified.
5. Record commands, compiler/SDK, exit codes, counts, failures and result paths. A build passing without tests is not a test pass; discovery is not execution.

Do not enforce invented latency or memory thresholds. Establish measured baselines on M4/16 GB in the relevant phase, then set product budgets. macOS 26 runtime compatibility and release signing require separate environments/evidence. Repeat broader tests only when changes or unresolved failures justify them.
