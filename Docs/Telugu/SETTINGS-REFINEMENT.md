# Language settings and empty-speech diagnosis — 2026-11-01

## Audit

The running process was `/Applications/Wesley Flow.app`, build 45.0.4, with an executable dated 2026-11-01 01:23. Its executable contained neither the language-mode preference key nor Romanised Telugu support. The saved preference object had neither `languageMode` nor `teluguRecognitionLanguage`. The current source did contain both selectors, below Agent controls. Thus the missing selector in the running copy was an installation/build mismatch; the source also needed better organisation. The user confirmed that the waveform moves while speaking. That observation shows incoming activity but does not establish that the selected recognizer receives useful speech.

## Changes

- General begins with Language (English / Telugu Romanised), optional Telugu recognition policy, and hold-to-talk controls. Appearance/startup, permissions and history follow.
- Technical speech controls and Agent/AI shortcut controls remain available under a collapsed Advanced settings section. The unrelated Ollama inventory and gated-model status were removed from General. Apple-specific speech setup is shown only for English. Existing preference values, shortcuts, English engines and insertion policy are preserved.
- Dictation error status provides a direct link to Language & microphone settings and explicit Copy speech diagnostics.
- Telugu capture distinguishes no delivered frames, audio that never passed the existing sustained-speech gate, and admitted audio for which recognition returned no words. The threshold is unchanged; there is no speculative microphone gain change.
- Worker-side statistics retain only counts and numeric RMS/peak measurements. They report source/model frames and admitted utterances, survive cleanup, and reset for each session. The real-time callback remains unchanged and never takes the statistics lock. No audio is retained by these measurements.
- Empty Telugu failures retain their actionable error instead of a generic diagnostic summary. English retains its provider/native-error descriptions. Cancellation and watchdog messages remain distinct. The speech diagnostic copy now includes the local capture summary.
- The new app build is 45.0.5 so it can be distinguished from the installed old copy. User settings and history are not reset.

## Verification and handoff

Xcode 27.0 / Swift 6.4 / SDK 27.0, arm64:

- Native CI-selected suite: **828 declarations / 1,901 expanded cases passed**, zero failures; required regression selection validated. The previous four graphical tests were excluded from that count.
- Separately ran `GlobalCoordinatorTests/nativePagesInstantiateInBothAppearancesWithoutStartingSpeech()`: **passed**, rendering all pages in both appearances, with fixture speech input and no capture. This checks layout/rendering, not physical input or a visual quality assessment.
- Actor-checked deterministic Telugu Unicode, audio, quality and routing suites passed, including missing-audio versus below-threshold stream tests. CI helper tests: **15 passed**.
- The first native attempt failed the new error-preservation assertion: synthesized generic diagnostics still took priority over the intended detailed Telugu message. Corrected the Telugu-only message selection and reran the full suite successfully. Existing English diagnostics retain priority.

Evidence: ignored `Evidence/SettingsRefinement/Verified`, `Evidence/SettingsRefinement/RenderedPages.xcresult`, `Evidence/SettingsRefinement/rendered-pages.log`, and `Evidence/Telugu/package-tests.log`.

No live microphone or physical insertion acceptance is implied by fixture tests. If recognition still fails after selecting Telugu in the new build, use Copy speech diagnostics in the Dictation error area; numeric capture counts and the precise failure will distinguish capture gating from model output. The user's previous yellow message came from the older installed build, so its precise recognition failure cannot be inferred from source tests.


Release build with complete concurrency checking: **BUILD SUCCEEDED**. Debug and Release strict/deep code-signature verification passed. The Release executable contains the language selector, `te-quality-r2` specialist routing, and new capture-error markers.

Installed and reopened **45.0.5** at `/Applications/Wesley Flow.app` after the old copy accepted normal Quit. No force quit, clipboard read/write or preference reset was used. The old 45.0.4 bundle is preserved under ignored `Evidence/SettingsRefinement/PreviousInstalled45.0.4.app`; handoff metadata is in `Evidence/SettingsRefinement/handoff.json`. The launched process was verified against the exact Applications executable path. Its live microphone and cross-app insertion remain user-operated acceptance checks.

In the updated app, open **General → Language → Telugu (Romanised)**, then choose Telugu only for an initial Telugu sentence. The older copy had no saved language-mode value, so the new build retains the normal English default until the user selects Telugu. It does not silently change existing English users to Telugu.


## Direct-launch signing correction

The first installed 45.0.5 process exited during dynamic linking. Its crash report identified `whisper.framework` and hardened-runtime library validation: the app and framework were both ad hoc signed with no Team ID. A strict signature check verifies package integrity but does not prove that this library-loading policy permits launch. No valid development signing identity is installed on this machine. [Apple documents the same-team library-validation rule and its app-scoped exception](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation).

`Tools/Telugu/prepare_local_app.py` explicitly prepares a separate **local ad-hoc** package. It refuses normally signed distribution builds, preserves existing entitlements, enables `com.apple.security.cs.disable-library-validation` only on that new local copy, retains hardened runtime, and signs/verifies it. It does not modify production entitlement sources, the original build product, or any macOS security setting. This permits loading non-platform/ad-hoc libraries and reduces that app's library-loading protection; a distribution build should instead sign the app and embedded frameworks with a real matching Team ID.

```sh
python3 Tools/Telugu/prepare_local_app.py \
  --source 'Evidence/SettingsRefinement/Verified/DerivedData/Build/Products/Release/Wesley Flow.app' \
  --destination 'Evidence/SettingsRefinement/LocalInstall/Wesley Flow.app'
```

The corrected local package replaced the failed initial installation, which remains backed up as `Evidence/SettingsRefinement/FailedInitial45.0.5.app`. Its final direct-launch survival and signature results are in `handoff.json`; physical microphone/dictation acceptance remains untested. Earlier wording about the first launched process indicates dispatch, not successful startup; the initial launch failure is explicitly retained here.

Final corrected launch: **45.0.5 stayed running through a 15-second survival check and a later independent process check**, from the exact `/Applications/Wesley Flow.app/Contents/MacOS/Wesley Flow` path. Installed strict/deep signature verification passed. The three local-packaging policy tests passed, including refusal to modify normally signed distribution builds.
