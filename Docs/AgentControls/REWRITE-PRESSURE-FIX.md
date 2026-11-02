# Warning-pressure rewrite correction — 45.0.11

The user reported “memory pressure” after 45.0.10. Five read-only host observations returned raw pressure 2 with 3.895–3.955 GiB conservative available memory and constant swap use of 1,031,208,960 bytes. The currently running app was the Xcode Debug product (45.0.10), not the Applications copy. Its observed RSS was about 100 MiB; this is not a measurement of all OS-managed speech/AI/GPU memory. Inspection showed the English adapter clears app-owned capture/analyzer references on successful completion. No unproven speech-cache purge was added.

## Pressure policy

The Darwin sysctl returns converted dispatch pressure flags, not the kernel's internal 0/1/2/3 enum. Mapping is normal=1, warning=2, critical=4; other values are unknown and remain blocked. This is verified against the installed dispatch/source.h and Apple's [sysctl conversion implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c). Apple's [notification documentation](https://github.com/apple-oss-distributions/xnu/blob/main/doc/vm/memorystatus_notify.md) separately describes internal pressure levels. No pressure/swap sysctl is written and no synthetic system pressure is induced.

The memory sample now retains normal/warning/critical/unknown explicitly. Its existing pressureNormal Boolean stays false for warning, critical and unknown. Legacy Boolean-only sources map false conservatively to critical. Heavy model and Agent planning admission therefore retain their previous normal-only behavior and unchanged reserves.

Only short Apple text rewriting admits a warning state when at least 2 GiB remains available and swap has not increased from the request baseline. Critical pressure, unknown observations, a sub-2-GiB sample or any swap growth still block it. The eight-second deadline, 250 ms observations, 256-response-token cap, one framework lease and cancellation/late-result protection remain. This is an intentional bounded-workload application policy, not a claim that warning is harmless or permission to start arbitrary models. The user explicitly requested correction of the repeated memory blocker.

Resource diagnostics now retain the observed pressure level. The detailed pressure error explicitly says critical. No microphone, ASR, romanisation, insertion, clipboard, history or preference behavior was changed.

## Prompt transport

The first new real synthetic probe passed memory checks but returned invalidOutput after 4,583 ms. The previous catch path did not retain enough information to attribute that result to a model error versus contract rejection. It is not counted as a successful generation.

Prompt Engineering now uses FoundationModels guided typed output for its five integer-index arrays, then serializes those fields to the existing Domain contract. This guarantees the transport keys/types rather than requesting free-form JSON. The original renderer still rejects missing, repeated, invented and out-of-order indices and preserves every source unit exactly once. No permissive parser, repair of unsafe model plans, deterministic fallback or model retry was added. Smart Polish retains its existing text response path. Diagnostic reasons now distinguish output-contract rejection from native-generator failure without retaining transcript/output/error-description contents.

## Verification

Actor-checked deterministic speech/Unicode/audio/Agent/provider tests passed. New tests verify raw dispatch flag mapping (including unknown values); conservative legacy Boolean mapping; successful bounded rewriting under warning while Agent planning still refuses warning; critical/unknown refusal before generation; unchanged warning-state reserve/swap guards; and guided transport with valid source-preserving output plus rejection of incomplete, duplicate or reordered plans.

A second bounded real synthetic Prompt Engineering request, after that transport change, returned **rewritten in 3,908 ms** (complete test 3.925 seconds). All **18** observed resource samples were **warning**, minimum available bytes **3,204,186,112**, maximum swap growth **0**. The production prompt contract validated the result. Process networking was denied. This establishes one actual completed on-device request under the user's reported warning condition; it does not prove every input or physical editor delivery. No critical/unknown pressure generation was attempted.

Actual native build/test, packaging and installation outcomes follow when complete. Temporary products will be removed after handoff. The running Debug copy must accept normal Quit before the canonical Applications copy is reopened; no forced termination or unrelated app closure is authorized or performed.

Full native suite: **854 declarations / 1,936 expanded cases passed**, zero failures. Release with complete concurrency checking passed. Repository checks passed; CI helper tests 15/15 and local packaging tests 3/3 passed. No test expectations were weakened to allow critical/unknown pressure or unsafe plans.

## Installed handoff

Installed and reopened **45.0.11** from `/Applications/Wesley Flow.app`. All running identified Wesley Flow copies accepted normal Quit, including the Xcode Debug product. The stale stopped 45.0.10 Debug app bundle was removed after successful handoff; Xcode itself and its other caches were preserved. Every existing preference compared equal after launch; `formattingShortcutAction` remains `lastInsertion`. Strict/deep signature verification and a 15-second launch-survival check passed.

The temporary prepared app, previous Applications backup and both temporary build caches were removed after successful launch. Native test reports and logs remain under ignored `Evidence/RewritePressureFix`. Implementation commit: `9a12ae3`; metadata-only provenance: `Evidence/RewritePressureFix/handoff.json`. No user audio or editor contents are retained there.

Physical acceptance uses the Applications copy and a fresh Fn dictation (old process-local replacement provenance intentionally cannot survive restart). After insertion, press Option+2 without editing/moving the caret. The actual physical cross-app replacement remains user-tested; the recorded real verification is on-device prompt generation under warning plus the existing deterministic replacement/cancellation suite.
