# Compact native UI — Iteration 2

21 October 2026. Presentation/navigation refinement implemented. Executed automated verification passes; physical verification limits are recorded below. No commit or push.

## 1. Previous problems and resulting navigation

The previous UI opened on a redundant Workspace hero with an inactive coding/workflow card, a 260pt sidebar, 34pt serif headings, and a 1000×720 minimum. That made a dictation utility resemble a large dashboard.

Workspace, its hero/card, and its enum case are removed. The opening page is Dictation. Navigation is now **Dictation → Insights → Dictionary → Command Mode → Smart Formatting → Privacy → General**. History remains a Dictation subpage; its parent row stays selected. Underlying Workspace/coding/task modules remain intact.

The previous selected page existed only in SwiftUI @State: there was no saved navigation key or persisted Workspace value to migrate on disk. The real view initializer now accepts restored selection text through DictationPage.restoring: Workspace, unknown values and nil resolve to Dictation; supported values resolve normally. Focused tests cover that path without inventing a persisted preference or altering existing settings.

## 2. Compact presentation

- Permanent 230pt sidebar; custom HStack, no splitter/collapse/hide control or icon-only mode. Seven labels fit at the minimum. Navigation has its own scroll container for larger accessibility text and up/down move-command support.
- Dictation home shows current status, selected shortcut, actual last recognition engine, permission warnings when needed, recent real history and a History action. Idle instructions are not repeated; active/error details, cancellation, retry and bound clipboard-recovery actions remain available. No microphone-start dashboard, fake records, hero or inactive agent card.
- Existing functional destinations share compact cards/spacing. Palette remains semantic in both appearances. No new fonts, assets, packages or runtime features.

| Token | New value |
|---|---|
| Sidebar | 230pt + 1pt divider |
| Navigation row | 44pt minimum; 2pt spacing; 10pt group inset; grows with wrapped text |
| Sidebar brand | 16pt SF system text / 21pt SF Symbol; 56pt minimum container |
| Page title | 26pt semibold system; 62pt minimum header |
| Navigation / body | 14pt / 13pt system, using ScaledMetric |
| Section title | 12pt semibold uppercase |
| Secondary text |Native caption typography, generally 11–12pt |
| Detail inset / section spacing | 22pt / 18pt |
| Card padding / content gap / radius | 14pt / 10pt / 12pt |

Title/body/navigation and symbol sizing use native relative scaling, with minimum rather than fixed row/header heights. Larger-text constrained layout is tested across every destination. Main content scrolls independently of the sidebar and header.

## 3. SF Symbols and interaction

| Destination | Native outline symbol |
|---|---|
| Dictation |mic |
| Insights |waveform.path.ecg |
| Dictionary |text.book.closed |
| Command Mode |terminal |
| Smart Formatting |textformat |
| Privacy |shield |
| General |slider.horizontal.3 |

All symbols were verified using NSImage(systemSymbolName:) in the installed SDK. Regular and semibold configured native images produce different TIFF renderings for all seven symbols. The actual row consumes SidebarPresentation: unselected icons are regular/muted; hover raises foreground and fades in a neutral background; selection uses semibold symbol strokes, blue foreground, moderately emphasized text, a soft neutral highlight and a 3×22pt leading indicator. There is no filled-icon substitution, scale animation or spring.

Hover uses 140ms ease-in-out; selection/content fade 180ms; settings disclosure 160ms. All added animations are gated by the native accessibilityReduceMotion environment. onHover updates the current boolean, and onDisappear clears it. Native buttons, accessible labels/selection and keyboard move commands remain.

Initial native inspection announced both Dictation and the checked-shield Privacy icon as selected. The final build uses a plain shield and hides decorative icons from accessibility. Actual inspection of all seven final pages confirms exactly one selected button matching the displayed destination. This correction was followed by full verification again.

## 4. Window defaults, restoration and actual display

Production uses SwiftUI defaultSize 960×620, defaultPosition(.center), and contentMinSize with an 800×520 minimum. There is no production setFrame/setContentSize loop or resizing in onAppear. Native restoration remains authoritative.

The existing saved frame was preserved through the first update: both pre-update and initial updated captures were 2940×1668 pixels. For explicit minimum-size testing, the native Window → Move & Resize → Top Left command was used; after normal quit and final relaunch, regular captures are 1600×1104 pixels at 2×, meaning 800×520pt content plus a 32pt native title bar. The sidebar divider is at460px, confirming 230pt. All seven final pages were captured at this size with readable labels and independently scrollable detail; vertical scrolling is expected at the minimum.

A fresh-profile960×620 first-launch window was not separately launched, because the current user's restoration state was preserved. 960×620 is the tested configuration/default, not a fabricated measurement of the restored window. Center-on-first-launch is configured through the supported SwiftUI API. Physical resize dragging was unavailable through the UI tool (noWindowsAvailable); native menu sizing successfully exercised the smaller actual window instead.

## 5. Real UI evidence

Evidence/UIRefinement2/ActualUI contains actual screenshots/AX observations from the final canonical app, distinct from the hosted test renderings in RenderedPages:

- Dictation-dark.jpg: final compact Dictation home, 1600×1104px.
- Insights/Dictionary/Command-Mode/Smart-Formatting/Privacy/General-dark.jpg: every remaining destination at the same minimum.
- General-light.jpg: actual Light appearance. System appearance was restored afterward.
- Dictation-fullscreen.jpg: actual 2940×1846px fullscreen capture, sidebar retained. Native View menu exposed Enter/Exit Full Screen and no hide-sidebar command. Fullscreen was exited.
- Dictation-scrolled.jpg and its AX observation: content scrolled while the sidebar/header persisted. The scroll was returned to the top.

The History button and Back to Dictation action were exercised; real records/search were present. No records were edited, deleted or copied. No dictation or command was executed for UI verification. Some captures include macOS screen-sharing/title-bar chrome; it is system UI, not an app control.

The native capture service briefly failed/reported user interaction. Current state was re-read before further actions; final captures succeeded. Interactive hover frame timing and changing the OS Reduce Motion setting were **not physically measured**. Hover/selection state, symbol weight, larger text and native environment guards were tested/inspected; do not interpret that as a physical timing measurement or an OS-setting toggle test.

## 6. Automated verification

All final checks used the identical 74-file source hash map and reported source_unchanged:true. Environment: explicit /Applications/Xcode-beta.app/Contents/Developer, SDKROOT unset; Swift 6 mode with SWIFT_STRICT_CONCURRENCY=complete, Xcode 27 beta / Swift 6.4, arm64 and installed macOS 27.0 SDK, minimum deployment 26.0. This does not establish actual macOS 26 runtime or Swift 6.2.3 compatibility.

| Exact executed wrapper command | Exit | Actual result |
|---|---:|---|
|python3 Evidence/UIRefinement2/runner.py accepted2-focused test -only-testing:WesleyFlowAppTests |0|221 cases /152 functions, no failures/skips |
|python3 Evidence/UIRefinement2/runner.py accepted2-full test |0|845 cases /379 functions, no failures/skips |
|python3 Evidence/UIRefinement2/runner.py accepted2-replay test-without-building |0|845 cases /379 functions, no failures/skips; independent invocation |
|python3 Evidence/UIRefinement2/runner.py accepted2-debug build |0|BUILD SUCCEEDED |
|python3 Evidence/UIRefinement2/runner.py accepted2-release build |0|BUILD SUCCEEDED |

Each wrapper invokes /usr/bin/xcodebuild with the project/scheme WesleyFlow, destination platform=macOS,arch=arm64, derivedDataPath DerivedData/UIRefinement2, disableAutomaticPackageResolution, skipPackageUpdates, Debug or Release configuration, and a unique resultBundlePath. Exact expanded argv, timestamps, hashes and exit codes are in accepted2-*.json; raw logs and xcresult bundles accompany them. accepted2-{focused,full,replay}-summary.json records native case counts; review.json validates accepted results and source identity. No Swift source warnings/errors. Routine Apple AppIntents/linkd diagnostics remain in raw logs.

Four added focused tests cover legacy/default selection, removed Workspace, History parent/keyboard navigation/settings destinations; hover clearing, selected icon state and actual SDK symbol variants; compact sizing/geometry preservation; and larger text on every page. The existing native rendering test now covers all eight pages in both appearances at 800×520. It preserves image-size/data, no-speech and no-model assertions and adds constrained sizing checks. The obsolete minimum and sidebar expectations were updated for this request; no voice/concurrency/persistence test was removed or weakened.

The first attempted run failed new maximum-width assertions because NSView.fittingSize measures preferred width, not constrained minimum. Those new assertions were corrected to NSHostingController.sizeThatFits(in:) using zero/minimum proposals. The corrected focused run passed. After the subsequent accessibility refinement, all five final checks above were rerun. Initial results are retained separately and are not substituted for final verification.

Module/dependency inspection: Package.swift, Xcode target graph/project, all core sources/tests and dependencies match this iteration's baseline. No new module, dependency, entitlement or import boundary was introduced. git diff --check exits 0; staging index empty.

## 7. Preserved work and safe deployment

Only App/GlobalDictationView.swift, App/DictationPreferences.swift, App/WesleyFlowApp.swift, AppTests/GlobalDictationTests.swift, AGENTS.md and this report changed since the iteration baseline. baseline-hashes.json, baseline-status.txt and Before preserve the prior uncommitted state; ui-only.diff isolates this UI work. Prior reports were preserved.

Voice capture, Apple Speech, global shortcuts, 84×32 pill, session lifecycle, smart formatting/vocabulary, history storage, permission enforcement, target binding and clipboard leases are unchanged. Clipboard confirmation still captures the expected lease ID. Underlying coding architecture/task services are intact. Terminal stays manual-copy; declined AX tree activation stays disabled; Ollama/OpenCode and AI rewriting were not activated. Repeated ChatGPT insertion remains a separate unverified physical acceptance item.

Both app updates used visible idle/no-pending-lease checks, an already-disabled shortcut, normal Quit, confirmed process exit and exact tested Debug-bundle/signature verification. No signals/forced termination, active session interruption or unresolved lease destruction. Clipboard metadata remained revision 102, one item/one representation, no Wesley ownership marker, stable inspection throughout; no clipboard payload was read or written. Rollbacks are Run/.before-ui-refinement2-20261021 and Run/.before-ui-refinement2-final-20261021; the earlier UI-reference rollback also remains.

Final canonical app: Run/Wesley Flow.app, process 12469, exact accepted2 Debug bytes. Executable SHA-256: `34ce8f9d4d0728ae15a131a2acbf43354098aa97bb7c91164f9d007115d0b83e`. Debug dylib: `c087f26e2c34a7d7bbfaef4699c263dfc4f8db0f165e80d633e4189b92278164`. See launched.json and promotion.json for complete file identities. App remains on Dictation in a regular compact window, with System appearance restored and Fn left disabled as observed before the updates. Permissions were not granted or bypassed.

## 8. Git and remaining limits

Branch main; HEAD 0a3e91c731a716945853a6b84bcfaaf6d9e672d3. Prior uncommitted work plus this UI refinement remains uncommitted; index empty, no push or remote change. final-status.txt and final-tracked.diff retain the actual Git state. Nothing was discarded.

Remaining visual differences are intentional original Wesley Flow symbols, native macOS controls and a smaller system-font hierarchy. This is no longer a DailyOps dashboard reproduction. Longer histories/settings scroll at minimum size. Physical hover timing, an OS Reduce Motion toggle, and a clean-profile default-size launch remain unverified as distinguished above; native minimum/restoration, both appearances, selection, full History and fullscreen were exercised. No live speech/insertion or AI acceptance is claimed by this UI milestone. Stop after Iteration 2.
