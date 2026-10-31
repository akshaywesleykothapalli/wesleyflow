# Milestone 41A-R3 — App discovery and hotkey cancellation recovery

30 October 2026, Asia/Calcutta. Build 41.0.4. Physical acceptance pending.

Agent's cancelled-event handler did not clear agentHeld. Escape, another modifier, tap recovery or cancellation could leave it latched: another Agent press was ignored and ordinary Fn was blocked by agentHeld. The handler now releases that latch before cancellation. It does not synthesize a press or execute a command. A regression repeats six press/cancel cycles without release notifications, then verifies ordinary capture remains available.

Discovery now uses a bounded breadth-first folder scan rather than stateful directory-enumerator skipDescendants calls. Most importantly, the prior skipsHiddenFiles option excluded Finder-hidden installed app links: the read-only host probe initially missed Safari. Including those entries while excluding dot-named paths finds Safari's system link. Application packages are still not traversed. VS Code/VSCode/Code aliases are derived for the installed com.microsoft.VSCode identity. Unique installed identities remain required; no fuzzy auto-launch or cloud fallback.

The final read-only host probe finds all four actual installed identities: WhatsApp, Brave, VS Code and Safari. It reads metadata only and does not launch them. This does not establish the exact transcription or executable used in the user's failing session. Other recognition/permission/event-delivery failures remain possible and physical acceptance is pending.

Final verification: 141 focused cases, 1517 full Debug cases and matching test-without-building replay passed, zero failures. Release and complete Swift concurrency builds passed. Existing four graphical exclusions remain untested. Earlier before-safari results are retained separately and are not the final source result.

Normal dictation insertion, speech implementation, clipboard handling, secure checks, offline planner constraints and explicit message approvals were not changed. Existing uncommitted work was backed up. No commit, staging, push, merge, app replacement or productive native action.

Prepared bundle, signature verified, NOT LAUNCHED:

/Users/akshaywesley/Developer/WesleyFlow/Run/Milestone41A-R3-41.0.4-152972ca/Wesley Flow.app

Executable SHA256: 152972caab9cc95ca34226a7c7825120a5cd20c09dfdb23e5b708686a083d99c

For later physical acceptance, resolve pending clipboard recovery and finish/cancel active work, quit the previous copy normally, then open this exact bundle and check build 41.0.4 / marker 41A-R3. Test each reported app by Agent voice after restart, then six successive holds, Escape cancellation without release, and alternating Fn/Agent. Verify actual app activation, no unintended insertion, and clipboard preservation. Do not infer physical success from fixtures. The old running copy is not replaced by preparing this build.
