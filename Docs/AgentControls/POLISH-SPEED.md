# Short-sentence Smart Polish — 45.0.17

The user confirmed Option+2 is faster/better and requested lower Option+1 latency. The working tree was clean before this change. Option+1 grammar mode previously always requested a typed edit array, even when the source had no protected spans and only one short sentence. Existing measurements were roughly 4–4.5 seconds for the supplied examples, but those older observations are not a controlled benchmark.

## Change

Short, single-line grammar input up to 512 UTF-8 bytes with one editable passage and no fixed spans now uses a compact plain-text response and shorter instructions. It returns no JSON/edit-plan indices. The response budget is 256 tokens; the existing structured route retains 512. Protected names, dictionary entries, code/identifiers, quantities, multiline or longer text retain the existing structured route and instructions. Cleanup mode and Option+2 are unchanged. No prewarming, background inference, speculative generation, cache/session retention or networking was added.

Both routes use the same FoundationModels lease, guarded provider, 2 GiB reserve, pressure/swap observations, 8-second deadline, cancellation, stale-result suppression, restoration/fact checks and exact insertion-anchor verification. Rejected compact output retains the original; there is no second-model retry. The choice changes transport and instruction overhead, not permission to insert an unverified result. Existing checks are observable guards, not a proof of semantic equivalence.

## Measured comparison

A bounded opt-in test ran with networking denied and the actual guarded provider. It alternated guided, compact, compact, guided (ABBA) on “This is a checkup if it's working or not.” Every trial returned the same validated sentence: “This is a checkup to see if it's working.”

| Trial | Route | Provider time |
| --- | --- | --- |
| 0 | Existing guided | 3797 ms |
| 1 | Compact | 881 ms |
| 2 | Compact | 805 ms |
| 3 | Existing guided | 1581 ms |

The first observation includes colder conditions; even the later guided observation was slower in this run. This is a small synthetic comparison on one host, not a distribution, guaranteed latency or complete end-to-end physical shortcut measurement. All trials stayed at normal pressure with zero swap growth; minimum observed available memory was 3239952384 bytes. No thresholds were reduced to obtain results.

A separate compact-path regression probe returned “What happened? Yes, I'm checking in, but I'm smoking.” in 1731 ms, preserving the user's earlier ambiguous word. Ten observations stayed normal, with minimum available 3296133120 bytes and zero swap growth. Synthetic model outputs are logged only by the explicitly enabled test, not production transcript logging.

## Verification

The focused actor-checked package gate passed. The new routing test checks short prose selection and refusal for protected vocabulary/markers, multiline, oversized and whitespace-only input. Existing grammar/fact guards, cancellation, timeout, late results, English/Telugu routing, insertion/clipboard and Option+2 regression coverage remain. Repository/history checks, 15 CI tooling tests and 3 local-packaging tests passed. The full native Xcode Debug suite passed: 1968 expanded cases across 885 declarations, zero failures. The arm64 Release build passed complete Swift concurrency checking.  No microphone or external editor was automated.

## Installed handoff

Source commit `06335b3`. The initial install and one normal-Quit retry stopped because the running app declined termination; no force quit or overwrite was used. After the user reported closing Wesley Flow, installation resumed using the existing verified prepared copy. Installed 45.0.17 at `/Applications/Wesley Flow.app` with the existing explicit ad-hoc signing helper. Strict/deep signature verification and the 15-second launch observation passed. All preferences were preserved, including grammar style and last-insertion mode. Temporary signing/package/build copies and the old app backup were removed after successful launch; comparison logs and native results remain under `Evidence/PolishSpeed`. Physical Fn/Option+1 insertion still requires user acceptance with a fresh recording after restart.
