# Product release checkpoint — 1.0.0

The user requested a clean production-style interface around the confirmed working app, removal of other model settings and historical labels, and a source checkpoint they can push to GitHub. The working tree was clean before edits. No remote push, release publication, tag, visibility or signing-account change is part of this task.

## Product changes

General retains language/recognition mode, dictation and Agent keys, permissions, history, startup and appearance. Developer engine inventories/preparation rows, live key counters and duplicate shortcut controls have been removed or reduced to actionable troubleshooting. Smart Formatting retains one combined shortcut permission, independent Polish/Prompt enable controls, style/tone and deterministic cleanup. The combined switch changes its two existing permission fields only on an explicit user toggle; settings are not migrated/reset at launch. The saved next-recording mode remains decodable; if explicitly selected previously, the UI offers a deliberate switch to last dictation. No existing preference/history/model files are deleted.

Removed the redundant manual-preview input/editor/buttons from the settings. The underlying preview interfaces, regression coverage and historical architecture remain for compatibility; they are no longer competing product controls. Privacy now explains actual on-device processing, audio/history and clipboard behavior and retains the app HTTP policy switch, without model-service names or developer counter dashboards. The production composition no longer creates an Ollama provider or model-inventory inspector. Active English/Telugu input, FoundationModels rewriting/Agent planner, insertion and clipboard services remain the same.

App-facing phase aliases (including 45A-R3, speech38L3R3 and the old preview number) have been removed. The shell says Ready. App identity/diagnostics use marketing version 1.0.0 and internal build 46; the latter is a normal monotonic build number above 45.0.19. The bundle identifier, installed app name and storage locations are preserved. Internal lifecycle states and historical regression identifiers are not development badges and were not renamed.

The visual review found a compressed Privacy heading at minimum size; the title now retains layout priority and the scrolling content may shrink. Final fixture screenshots show the full heading and coherent General/Smart Formatting/Privacy initial viewports in both appearances. Lower scrolled settings were not separately inspected visually. No external app UI or microphone was automated.

## Repository preparation

The README now describes actual current features, setup, model acquisition, requirements and delivery limits. CONTRIBUTING.md and RELEASE-NOTES.md provide normal product documentation. The previous README is archived under Engineering with corrected relative links. Historical phase/research documents, licenses and tests are preserved as engineering records. Private history, models, recordings, binaries and evidence remain ignored.

Origin was fetched successfully. At that snapshot main was 38 commits ahead and zero behind origin/main; no branch/history rewriting or force push was used. The cleanup adds reviewed local checkpoints. GitHub hosted checks are not claimed for an unpushed revision. Signed/notarized binary distribution still requires the user's own identity and release process; a clean product interface and local ad-hoc signing are not certification of every editor/OS version.

## Actual validation

- Final Xcode Debug suite: 1993 expanded cases / 901 declarations, zero failures.
- Release build: complete Swift concurrency checking passed.
- Four graphical fixture checks passed; result summary confirms four executed, zero failures and no runtime warnings. Own app pages rendered in both appearances without speech, plus minimum/larger-text sizing and control alignment checks.
- CI tooling: 15 tests; local signing/packaging: 3 tests; offline quality: 6 tests, all passed.
- Required offline research CI gate: 152 model-lab fixture tests and 7 resource-guard tests passed; no inference, training or model acquisition.

A verification iteration failed only because two existing tests matched previous status wording (Conflict/sleeping/re-registered). Expectations were updated to the new product labels; their cancellation/no-late-result behavior assertions remain. The final full rerun passed. An initial read-only xcresult summary attempt needed permission for its database migration; the approved result read confirmed positive graphical-test counts. Earlier failed logs are preserved locally and are not counted as passing results.

The tracked-file/history publication scan passed: 426 tracked files, 1370 history objects, zero issue categories.

## Installed handoff and push state

Source checkpoint `4d0a1ab`. The first install stopped when the old app declined normal Quit; no force termination or overwrite was used. After the user reported closing it, installation resumed using the same verified prepared copy. Installed marketing version 1.0.0 / build 46 at `/Applications/Wesley Flow.app`; Info.plist verification, strict/deep signature verification and the 15-second launch observation passed. All saved preference values were preserved. Temporary signing/build app copies and the previous app backup were removed after successful launch; test reports remain under ignored local evidence. No real microphone, target editor or clipboard contents were automated/inspected during verification.

The source and documentation are committed locally on main. No push, tag, release upload or hosted CI invocation was performed. The user can push the reviewed branch normally; Git protects against a non-fast-forward if origin changes after the earlier fetch. Historical test/engineering phase references remain intentionally separate from product-facing UI. Developer ID signing and notarization are still required for a public downloadable binary.
