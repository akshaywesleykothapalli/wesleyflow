# Wesley Flow

Native voice dictation and text formatting for Apple Silicon Macs. Hold Fn to dictate into a supported text field, then use Option+1 to polish the wording or Option+2 to turn it into a clear prompt.

## Features

- English dictation using installed Apple on-device speech engines.
- Offline Romanised Telugu with Telugu-only and automatic Telugu/English recognition modes.
- A compact recording pill, configurable dictation and Agent keys, and language switching.
- English Smart Polish and prompt formatting through Apple's on-device AI, with local formatting for protected sentences.
- A personal dictionary, phrase replacements, punctuation and text cleanup controls.
- Local history, activity insights, appearance and launch-at-login preferences.
- Command Mode for supported dictation controls and Mac actions, with review for sensitive actions.

## Get started

1. Build and open Wesley Flow on an Apple Silicon Mac running macOS 26 or later.
2. In General, choose English or Telugu (Romanised), review the requested microphone, speech and Accessibility permissions, and enable hold-to-talk.
3. Click inside a supported text field, hold Fn, speak and release.
4. In Smart Formatting, enable formatting shortcuts. Enable Smart Polish or prompt formatting as desired, then press Option+1 or Option+2 after dictating. On-device AI features require Apple Intelligence to be available on the Mac.
5. For Command Mode, configure the separate Agent key in General. Supported commands are listed in the app. Agent requests are not pasted into your text field.

No chat message or prompt is submitted automatically. Formatting replacement requires an unchanged, verified last dictation and editor support. Unsupported or unverified delivery retains the transcript for review.

## Telugu setup

Telugu uses local Small model files verified by size and SHA-256. Telugu-only needs the specialist model; automatic language recognition also needs multilingual Small. Acquisition is explicit and separate from inference:

```sh
python3 Tools/Telugu/install_model.py --model both
```

This downloads approximately 752 MB of pinned model files. To install an already acquired model without networking, use `--model telugu --source /path/to/model` or `--model multilingual --source /path/to/model`. Models are stored in the user's Application Support directory and are not included in Git. See [setup and model provenance](Docs/Telugu/RECOGNITION-QUALITY-FIX.md) and [third-party notices](THIRD_PARTY_NOTICES.md).

## Build and verify

The currently verified lane uses Xcode 27, Swift 6.4 and the macOS 27 SDK on Apple Silicon. The deployment target is macOS 26; runtime acceptance on macOS 26 is still pending. Open `WesleyFlow.xcodeproj`, select the WesleyFlow scheme and My Mac. No Ollama server or separate coding model is required.

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
python3 Tools/CI/run_checks.py test --output Evidence/ReleaseCheck
python3 Tools/CI/run_checks.py concurrency --output Evidence/ReleaseCheck
```

Choose an existing full Xcode path on your Mac. The package uses a checksum-pinned whisper.cpp XCFramework fetched at build time. Tests use fixtures and do not record audio or type into your applications. See [contributing](CONTRIBUTING.md) for additional checks and [release notes](RELEASE-NOTES.md) for the current checkpoint.

## Privacy and delivery

Once the necessary resources are installed, speech recognition runs on-device with no configured cloud transcription fallback. Wesley Flow does not save microphone audio. Optional dictation history is local plaintext protected by your user account and can appear in backups; manage it in General.

Supported browser editors use guarded clipboard paste. Successful verified delivery restores the previous clipboard when ownership permits. If delivery is uncertain, the app preserves the backup for explicit recovery and never retries the old text. After recovery, return to the field for a fresh Fn recording. Newer clipboard contents are preserved. Password/secure fields are excluded; Apple Terminal is manual-copy only.

The app's network switch governs its own HTTP connections, not macOS services or other apps. English/AI assets are managed by macOS. No private accessibility activation flags, background microphone capture or automatic message sending are enabled.

## Release status

Version 1.0.0 is a source and product-interface checkpoint of the current working app. The repository does not contain a Developer ID-signed/notarized distribution or an App Store release. Local ad-hoc development signing is supported; production distribution requires your own signing identity and notarization. Editor compatibility depends on the application's exposed accessibility data and requires physical acceptance on the target Mac.

CI configuration is included. Hosted results must be checked for the exact pushed revision; local checks are not a claim that a future GitHub run has passed. Private history, weights, recordings, build outputs and raw verification evidence are excluded from Git.

## License

[MIT](LICENSE). Third-party code and models retain their own licenses: [third-party notices](THIRD_PARTY_NOTICES.md). [Engineering records](Docs/Engineering/DEVELOPMENT-HISTORY.md) preserve historical work separately from the current product instructions.
