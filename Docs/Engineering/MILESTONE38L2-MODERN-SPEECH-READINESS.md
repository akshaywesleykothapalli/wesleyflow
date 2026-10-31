# Milestone 38L2 — Modern Speech Resource Readiness

28 October 2026, Asia/Kolkata. Repository: `/Users/akshaywesley/Developer/WesleyFlow`.

## Disposition

Implementation and automated verification are complete locally. **Native installation, successful modern-engine preparation after installation, and user-operated 1/3/5-minute dictation remain PENDING.** No installation request, asset reservation, download, microphone start or live editor insertion was initiated by this task. This milestone implements the user's explicit Settings action; it does not treat implementation authorization as consent to download resources now.

The selected locale remains **en-IN**. This device reports modern SpeechTranscriber available. Both modern engines list the selected locale in supportedLocales and installedLocales, but AssetInventory reports **supported**, not **installed**, for the actual module configurations. The distinction matters: locale presence alone does not establish that every required module asset is ready. The app therefore offers explicit resource installation rather than claiming modern readiness or advertising uninterrupted legacy dictation.

## Instructions and preserved baseline

Read AGENTS.md and the complete Milestone 38L1 report before editing. Initial HEAD remains `24db5c924f8598c6971c771e41f1678262e54379` on `feature/milestone-31-integration`. Existing 38L1 source, tests, CI changes and report were uncommitted; preserved 19 baseline files and their hashes before making 38L2 changes. The old report remains byte-for-byte unchanged.

38L2 changes are limited to speech readiness/resource APIs, capture engine selection through the common readiness policy, additions within the existing General settings group, resource/long-cancellation tests, CI regression requirements, this report, and a build version. No UI redesign, new panel, AI rewriting/provider change, speech language preference change, clipboard/insertion implementation change, permission bypass, model download, training, cloud speech, commit/staging/push/merge or app replacement.

The waveform, pill, audio meter, formatting, history/Insights and text accumulator implementations from 38L1 are preserved. In particular, both TranscriptBuffer and LegacyTranscriptBuffer are byte-identical to the preserved 38L1 baseline. The 64 KiB transcript bound, 256 unresolved-range bound, 32-buffer ingress, eight-second post-release finalization watchdog, native provider resource limits, 4 GiB AI floor, AX restrictions and Terminal manual-copy decision remain in force.

## Actual native device observation

A Swift 6 arm64/macOS 26-targeted probe compiled the current production readiness implementation, with only its Domain error dependency replaced for standalone compilation. It inspected native APIs outside the restricted command environment. It did not create an AssetInstallationRequest or call downloadAndInstall. It was permitted to prepare only a verified installed modern engine; none qualified, so preparation was not attempted.

Final observation: **19:05:04 IST** (13:35:04 UTC). Full metadata, supported/installed locale lists and the probe source are saved in `Evidence/Milestone38L2/Verified/`.

| Observation | Actual value |
| --- | --- |
| Requested/selected speech locale | en-IN, from the existing preferred-language selection |
| Apple-resolved locale | en_IN for both modern engines; canonical locale objects are obtained from Apple's equivalence API |
| SpeechTranscriber.isAvailable | true |
| SpeechTranscriber.supportedLocales | 45 entries; selected locale included |
| SpeechTranscriber.installedLocales | en_AU, en_CA, en_GB, en_IE, en_IN, en_NZ, en_SG, en_US, en_ZA |
| SpeechTranscriber module inventory | supported; module readiness not confirmed |
| DictationTranscriber.supportedLocales | 54 entries; selected locale included |
| DictationTranscriber.installedLocales | en_IN, en_US |
| DictationTranscriber module inventory | supported; module readiness not confirmed |
| Probe process's reservedLocales | empty |
| Legacy on-device availability | true |
| Engine recommended by the production selection policy at this observation | Legacy Apple Speech compatibility — about one-minute provider limit |
| Native installation request / download / recording | Not attempted |
| Real modern preparation | Not attempted: no module with verified installed resources |
| Actual capture engine for this new build | Not physically observed; the Settings row reports last capture separately from inspected readiness |

These are process-scoped observations, not a claim about reservations held by a separately running app. Apple manages shared assets and app reservations; the empty reservation list may be relevant, but the observation does **not** prove that adding a reservation alone will resolve the module status. The explicit installation request lets Apple's API reserve the requested locale and decide whether any download is necessary. No other locale reservation is released to make room.

This refines the 38L1 diagnosis: “module assets supported but not ready” is established; absence of every language resource on disk is not. Device support and language support are present. An installed locale list and a module's installed status are separate checks.

## Implemented readiness policy

AppleSpeechConfiguration now exposes typed module readiness, device availability, Apple-resolved locale, supportedLocales, installedLocales, exact module inventory status, app reservations and legacy on-device availability. Read-only inspection does not request installation, reserve resources, prepare a model or prompt for microphone/speech consent.

States distinguish:

- Device unavailable.
- Unsupported selected language/configuration.
- Supported resources requiring installation, including the observed “locale present; required module resources not ready” case.
- A download reported by macOS, with unknown percentage until a user requests an observable installation operation.
- Installed, requiring agreement between module inventory and installedLocales.
- Inventory installed but locale listing unconfirmed; no premature ready claim.

The selector uses installed modern SpeechTranscriber first, then installed modern DictationTranscriber, then available legacy on-device recognition. Capture uses that same policy and the same module factory as inspection, installation and preparation. Locale normalization treats en_US/en-US as equivalent identifiers; it does not silently substitute en-US for en-IN. The selected preference stays unchanged, and any Apple-resolved locale is displayed explicitly.

SpeechTranscriber retains progressiveTranscription. DictationTranscriber retains 38L1's explicit long-form configuration with punctuation, volatile results and frequent finalization, without a short-form hint. Canonical Locale objects returned by Apple are reacquired before constructing modules, avoiding fragile equality assumptions from recreating an identifier alone.

Legacy fallback remains available and explicitly duration-limited in Settings and actual capture engine identity. An installed modern engine that fails to prepare fails the gesture; it does not silently downgrade that gesture to legacy or claim modern success. Resource status is rechecked at capture, so an earlier inspection is not an indefinite readiness guarantee.

## Explicit installation and preparation

The existing **General → Speech engine** group now provides:

1. **Inspect availability** — reads actual capability, module status, locale lists and reservations. No download or model preparation.
2. **Install Apple speech resources** — appears for a supported missing/downloading candidate. Requested and Apple-resolved locales are shown before the action. Pressing this button is the user consent boundary for Apple's resource request.
3. Actual ProgressReporting completed/total units from AssetInstallationRequest.progress. Unknown totals show an indeterminate indicator; units are not mislabeled as bytes, and no percentage or ETA is invented.
4. Reinspection after downloadAndInstall returns. A nil installation request or 100% progress is not accepted as proof that resources are ready.
5. Automatic real analyzer preparation **after that explicit installation succeeds**, using SpeechAnalyzer.bestAvailableAudioFormat and prepareToAnalyze with the exact capture module configuration. Preparation has no microphone/tap/input sequence or text insertion.
6. **Prepare modern engine** for already-installed resources. This is also explicit; inspecting or launching the app does not load a speech model.
7. A verified preparation message, or a concrete failure status with sanitized native error domain/code. Raw error descriptions, user paths, transcripts and audio are not recorded.

Preparation rechecks readiness before and after the native call and verifies engine, requested/resolved locale, format and channel count. The temporary validation analyzer is finished and released. The next held capture creates and prepares its actual session analyzer with the same configuration; the UI does not imply that a microphone is running or a warm analyzer is retained indefinitely.

**Stop waiting** cancels the app's task/observation and requests native Progress cancellation when supported. Tickets reject late progress/success callbacks. Apple documents that an explicitly requested download may continue or retry in the background; the UI states this and does not promise that stopping observation undoes the OS request. An unsettled native operation cannot trigger unbounded parallel installs: the service admits one operation at a time.

No setup operation starts during recording, finalization, insertion or an active AI operation. Capture cannot start while setup is active. Repeated install clicks produce one request. Normal Quit asks the user to finish setup or stop waiting; existing capture and clipboard-recovery termination guards remain.

The existing **Block network requests** preference disables new installation actions. It is not toggled or bypassed. If enabled during setup, the app stops waiting/cancels its operation; an Apple download already explicitly requested may still continue under macOS management. Local preparation of already-installed resources does not require enabling network requests.

## Transcript and release preservation

No transcript accumulation or insertion algorithm was rewritten in 38L2. The common engine selector reaches the existing modern pipeline:

- The realtime PCM tap, converter and bounded ingress stay unchanged.
- Results are consumed independently from capture; finalized phrases commit to an immutable bounded prefix, and only the volatile tail can revise.
- Cross-boundary revisions that cannot safely preserve earlier text fail visibly rather than replacing the session with a short suffix. Duplicate finalized callbacks cannot duplicate committed speech.
- Release closes capture/end-of-input, then finalizes the analyzer and awaits remaining results before successful insertion.
- Unexpected provider completion while held remains a failure without automatic insertion. The last valid complete snapshot remains recoverable for intentional copy.
- The existing recording waveform, post-release “Transcribing…” state, quiet verified-success dismissal, native interruption handling, focus/target/clipboard ownership checks and no-submission behavior remain.

This does not reconstruct speech that a provider never recognized or make arbitrary provider failures recoverable without loss. It preserves available recognized text and withholds false success.

## Verification

Exact commands, start/end timestamps, logs, Xcode results, summaries/test trees and binary fingerprints are in `Evidence/Milestone38L2/Verified/`. The initial build and focused run passed; a standalone probe initially used Swift's default language mode and rejected an actor-isolated default argument. Recompiled the probe in Swift 6, matching the project's toolchain; it passed. No production workaround, weakened isolation or resource-limit bypass was introduced.

| Check | Actual result |
| --- | --- |
| Focused resource/lifecycle/PCM/history/formatting/AI/insertion tests | 322 expanded cases / 182 declarations; zero failures/skips |
| Complete regression suite, including four graphical layout unit checks | 1,305 cases / 607 declarations; zero failures/skips |
| Independent complete replay | 1,305 cases / 607 declarations; zero failures/skips |
| Exact CI lane, graphical unit checks excluded | 1,301 cases; exclusions and all required regression identifiers verified |
| Debug build | Passed, exit 0 |
| Release build | Passed, exit 0 |
| Release strict-concurrency build | Passed, exit 0 |
| CI/repository helper tests | 13 passed |
| Repository checks | Passed; 299 tracked files, 648 history objects; no issue categories |
| Diff whitespace check | Passed |

38L2 adds **28 expanded cases in 17 declarations** beyond 38L1. CI now requires the 1,301-case headless floor and specific readiness/installation/failure/cancellation tests, while retaining all 38L1 required regressions.

New tests cover missing/downloading/installed/unsupported resources; inventory/list disagreement; device availability; locale normalization; engine preference and legacy labeling; inert inspection; explicit installation; exact reported progress and unknown size; install errors and nil requests; already-installed no-download behavior; preparation errors/removal/wrong locale; cancelled/duplicate requests; stale completion rejection; capture/setup exclusion; native error-code display; and network-policy preservation.

The retained 1/3/5-minute synthetic PCM and phrase tests verify bounded ingestion, finalized/partial accumulation, ordering and deduplication. New 1/3/5-minute controlled-clock cancellation/pause tests verify prefix retention across silence, cancellation recovery and zero insertion before/after cancellation. These tests do not constitute real speech-engine accuracy or five-minute microphone acceptance. All native installation/preparation success/failure test scenarios use injected backends; real installation was not attempted.

The four graphical layout fixtures run inside disposable test hosts, not the user's real speech/editor sessions. No running user app was quit, replaced or relaunched, and no real editor was typed into. No model inference or training was run. AI provider and safety implementations remain unchanged.

## Identifiable test build

- Debug: `/Users/akshaywesley/Developer/WesleyFlow/DerivedData/Milestone38L2-Resources/Build/Products/Debug/Wesley Flow.app`.
- Release: the same path under `Products/Release/`.
- In-app diagnostic marker: **38L2**.
- Verified Debug and Release `CFBundleVersion`: **38.2**.
- Fingerprints: `Evidence/Milestone38L2/Verified/build-hashes.json`.

No canonical Run bundle was overwritten. Before opening the new bundle, finish/cancel any dictation in the running app, resolve pending clipboard recovery, and use normal Quit. Do not run two operational instances alongside a pending clipboard lease. This task did not claim a safe-idle inspection of the separately running user app or launch this build interactively.

## User-operated acceptance — PENDING

1. Open the 38L2 / build 38.2 bundle after the safe handoff above. In General, inspect availability. Confirm selected en-IN and the displayed Apple locale/resource state; note the actual observations rather than assuming the probe's older status is unchanged.
2. If resources are not ready, intentionally choose **Install Apple speech resources**. Observe Apple-reported progress or an honest unknown total. If network blocking is enabled, explicitly decide whether to change that setting; the app will not do it for you.
3. On success, verify installed module status, installed locale presence, app reservation status and the real preparation message. If preparation fails, retain its domain/code and readiness metadata; do not mark modern speech ready.
4. Hold the key in an unsent test draft. Confirm **Last capture engine** reports a modern engine and the actual Apple locale. A legacy result is compatibility mode, not long-form acceptance.
5. Perform 1-, 3- and 5-minute sessions with unique numbered opening/middle/closing phrases. Include 5–15-second silence pauses and fast/slow speech. Verify all recognized text appears once in order, with no insertion while held and one insertion after release. Record actual duration and count observations; do not retain private audio.
6. Repeat in supported native, browser, ChatGPT and WhatsApp inputs. Test app/caret changes, unsupported/secure fields and Terminal manual-copy behavior. Preserve unsent drafts and clipboard recovery; nothing should submit.
7. Cancel during a long held session and during preparation/finalization; confirm no late insertion and a clean next session. Test OS sleep/microphone configuration interruption and provider failure, checking that recoverable text remains and the status is accurate.
8. Reinspect after a preparation failure, OS asset change or interrupted installation. Apple may continue a previously requested download; no automatic app retry or silent language substitution should occur.

### Duration results

| Scenario | Controlled time / PCM / result fixtures | Real modern speech and physical insertion |
| --- | --- | --- |
| 1 minute, release after hold | Passed | PENDING |
| 3 minutes, release after hold | Passed | PENDING |
| 5 minutes, release after hold | Passed | PENDING |
| Mid-recording silence pauses | Passed for timestamped passages/controlled lifecycle | PENDING |
| Long cancellation, 1/3/5 minutes | Passed, zero insertion | PENDING |
| Installation and analyzer preparation | Injected success/failure paths passed | PENDING explicit installation; native probe did not qualify for preparation |

Retain only build marker/version, selected/resolved locale, module inventory/list/reservation state, reported progress, preparation result/domain/code, actual engine, capture duration, final/volatile counts and existing insertion/clipboard outcomes when diagnosing a failure. No transcript, audio, clipboard payload or full AX-tree capture is required for the initial diagnosis.

## Remaining limits

Apple controls resource availability, storage/network conditions, reservations, background retry and resource eviction. No fixed download size or completion time is promised. Installed locale presence alone is insufficient for module readiness. Modern resource preparation is not a five-minute speech test or a universal accuracy/compatibility claim. Legacy tasks retain their documented approximate one-minute limit; reliable rollover has not been implemented or newly claimed. Existing transcript/queue/finalization/readback bounds and editor-specific verified insertion limits remain. The selected macOS language still comes from the existing preferred-language policy; no new language picker or automatic translation was introduced.

## Primary API references

- [Apple AssetInventory](https://developer.apple.com/documentation/speech/assetinventory): system-managed assets and app locale reservations.
- [Apple assetInstallationRequest(supporting:)](https://developer.apple.com/documentation/speech/assetinventory/assetinstallationrequest(supporting:)): explicit request, nil when already installed, automatic reservation and reservation-limit errors.
- [Apple downloadAndInstall()](https://developer.apple.com/documentation/speech/assetinstallationrequest/downloadandinstall()): completion/failure and possible subsequent system retry.
- [Apple supported status](https://developer.apple.com/documentation/speech/assetinventory/status/supported): configured module support does not mean all required assets are installed.
- [Apple SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer): module readiness, preparation, input, result processing and finishing.
- Checked the installed Xcode-beta macOS 27 Speech.swiftinterface for the actual availability, locale, AssetInventory, ProgressReporting and preparation APIs. Deployment remains macOS 26 arm64; no macOS 27-only analyzer/converter API was introduced.
