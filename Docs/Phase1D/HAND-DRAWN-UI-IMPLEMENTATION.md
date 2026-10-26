# Hand-drawn Dictation and Insights implementation

25 October 2026. Implemented from the two supplied HEIC drawings, independently in existing SwiftUI. No DailyOps source/assets were used. Existing uncommitted work was preserved. No AI or model execution, downloads, clipboard actions, speech capture, agent execution, commit or push occurred.

## Comparison with the sketches

**Dictation:** retains the permanent230pt sidebar, compact page title and full-width divider. Header search is a180pt rounded capsule with thin border, magnifier, real native text input, clear button, accessible labels and reduced-motion-aware focus-border transition. It binds to the existing actual-history query; no duplicate search field. Actual GUI verification entered a nonmatching synthetic query, observed “No matching dictations,” then used Clear to restore the entries.

History stays a flat native LazyVStack of stable entry IDs, time/transcript/copy/delete, hairline separators, no table headings, surrounding card, repeated dates or insertion badges. Today's section displays TODAY in English; older sections reuse the existing ordinal/date formatter. Non-English locales use native localized relative date formatting. The active Calendar/timezone controls same-day identity; no stored timestamps changed. Pinned opaque native section headers remain separate from the page header. Existing detail access, ID-bound copy/checkmark, clipboard gates, confirmed persistent deletion and history storage are unchanged.

**Insights:** four equal compact cards, number above label: Total Words, Average WPM, Current Streak, Longest Streak. ViewThatFits uses one horizontal row when it fits and a two-column grid otherwise. Activity follows beneath, with one rounded panel: current-streak headline left, longest summary right, then the existing heatmap. No divider under the Insights title. Only Dictation/legacy History and Dictionary retain the page-header divider; settings/history row dividers remain intact.

Heatmap keeps the tested real calendar model, five blue activity levels, month/weekday labels, zero days, future-day treatment, date/count help and keyboard day-focus logic. It now uses readable10pt cells in a minimum680pt horizontal ScrollView with hidden indicators, instead of squeezing all cells to fit. The preserved model represents52 preceding weeks plus the current week (53 columns); this intentional partial-week boundary is retained rather than rewriting correct aggregation for an exact52-column visual. The outer page still scrolls vertically.

Where you write appears below Activity as a compact bar list. It was not present in the previous implementation, so it was added using stored source-application labels and verified insertion receipts only. Labels are grouped as saved display names, not asserted to be unique bundle identities. Sorting is descending verified words, then name for ties. Bars are relative to the largest app total. No private app data is queried; no failed/uncertain delivery is counted. Missing names produce an explicit coverage note and no-data history produces an honest empty state.

## Metric definitions

- Total Words: whitespace-delimited count of canonical stored cleaned transcripts across unique saved IDs; unchanged word-count representation.
- Average WPM: total canonical words ×60,000 / total stored recording milliseconds, rounded for display. Available only when history is nonempty and every included entry has a valid positive duration≤120,000ms. Zero/unknown/invalid timing makes the whole rate unavailable; coverage is stated. This is a weighted aggregate, not an average of individual rates. Reliable duration means valid existing stored timing, not a new independent audio measurement.
- Current/longest streak: existing eligible-day/calendar semantics, including the requirement that the current streak includes today. Interrupted speech eligibility is unchanged.
- App usage: only outcome inserted + reason verified + attempted true, grouped by nonblank stored application name; canonical word counts. Denied, failed, uncertain and unattempted entries are excluded. Missing-name entries are explicitly omitted.

The prior seven-metric helper and its tests are preserved; only the visible Insights selection changed per the new request. No persistence/schema or historical recording semantics changed.

## Actual native visual verification

Opened the exact Debug bundle under `DerivedData/Phase1DComplete/Build/Products/Debug/Wesley Flow.app` after tests; process inspection found no previous normal app process. The canonical installed/Run application was not replaced, no running clipboard lease was force-terminated, and no clipboard contents were read or written.

Observed the real saved history, TODAY label, top-right capsule search, trailing copy/delete controls, no column header, and Dictation divider. Inspected actual four-card Insights, title without divider, streak summaries inside Activity panel, real heatmap and app usage beneath it. Inspected both Light and Dark appearances and restored original System appearance; Offline AI Rewriting remains OFF. No inference button was pressed.

Native Accessibility history scroll-to-bottom succeeded and the captured older-date header remained pinned below the Dictation header. This verifies native accessibility scrolling and one pinned replacement state, not every intermediate push-off/flicker transition. Ordinary wheel/drag scroll and resize attempts returned the computer-use bridge error `noWindowsAvailable`; a native submenu selection also returned invalidUIElement. These automation failures do not establish a product scrolling failure, but physical trackpad/mouse/keyboard scrolling, horizontal heatmap scrolling, exact960×620 and800×520 GUI sizing, and all intermediate sticky transitions remain **UNVERIFIED** for this run. Existing automated native layout tests still pass at both target sizes and accessibility scaling; that is not substituted for physical GUI evidence.

The screenshots are actual app captures, not mockups; existing transcript text remains local. Differences from the drawings are native typography/colors, production seven-item sidebar, real history values, readable-cell horizontal heatmap overflow, a concise WPM coverage note, and the requested app-usage section that is specified in the task text rather than drawn.

## Actual screenshots

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

(Private/local screenshot omitted from publication.)

## Verification

- baseline: exit0, 945 expanded cases / 431 declarations, 0 failures. Evidence: `Evidence/Phase1D/drawing-baseline.json`, `.log` and `.xcresult`.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/drawing-baseline.xcresult test
```

- focused-fixed: exit0, 607 expanded cases / 329 declarations, 0 failures. Evidence: `Evidence/Phase1D/drawing-focused-fixed.json`, `.log` and `.xcresult`.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/drawing-focused-fixed.xcresult test -only-testing:WorkspaceTests -only-testing:WesleyFlowAppTests
```

- full: exit0, 953 expanded cases / 437 declarations, 0 failures. Evidence: `Evidence/Phase1D/drawing-full.json`, `.log` and `.xcresult`.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/drawing-full.xcresult test
```

- replay: exit0, 953 expanded cases / 437 declarations, 0 failures. Evidence: `Evidence/Phase1D/drawing-replay.json`, `.log` and `.xcresult`.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath $REPO_ROOT/Evidence/Phase1D/drawing-replay.xcresult test
```

- debug: exit0. Evidence: `Evidence/Phase1D/drawing-debug.json`, `.log`.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug build
```

- release: exit0. Evidence: `Evidence/Phase1D/drawing-release.json`, `.log`.

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData/Phase1DComplete -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release build
```

Added eight expanded regression cases in six test declarations: exactly four metrics and weighted WPM; three invalid/missing timing values; empty/duplicate history; verified app words with stable ties and missing names; deletion updates; TODAY/older formatting across active timezones. Existing date grouping, DST/boundaries, search filtering, ID-bound copy/deletion persistence, streaks, activity heatmap, native layout/window sizing and preference/provider tests were retained and rerun. No tests removed or weakened.

The first focused compile failed exit65 because a new fixture used a nonexistent `.failed` outcome. Corrected to the existing `.unsupportedTarget` outcome with `.unsupported` reason; final focused/full/replay/builds all passed. The failed record is retained at `Evidence/Phase1D/drawing-focused.*`. No safety threshold, authority or model behavior changed to pass tests.

## Git and scope

Task-start hashes prove only three existing Swift files changed:

- `App/GlobalDictationView.swift`: view presentation/search/header/card/heatmap layout.
- `App/DictationPreferences.swift`: pure presentation aggregation and relative section label helper.
- `AppTests/GlobalDictationTests.swift`: append-only regressions.

Every prior test byte is preserved as a prefix. Provider, speech, coordinator, clipboard, persistence, pill, validator, package and Xcode configuration are unchanged from task start. No dependencies, capabilities or entitlements added. `git diff --check` exit0. Index empty. All work remains uncommitted, including pre-existing changes. No commit/push/remote operation.

```text
 M .gitignore
 M AGENTS.md
 M App/AppComposition.swift
 M App/FoundationView.swift
 M App/WesleyFlowApp.swift
 M Docs/Phase1B/MODEL-PROVIDER.md
 M Docs/Phase1B/SECURITY-BOUNDARIES.md
 M Packages/WesleyFlowCore/Package.swift
 M Packages/WesleyFlowCore/Tests/WorkspaceTests/ProviderTests.swift
 M Packages/WesleyFlowCore/Tools/OllamaEvaluation/EvaluationMain.swift
 M WesleyFlow.xcodeproj/project.pbxproj
?? App/ClickableDictationPill.swift
?? App/DictationModel.swift
?? App/DictationPreferences.swift
?? App/GlobalDictationView.swift
?? App/SystemWideDictationCoordinator.swift
?? AppTests/DictationTests.swift
?? AppTests/GlobalDictationTests.swift
?? Docs/ModelLab/
?? Docs/Phase1C/
?? Docs/Phase1D/
?? ModelLab/
?? Packages/WesleyFlowCore/Sources/Domain/AppOpeningCommand.swift
?? Packages/WesleyFlowCore/Sources/Domain/Dictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/Domain/DictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/Domain/GlobalDictation.swift
?? Packages/WesleyFlowCore/Sources/Domain/OfflineRewrite.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/AppleTranscriptRewriter.swift
?? Packages/WesleyFlowCore/Sources/ModelProviders/LocalPromptRewriter.swift
?? Packages/WesleyFlowCore/Sources/Persistence/SwiftDataDictationHistoryStore.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeAppOpening.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationFormatting.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeDictationShortcut.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/NativeTextInsertion.swift
?? Packages/WesleyFlowCore/Sources/SystemOperations/TextInsertionService.swift
?? Packages/WesleyFlowCore/Sources/VoiceInput/
```
