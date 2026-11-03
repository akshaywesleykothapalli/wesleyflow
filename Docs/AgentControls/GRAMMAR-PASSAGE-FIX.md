# Smart Polish passage correction — 45.0.14

The supplied 45.0.13 diagnostics reported a completed but unchanged grammar rewrite, with no replacement requested. They did not report a speech or insertion failure. The user supplied “What happened? Yes, I'm checking in, but smoking.” and confirmed that speech recognition works well; this correction leaves ASR unchanged and does not guess a different word for “smoking”.

## Correction

Grammar-mode protection incorrectly froze common question/response words such as What and Yes as names. The common-word list now includes these forms; explicit dictionary entries still take priority. Cleanup-mode protection remains unchanged.

The model-facing editable list previously included empty leading/trailing and punctuation-only gaps between protected spans. It now exposes only passages containing letters, with contiguous indices mapped back to the original fixed-span layout. This prevents an empty edit from satisfying the minimum-one-passage response contract. Fixed-only input returns unchanged without starting generation. Instructions request faithful grammar/wording improvement and preserve contrast instead of replacing “but” with a temporal or causal relation.

These are confirmed input-contract defects; the previous diagnostics do not reveal which passage the model selected, so they cannot prove the exact reason for that earlier unchanged response. Already clear text can still legitimately return unchanged. All existing memory, timeout, cancellation, fidelity and editor-verification guards remain.

## Verification

The actor-checked deterministic package gate passed. Added tests cover ASCII/curly apostrophes, common-word versus explicit dictionary priority, filtered passage numbering, invalid indices and fixed-span reconstruction.

A bounded opt-in real on-device provider test, run with network access denied, returned: “What happened? Yes, I'm checking in, but I'm smoking.” The provider accepted a changed result in 4510 ms; 21 resource samples observed normal/warning pressure, minimum available memory 3037626368 bytes and zero swap growth. The test uses the supplied sentence as synthetic input and does not capture a microphone, manipulate a target editor or log production transcripts. This single result is not a guarantee of every future model response.

The full native Xcode Debug suite passed: 1956 expanded cases across 873 declarations, zero failures. Repository/history checks passed, along with 15 CI tooling tests and 3 local-signing/packaging tests. The arm64 Release build passed with SWIFT_STRICT_CONCURRENCY=complete.  Physical Option+1 replacement in Notes/ChatGPT/Codex remains user acceptance; no scripted external-editor verification was performed. No settings UI changed in this patch.

## Installed handoff

Source commit: `6dadd17`. Build 45.0.14 was installed at `/Applications/Wesley Flow.app` using the existing explicit local ad-hoc signing helper. Signature verification passed; normal Quit was used, and the canonical app survived the 15-second launch observation. Grammar style and last-insertion shortcut mode were already selected; all preference values were preserved. Temporary signing/build/package copies and the previous app backup were removed only after successful launch. Evidence logs/results remain under `Evidence/GrammarPassageFix`; its handoff JSON records executable identity and checks. No production transcript or external editor was read or modified by verification.

User acceptance: dictate a fresh sentence with Fn, then press Option+1 in the same field to request grammar/wording replacement. Option+2 and all speech backends are unchanged by this patch. A fresh anchor is required after the restart.
