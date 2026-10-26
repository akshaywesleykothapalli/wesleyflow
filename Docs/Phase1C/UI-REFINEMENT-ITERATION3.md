# Phase 1C — UI Refinement Iteration 3

Date: 22 October 2026 (Asia/Kolkata). Implementation and automated verification complete; native visual acceptance is partial as detailed below. No commit or push.

## Changes

- Native SwiftUI switch style now applies to Boolean preferences in General, Smart Formatting, Privacy, and the raw-text detail control. Original bindings, preference schema, defaults and persistence remain. Unsupported model capabilities remain informational; no new feature switches were fabricated.
- Dictation is a continuous `ScrollView` / `LazyVStack` over the complete filtered saved history, newest first. Columns are 110pt date, flexible transcript, 36pt copy and 36pt delete. Thin dividers replace dashboard containers. Long transcripts wrap to three preview lines and open existing full/raw/editable details. Empty/search-empty states are concise.
- Removed persistent idle/status/engine/permission summary, Recent card, Stored locally label, outcome badges and redundant History button from normal Dictation. Contextual errors, active cancellation, unsaved latest review, history errors and lease-bound clipboard recovery remain. Privacy retains permission setup; stored diagnostics are untouched.
- Explicit copy resolves the entry by ID and checks idle/open/no-pending-clipboard ownership synchronously on MainActor. Detail-draft copy uses the same guard. A failed writer cannot publish success. No backup restoration, lease retirement or implicit retry is introduced. Native pasteboard writing is isolated behind an injected writer for tests.
- Copy feedback is per entry ID, with UUID generations, cancellable tasks and an injected clock. It lasts 1,400ms; repeated clicks cannot expire a newer generation. Removing rows, changing page or closing cancels obsolete tasks. Fixed-size actions prevent layout movement; an accessibility announcement reports success.
- Delete captures the stable selected ID, requires native confirmation, invokes the existing persistence deletion API and reloads history. Removal fades unless Reduce Motion is enabled. Current data drives Insights, so deletion also recalculates activity/streaks.
- Insights now leads with an original 53×7 calendar heatmap, five fixed levels (0, 1, 2–3, 4–7, 8+), blue intensities, month labels, optional day labels, Less/More legend, native date/count help and accessible labels. Cells support keyboard focus and arrow movement. No chart dependency or sample activity.

## Activity and metrics definition

The pure `DictationActivity` model uses the current Calendar and timezone, calendar week/day arithmetic, 52 prior weeks plus the current week (371 cells), and deduplicates saved IDs. Future/invalid timestamps and empty text are excluded. Recognition fragments are not counted independently.

Eligible activity is a nonempty saved utterance excluding `speechFailed`; cancellation/deadline receipts count only if insertion was attempted. Other failed/denied/unsupported insertion outcomes count because speech success differs from insertion success. Existing history has no independent final-recognition flag: cancellation/deadline before attempted insertion can be ambiguous. Those records are conservatively excluded, potentially undercounting finalized but pre-dispatch-cancelled speech. No schema was changed.

Current streak must include today; longest streak uses all retained eligible local days. Calendar boundaries, DST and timezone changes are tested. The five prior metric formulas remain unchanged: saved entries, words, recording duration, verified insertions and uncertain insertions. Current and longest activity streaks were added. No average metric previously existed; none was invented. Deleted/unsaved/retention-evicted entries cannot contribute.

## Verification

Explicit developer directory: `/Applications/Xcode-beta.app/Contents/Developer`; Swift 6.4, Xcode 27 beta, macOS 27 SDK, arm64; deployment minimum remains macOS 26. SDKROOT unset. macOS 26 hardware execution and Swift 6.2.3 compilation were not performed.

| Run | Expanded cases | Test functions | Failures/skips | Exit |
|---|---:|---:|---:|---:|
| Unchanged baseline rebuilt | 845 | 379 | 0/0 | 0 |
| Final focused App/UI/history/activity | 234 | 165 | 0/0 | 0 |
| Final complete suite | 858 | 392 | 0/0 | 0 |
| Independent test-without-building replay | 858 | 392 | 0/0 | 0 |
| Final Debug build | — | — | — | 0 |
| Final Release build | — | — | — | 0 |

Evidence: `Evidence/UIRefinement3/review.json`, `visual-{focused,full,replay,debug,release}.{json,log,xcresult}` and native test summary JSONs. JSON records contain exact argument vectors, environment, UTC start/end times, exit codes and 74 source hashes. All five final runs used identical source; source stayed unchanged during each run.

Commands (from repository, `DEVELOPER_DIR` set above):

```sh
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/UIRefinement3 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath Evidence/UIRefinement3/visual-focused.xcresult test -only-testing:WesleyFlowAppTests
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/UIRefinement3 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath Evidence/UIRefinement3/visual-full.xcresult test
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/UIRefinement3 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath Evidence/UIRefinement3/visual-replay.xcresult test-without-building
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/UIRefinement3 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Debug -resultBundlePath Evidence/UIRefinement3/visual-debug.xcresult build
xcodebuild -project WesleyFlow.xcodeproj -scheme WesleyFlow -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData/UIRefinement3 -disableAutomaticPackageResolution -skipPackageUpdates -configuration Release -resultBundlePath Evidence/UIRefinement3/visual-release.xcresult build
```

Thirteen new deterministic tests cover native switch representation/binding/persistence and invalid-version preservation; newest-first stable history IDs/full long text/date formatting; daily/five-level aggregation; leap/month/year/future/week-start boundaries; partial-first-month label spacing; spring DST and timezone; autumn repeated hour; interrupted speech vs insertion failure; streak/deletion recalculation; 5,000-record aggregation; per-ID feedback generations/expiration/pruning; busy and genuine pending-lease copy rejection without backup writes; failing writer and SwiftData delete/reopen preserving the other entry. Existing assertions were not removed or weakened. Controlled clocks replace arbitrary sleeps.

Swift concurrency: existing Swift 6 checks compiled in both configurations, with no Swift source warning/error diagnostics. No claim of an exhaustive race proof. Existing core/package/project dependencies and all non-UI baseline files hash-identical. No new target, package or third-party dependency. MainActor owns UI/copy feedback; no unsafe continuation or new lock.

Earlier evidence is retained: old baseline replay failed exit65 because its previous built test-host PlugIns bundle was missing; unchanged-source rebuild then verified845. An initial new test helper syntax error was corrected. Native visual review caught a wrapping DELETE header; corrected with one-line scaling, then all five final checks were rerun successfully. System logs include AppIntents metadata-not-applicable and linkd connection warnings; these did not fail builds/tests.

## Actual running UI and safety

Canonical app: `Run/Wesley Flow.app`, verified byte-for-byte against the final Debug product and signature-checked. Each replacement followed idle/no-pending-recovery observations, disabled Fn monitoring and normal Quit with process exit confirmed. Prior bundles retained under Run for rollback. No forced termination, permission grants, speech capture, model execution or external insertion test.

Native clipboard metadata only was inspected; no payload read. A sandboxed query returned an isolated empty pasteboard and was rejected as safety evidence; native metadata showed no Wesley ownership marker. Explicit Copy QA intentionally changed the clipboard once (changeCount107→108), as requested. No clipboard-restoration claim is made. No history was deleted during live QA.

Observed live:

- Permanent230pt sidebar and seven destinations; Dictation defaults on relaunch. Flat aligned history, dates, action icons, no persistent status/outcome/Stored locally presentation. Final DELETE heading fits.
- Copy produced exactly one `Copied dictation` accessibility action with checkmark, then reverted. The screenshot catches the native transition, so icon appearance during that frame is not the sole feedback evidence; controlled-clock tests verify exact expiration.
- Native destructive dialog inspected and Cancel selected. Actual delete/reopen persistence verified only with disposable SwiftData test records.
- Heatmap reflects the56 saved utterances on20October; other dates empty. Visible totals:56 saved,286 words,1:53 recording,14 verified,6 uncertain, current streak0, longest1day. These are retained speech records, not fabricated activity or a cross-app-success claim.
- General and all six Smart Formatting Boolean controls expose native switch roles. Show pill was changed off, app normally quit/reopened, off persisted, then original on restored. Idle pill remained off, Appearance restored to System and Fn remained disabled. No permissions changed.
- Actual Dark and Light screenshots inspected; no observed clipping at the restored949×520pt content size (1898×1104px including titlebar at2×). Settings/content scroll independently of sidebar. At this height the lower speech disclosure requires scrolling, as intended.

Native visual acceptance limitations: CUA native resize/menu actions returned invalidUIElement/noWindowsAvailable; a successful live800×520 or exact960×620 screenshot was not obtained. Existing hosted-window test verifies960×620 defaults,800×520 minimum and preservation of user geometry; hosted rendering is not a substitute for live exact-size acceptance. Tooltip implementation/accessibility date-count descriptions inspected, but a physically hovered tooltip and VoiceOver spoken output were not manually verified. Keyboard focus/arrow handlers and Reduce Motion gates were reviewed; full keyboard/VoiceOver/Reduce Motion system acceptance remains manual. No full-screen change was made in this iteration.

Actual screenshots, retained locally under ignored evidence (contain existing transcript previews):

- [Final Dictation, Dark](../../Evidence/UIRefinement3/Screenshots/Final-Dictation-Dark.jpg)
- [Insights, Dark](../../Evidence/UIRefinement3/Screenshots/Insights-Dark.jpg)
- [Insights, Light](../../Evidence/UIRefinement3/Screenshots/Insights-Light.jpg)
- [General switches, Dark](../../Evidence/UIRefinement3/Screenshots/General-Dark.jpg)
- [General switches, Light](../../Evidence/UIRefinement3/Screenshots/General-Light.jpg)
- [Other switches, Light](../../Evidence/UIRefinement3/Screenshots/Formatting-Light.jpg)
- [Copy transition](../../Evidence/UIRefinement3/Screenshots/Copy-feedback.jpg)
- [Delete confirmation](../../Evidence/UIRefinement3/Screenshots/Delete-confirmation.jpg)

## Preservation, Git and remaining concerns

Only five pre-existing files changed relative to the captured iteration baseline: AGENTS.md, App/GlobalDictationView.swift, App/DictationPreferences.swift, App/SystemWideDictationCoordinator.swift and AppTests/GlobalDictationTests.swift; this report is new. The coordinator additions are guarded explicit-copy entry points plus an injected writer; all prior recording/cancellation/insertion/recovery/history methods remain unchanged. Existing preference defaults/schema, native window configuration,84×32 pill, core services, permission decisions, terminal manual-copy policy, disabled accessibility-tree activation, provider admission and OpenCode restrictions remain intact.

Branch main, HEAD `0a3e91c731a716945853a6b84bcfaaf6d9e672d3`. The working tree remains dirty with the pre-existing voice/UI work preserved; the index is empty. Full status and iteration-only diff: `Evidence/UIRefinement3/final-git-status.txt`, `ui-only.diff`. No staging, commit, push or remote creation. Evidence/build products stay ignored.

Remaining: exact-size live UI/accessibility checks above; conservative historical speech classification can undercount ambiguous cancellation records; heatmap/metrics cover retained saved data only. Repeated ChatGPT insertion remains a separate unverified concern and is not fixed or claimed fixed by this UI work. Stop after Iteration3.
