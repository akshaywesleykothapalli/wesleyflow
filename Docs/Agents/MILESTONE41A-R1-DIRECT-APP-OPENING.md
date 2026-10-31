# MILESTONE 41A-R1 — Direct installed-app opening

30 October 2026, Asia/Calcutta. Build **41.0.2** (marketing version 0.1.0), arm64. Corrects the user's report that “Open WhatsApp” produced Reply needed and opened Command Mode. Physical speech verification remains pending; native metadata resolution was checked read-only with zero application launches.

## Diagnosis and correction

41A's `PersonalAgentDialogue.intake` treated an unmatched complete app request as a missing app-name question. `askAgent` then requested the Command Mode screen. Once that question was pending, a fresh full command such as “Open WhatsApp” was consumed literally as an app-name answer, compared against installed names including the word “Open”, and could repeat the question. This is a reproducible retry-loop defect; complete app requests now replace an earlier app question.

The prior native catalog only enumerated immediate children of three Applications folders. It used a display name and a few hard-coded aliases, omitted arbitrary bundle/file/localized names and nested utilities/vendor/PWA folders, truncated the alphabetically sorted result at 300 apps, and then depended on a Launch Services lookup at execution. Those were additional installed-app coverage limits.

On this Mac, `/Applications/WhatsApp.app` exists with identity `net.whatsapp.WhatsApp`; its display name starts with an invisible U+200E mark and its bundle name is WhatsApp. The prior resolver's alphanumeric normalization and explicit alias should already match the exact isolated transcript “Open WhatsApp”. Therefore this report does **not** claim that hidden character caused the user's particular speech failure. The original session's exact transcript and loaded executable were not established. The confirmed code defects above and the unwanted complete-name question behavior are corrected; physical acceptance is still required.

The production path is now:

Agent press/release → existing reliable final transcript → dialogue recognizes complete app request → exact normalized installed-name resolution → typed `openInstalledApp` plan with immutable bundle ID → existing durable routine executor → `NSWorkspace.openApplication` using the discovered bundle URL → existing launch receipt.

For a unique installed match this path neither calls the language model, asks for a reply, registers a command, requests plan approval nor redirects to Command Mode. Existing approval for messages is unchanged. The ordinary dictation shortcut continues to insert words rather than execute them.

## What changed

- Discovery traverses standard `/Applications`, `/System/Applications` and the current user's Applications directory, including nested utility/vendor/localized folders. App bundles and unrelated packages are not recursively searched. It is bounded to six directory levels, 16,384 visited entries and 2,048 distinct app identities; mounted/downloaded apps outside these installation roots are not a universal filesystem search.
- Matches use localized/raw display name, localized/raw CFBundleName, filename, installed bundle identity and retained explicit common aliases. Matching ignores case, diacritics, width, punctuation and spacing, including “Whats App”/“What's App”. No per-app user registration is needed. Unknown phonetic guesses are not silently launched.
- Exact full installed names take priority over optional “the app”/“application” prefixes and “app”/“application”/“.app” suffixes. This protects actual names containing those words.
- Linked `.app` bundles are resolved and indexed; ordinary directory symlinks are not traversed. Multiple copies of one bundle ID collapse to one identity and retain aliases. Different IDs with the same matching name fail as ambiguous instead of choosing arbitrarily.
- Execution revalidates the indexed bundle ID and opens the discovered actual path. An installed app no longer needs a successful prior Launch Services registration just to locate its bundle.
- Catalogs refresh on each request/target check, so a newly installed app can be discovered without restarting. The deterministic catalog bound increases from 300 to 2,048; the model prompt still lists at most 300 names to avoid growing its context budget. Model memory admission/leases are untouched.
- Fully named unknown/ambiguous app requests now show **App not found** / **App name ambiguous**, with no pending question or forced Command Mode. The latest heard request remains visible in the existing interface. There is no fallback to dictation or auto-insertion. Deliberately incomplete “Open” can still ask which app; note/search/message field questions remain supported.
- The same direct matching also handles normal close/quit requests. Closing still means normal app termination with native save dialogs respected, never force quit.

Source: `NativePersonalApps.swift` (discovery/target); `PersonalConversation.swift` (name resolution/bounds/failures); `PersonalAgentDialogue.swift` (direct named requests/retry reset); `SystemWideDictationCoordinator.swift` (compact error status); `ApplePersonalPlanner.swift` (retain 300-name prompt limit); `GlobalDictationTests.swift` (regressions); project build identity 41.0.2. No shortcut, audio, speech, insertion, clipboard, permission, native-message or durable engine implementation changed in this corrective milestone.

## Verification

- **129 focused expanded cases passed**, zero failures.
- Full headless Debug build/tests: **1,505 expanded cases passed**, zero failures.
- Independent test-without-building replay: **1,505 passed**, zero failures. Existing CI required test selection and the unchanged four graphical exclusions were validated.
- **Release and Swift 6 complete strict-concurrency builds passed**, Xcode 27 / Swift 6.4 / macOS 27 SDK, arm64, deployment target macOS 26. Active architecture only, indexing disabled, dwarf information and one compiler job as in 41A. Existing metadata/test-runner OS notices remain in logs.
- **13 CI helper tests passed**; tracked-file/reachable-history repository scan and `git diff --check` passed; packaged code signature verified.

New expanded cases cover speech variants of WhatsApp, generic installed names, literal exact-name priority, absent/ambiguous names, a catalog beyond the old 300-name limit, nested app bundles, bundle/display/file aliases, app links, helper exclusion, refresh after installation, Agent voice execution without Command Mode, unknown-name error without a question, recovery from a prior question and stale-question button rejection. The existing dictation/Agent separation, message approval/edit, cancellation, recovery and model-denial regressions remain in the full suite.

The read-only host probe confirms that the real installed WhatsApp metadata resolves “Open WhatsApp” directly to `net.whatsapp.WhatsApp`, and `target` returns `/Applications/WhatsApp.app`. It prints `launches=0`; the tool runner is not invoked. This establishes catalog/planning/path resolution on this host, not physical speech recognition or launch success. Integration executions use fixtures.

An initial focused run exposed a native file-enumerator issue in the new traversal: calling `skipDescendants` on a symlink/leaf could suppress the following directory. The correction only skips real directory descendants, supports linked application bundles and retains their aliases. The initial fixture test also expected a legacy quick-plan display name to be a bundle ID; that assertion now resolves the step identity correctly. Its unguarded indexing after a failed count assertion crashed the test process; the test now uses a required count before indexing. That aborted run is preserved under `initial-*` and is not counted as passing. Only final unprefixed results count.

Evidence: `Evidence/Milestone41A-R1/manifest.json`, baseline/source backups, milestone-only diff, source and preservation hashes, final summaries/trees/xcresults, logs, metadata fixture probe and signature verification. The native model was not invoked. No app/clipboard/history/model data was purged; nothing staged, committed, pushed or merged. Existing 38/39/40/41 uncommitted work was preserved.

## Identified build and later acceptance

Release build **41.0.2**, signature verified:

`/Users/akshaywesley/Developer/WesleyFlow/Run/Milestone41A-R1-41.0.2-84c23bb6/Wesley Flow.app`

Executable SHA-256: `84c23bb6ec7407848f7e41d805a6c40aab21e84602e7d0c35d63abef96cfa35e`.

The prepared production bundle is **not launched** and the user's running copy is not replaced. Headless test processes are separate verification instances. For this fix to take effect, the identified 41.0.2 build must be used.

When ready later, finish/cancel any active task and resolve any clipboard recovery in the old copy, quit it normally, then open this exact bundle. Check build **41.0.2** and General's **41A-R1 / speech38L3R3** marker; retain the working Agent binding.

1. From a disposable text editor with a clipboard sentinel, hold Agent and say “Open WhatsApp”; release. Expect the real app to activate directly, without Reply needed, Command Mode, approval or inserted text. Repeat “Open Brave” and another installed app by its actual displayed name.
2. Try “Open Whats App” and “Open the app WhatsApp”. If the actual speech result differs, inspect **Your words** in the existing Latest request disclosure; no silent phonetic substitution is promised.
3. Say “Open NoSuchInstalledApp”: expect the compact App not found error, no launch and no forced Command Mode. Then “Open WhatsApp” must work directly. Say only “Open”, then give the full “Open WhatsApp” request: the old question must not trap it as a literal answer.
4. Repeat ordinary dictation of “Open WhatsApp” into the editor. It must insert the words without opening an app. Check clipboard sentinel and back-to-back hotkeys. Native permissions, physical microphone recognition and launch outcomes remain user-operated checks.
