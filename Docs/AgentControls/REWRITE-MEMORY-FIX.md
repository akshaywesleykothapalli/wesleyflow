# Bounded rewrite memory fix — 45.0.10

The user repeatedly reported that Fn dictation followed by Option+2 stopped with “memory blocked” and explicitly requested a fix. This continuation intentionally revises the earlier fixed-reserve rewrite policy; it does not claim the old policy was unchanged.

## Diagnosis and change

A read-only five-sample host observation showed the conservative free-plus-inactive estimate moving from 4.086 to 4.083, 4.075, 3.994 and 4.010 GiB. Pressure was normal throughout and swap use remained exactly 1,081,540,608 bytes. The old 4 GiB rewrite floor could therefore reject a request during ordinary host fluctuations even without starting generation. The prior real diagnostic also reached readiness then rejected generation under that policy. That older result lacked the exact failing stage/counter, so no stronger attribution of its instantaneous cause is claimed.

Only the bounded Apple text rewriter now reserves **2 GiB** at admission, during generation and before accepting output. This is an application budget choice for a short system-managed, maximum-256-response-token request, not an Apple-published memory guarantee. The eight-second deadline, 250 ms resource observation, normal-pressure requirement, zero swap growth from the request baseline, cancellation, output validation and single in-flight framework ownership remain. Unknown observations still fail closed. No automatic retry, cloud fallback, external model, model download or OS-service termination was added.

Agent planning had called the rewrite's static memory predicate. It now owns its original independent **4 GiB**, normal-pressure and no-swap-growth predicate, verified at and below its boundary. Heavyweight model admission is unchanged. The shared FoundationModels generation lease remains intact.

Resource failures now retain typed cause, stage, observed available bytes, required reserve and swap delta. These contain no input/editor/model text. Persistent shortcut errors distinguish low memory, elevated pressure, swap growth, observation failure and a previous request still stopping. A busy request is no longer labelled MODEL_MEMORY_BLOCKED. Original input and inserted text remain intact on rejection. Manual previews use the same precise explanation. Metadata does not change the history/preferences schema.

## Verification

The actor-checked deterministic speech/Unicode/audio/Agent/rewrite gate passed. New provider tests exercise successful rewriting at 3 GiB while Agent planning still refuses it; the 2 GiB boundary; refusal before generation; post-generation refusal for low memory, pressure and a one-byte swap increase; admission and mid-generation observation failure; and retention of the exact rejection stage. Existing cancellation, timeout, single-slot ownership and late-result suppression tests remain. New app fixtures assert precise persistent errors for all five resource causes, no second insertion/preview, unchanged original field and untouched clipboard.

One bounded real **Prompt Engineering** test used synthetic English input, the actual AppleTranscriptRewriter and on-device generator, with process networking denied. It returned **rewritten in 4,116 ms**; the complete test took 4.135 seconds. The production prompt preservation contract accepted the generated classification/rendering. Every admission/watch/completion resource guard remained active. This proves this synthetic prompt completed on this host with the revised policy, not every workload or physical editor replacement.

No microphone, physical keyboard injection, external-app accessibility-tree inspection or external editor insertion was automated. The after-insertion Fn → Option+2 workflow and exact-span replacement checks remain unchanged.

The first native app build failed before compilation because its new DerivedData symlink pointed to a not-yet-created temporary folder. The folder was created; the clean rerun is recorded separately under ignored Evidence/RewriteMemoryFix/Final. The initial failure evidence remains under Verified. Temporary build/app copies will be removed after the verified installation, consistent with the user's duplicate-app cleanup request.

Final native verification: **849 declarations / 1,930 expanded cases passed**, zero failures. Release build with complete concurrency checking passed. Repository checks passed; CI helper tests 15/15 and local packaging tests 3/3 passed. Two assertions in the first full native run still matched the old generic memory/resource wording; they were updated to the new generic fallback wording, while the new typed-error tests assert the precise cause. A full rerun passed. The final pill-label refinement was followed by another full 1,930-case pass and a fresh release build. Both the detailed persistent errors and compact pill labels are covered.

## Handoff

Installed and reopened **45.0.10** at `/Applications/Wesley Flow.app` after normal Quit of the previous copy. Strict/deep signature verification passed and the installed process survived a 15-second launch check. Every existing preference was checked equal after launch; the selected shortcut action remains `lastInsertion`. No history/model changes, clipboard access, forced quit, network fallback or automatic key insertion were used.

After successful launch, the temporary signed/staged copy, previous app backup and both temporary build caches were removed. Generated DerivedData symlinks were removed as well; test reports and logs remain under ignored `Evidence/RewriteMemoryFix`. No old application backup is intentionally retained. Implementation commit: `9a12f44`; metadata-only installation provenance is `Evidence/RewriteMemoryFix/handoff.json`.

User acceptance starts with a fresh Fn dictation because replacement provenance is intentionally process-local. After text appears, Option+2 requests its prompt replacement and Option+1 requests polish. This handoff verifies the on-device generation and deterministic replacement fixtures, not a scripted physical editor write. Genuine pressure, swap growth or sub-2-GiB conditions can still pause rewriting with their specific explanation.
