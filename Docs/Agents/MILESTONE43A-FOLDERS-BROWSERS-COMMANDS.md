# Milestone 43A — Folder commands and named-browser searches

Build 43.0.1. Implementation and automated verification complete for the capabilities below. Physical folder effects, native permissions and browser handoffs remain pending. The user reported the preceding 42A app/window/dictation behavior working; this report does not infer physical acceptance of new features from fixtures.

## Requested behavior and scope

The user clarified creating, opening, closing, deleting and finding folders, plus searching in Brave or Safari. Existing generic installed-app resolution and open/close/minimise/restore/full-screen/maximise actions remain available across supported installed applications, rather than per-app macros. This milestone adds typed folder and named-browser tools, not unrestricted system control or arbitrary generated scripts.

Examples accepted by Agent voice and typed Command Mode:

- Create folder Projects in Documents
- Open folder Projects in Documents
- Open Downloads
- Find folder Projects in Documents
- Close folder Projects in Documents
- Delete folder Projects in Documents
- Search for Swift tutorials in Brave
- Search Safari for train times

Folder actions require an explicit Documents, Desktop or Downloads location. Named targets are direct children of that root; folder search can discover deeper matches. Hidden names, path separators, traversal, symlinks and application packages are refused for mutations/opening. Unquoted compound commands are refused; paired double quotes support a name such as "Research and Development". Identical complete speech requests repeated two to four times are folded into one plan. Missing folder details produce a folder-specific instruction rather than an accidental web search. This is a bounded deterministic grammar, not arbitrary natural-language comprehension; unavailable-model requests still fail honestly.

## Native execution and approval

PersonalFiles.swift defines validated serializable folder/browser payloads and parser rules. PersonalAgent, PersonalConversation and PersonalAgentDialogue route these to the existing durable typed execution system. NativePersonalTools dispatches to NativePersonalFolders. AppComposition resolves reviewed Trash identities before enqueueing; the coordinator and existing Command Mode show readable target/status and the existing immutable displayed-plan approval boundary. Help expands the command library; review collapses it so the target remains visible. Folder results appear immediately; clicking their HUD opens the results without starting another capture.

Create uses an opened standard-root directory descriptor and mkdirat; an existing real directory is an idempotent success without overwriting contents. Open verifies a real directory and records accepted native folder-open handoff, not a claim that Finder contents were inspected. Close uses one fixed Finder AppleScript, matching the actual folder alias and then rechecking its unique Finder window ID. Multiple matching windows are refused. Only that exact matching window can close; it never quits Finder. No match is reported as already closed. Finder Automation consent can be required and denial remains a failure. The fixed script was compiled, never executed by verification.

Find scans readable folder metadata, with a maximum of 2,048 entries, four levels and ten matching results. Hidden items, packages and symlinks are skipped; unreadable-directory counts are shown. It is neither a full-Mac index nor a content search. Results are paths, not automatic mutations of discovered matches.

Delete means move the named folder and its contents to Trash, never permanent erasure. It always requires the user to click Move reviewed folder to Trash for the exact displayed plan; routine authorization and spoken requests cannot self-approve. The standard root and child device/inode/birth identities are captured before review and rechecked before recycling. Missing/replaced targets fail instead of being substituted. Completion requires the authoritative NSWorkspace recycle success mapping and absence of the original entry; readable Trash destination identity must match. If macOS denies destination readback, the receipt explicitly reports native completion/source absence and the readback limitation without asking for broader Trash access. Native filesystem operations have a small unavoidable race between identity validation and the path-based recycle API; this is not an atomic identity-bound filesystem transaction. Cancellation or failure after a possible effect retains conservative review/recovery semantics; no blind automatic retry is introduced.

Safari/Brave searches encode the literal query in a fixed Google HTTPS search URL and open it with the requested installed browser identity. Missing Brave does not silently switch to another browser. The receipt establishes accepted handoff, not loaded results or page reading. Browser searches require normal network connectivity; command parsing does not call a cloud AI API.

## Preservation and limitations

The existing Fn dictation and separate Agent capture pipeline are preserved; no new text insertion, send key, clipboard publication or speech implementation is added here. Agent transcripts continue directly into the planner, not into the foreground editor or a ChatGPT/Codex conversation. Existing 42A clipboard-free delivery remains, including conservative unverified delivery and manual-copy limitations. No existing recovery backup is discarded during deployment. Existing application/window effects, Messages final approval, journal ordering, cancellation and recovery stay in the same engine.

No model generation, model download, cloud speech/API, arbitrary shell, unrelated-file modification or new communication capability was added. The existing 4 GiB model-admission floor remains. Native privacy permissions still apply to protected folders and Finder automation. Tool enum cases were added without wiping task storage: the new build reads existing records, while an older build cannot decode new-tool tasks and must not be used to downgrade a queue containing them. This milestone does not claim every possible OS task or phrasing is supported.

## Verification

Final results: {"focused": {"exitCode": 0, "cases": 199, "failed": 0}, "test": {"exitCode": 0, "cases": 1575, "failed": 0}, "replay": {"exitCode": 0, "cases": 1575, "failed": 0}, "release": {"exitCode": 0}, "concurrency": {"exitCode": 0}}. Focused and full headless Debug, independent test-without-building replay, Release and Swift concurrency builds passed. The existing four graphical exclusions remain manual. Final signed microphone and Automation entitlements and Release signature verified. Earlier compile/review runs are retained with prefixes; only the unprefixed summary is the final result.

Tests cover folder grammar and repeated speech, invalid names and compound rejection, quoted names, literal browser queries and fixed host/browser identity, scoped temporary-directory creation/idempotence, symlink refusal, replaced-target/root identity rejection, Trash authorization refusal before execution, simulated post-move source/destination verification and result-HUD navigation without recapture. Tests only create/move disposable temporary fixtures; they do not recycle user data, open browser pages, close Finder windows or inject live speech/text. Native script compile-only success is recorded separately from physical acceptance.

Prior uncommitted source was backed up under Evidence/Milestone43A/Before. New source hashes and final verification evidence are archived alongside this report. No staging, commit, push or merge occurred. Canonical installation target is /Applications/Wesley Flow.app, version 43.0.1, executable SHA256 e83d5490963c35530dcd217355219f7b849223d8ca20508da873e60fd7a50c88. installation.json records actual normal quit and replacement. No versioned Run app copy is created.

## Later user-operated acceptance

Confirm version 43.0.1 and marker 43A / speech38L3R3. Use a disposable name: Create folder Wesley Test in Documents; inspect Finder, then Open folder Wesley Test in Documents, Find folder Wesley Test in Documents and Close folder Wesley Test in Documents. Confirm only the matching Finder window closes. Test Delete folder Wesley Test in Documents by rejecting the first review and confirming it still exists; then approve a fresh review only for this disposable folder, inspect Trash and confirm the source disappeared. Do not approve a valuable folder merely for testing. Test changed targets, denied folder/Finder access and ambiguous Finder windows; failures must not be Done.

Try Search for Swift tutorials in Brave and Search Safari for train times; inspect the actual named browser/query. Test a missing browser and no network. Repeat Open/Close/Minimise/Restore with another installed app. Back-to-back Fn and Agent holds must retain separate behavior: in a clicked disposable editor, Fn should insert dictation with waveform/Transcribing and then hide; Agent should execute a command without inserting its transcript. Check a clipboard sentinel, cancellation, rapid repeats and longer recordings. Physical results remain pending until the user operates these checks.
