# Wesley Flow

Wesley Flow is a native macOS app for on-device dictation and voice commands. Hold a key to dictate into a supported text field, polish what you just wrote, or use a separate key to give your Mac a command.

Built for Apple Silicon. [Build from source](#build-from-source) · [Voice commands](#keep-your-mac-awake) · [Telugu setup](#set-up-telugu-dictation)

## Get started

1. Open Wesley Flow. In **General**, choose **English** or **Telugu (Romanised)** and enable **Hold-to-talk dictation**. Grant Microphone, Speech Recognition, and Accessibility access when requested. Accessibility lets Wesley Flow insert text into other apps.
2. Place the cursor in a supported text field. Hold **Fn / Globe**, speak, then release to insert the transcript.
3. To edit the last dictation in place, enable the features you want under **Smart Formatting** and keep the cursor in the original field. To issue voice commands, enable the separate shortcut in **Command Mode**.

| Default shortcut | Action |
| --- | --- |
| Hold **Fn / Globe** | Dictate into the focused text field |
| **Option + 1** | Use Smart Polish to improve the wording of the last English dictation |
| **Option + 2** | Turn the last English dictation into a structured prompt |
| Hold **Right Command** | Speak an English voice command |

Both hold keys are configurable. AI-assisted formatting requires Apple Intelligence to be available. In-place formatting requires a supported editor and an unchanged, verified insertion.

A personal dictionary, phrase replacements, and punctuation controls help tailor the transcript. When local history is enabled, **Dictation** shows saved entries and **Insights** charts activity by app.

## Label saved dictations by voice

Open **Speech Recognition**, enter a name, and select **Add My Voice**. With your consent, Wesley Flow records three short passages to create a local voice profile and discards the recordings. Enable **Label saved dictations by voice** to label future entries. Speech that cannot be confidently matched appears as **Unknown speaker**.

You can delete a profile from the same page. Saved dictations retain their existing labels.

## Keep your Mac awake

Enable the shortcut in **Command Mode**, then hold **Right Command** and speak one of these commands.

| Say | What happens |
| --- | --- |
| “Keep my screen awake until I say turn it off” | Keep the display awake until you stop the session |
| “Keep my screen awake for one hour” | End the session after one hour |
| “Keep my screen awake until this app quits” | End the session when the app in front at the time of the command quits |
| “Keep my screen awake until report.pdf is downloaded” | End the session once a new file with that name appears and settles in Downloads |
| “Cover the screen by keeping it awake for one hour” | Start a timed session with a frosted privacy curtain after Touch ID confirmation |
| “Turn it off” | End the active keep-awake session and let normal display sleep resume |

The privacy curtain covers connected displays. Wesley Flow temporarily disables the Trackpad gesture for switching Spaces in the background. Use **Reveal with Touch ID** on the curtain to show the desktop and restore the prior gesture setting. A timed session can expire while the curtain stays in place, and revealing the desktop can leave the keep-awake session running.

The curtain is an app-level overlay. macOS system controls can bypass it.

## Build from source

Use an Apple Silicon Mac with a full Xcode installation. The verified toolchain uses **Xcode 27**, **Swift 6.4**, and the **macOS 27 SDK**. The deployment target is macOS 26, where runtime acceptance remains pending.

```sh
git clone https://github.com/akshaywesleykothapalli/wesleyflow.git
cd wesleyflow
open WesleyFlow.xcodeproj
```

Select the **WesleyFlow** scheme and **My Mac**, then choose **Product → Run**. Xcode resolves a checksum-pinned whisper.cpp XCFramework at build time. The app runs with local development signing. Public binary distribution requires Developer ID signing and notarization.

### Set up Telugu dictation

Install the local Small models, then choose **General → Language → Telugu (Romanised)**. Use **Telugu only** for Telugu speech or **Auto** for Telugu and English.

```sh
python3 Tools/Telugu/install_model.py --model both
```

Both models together download approximately 752 MB. Telugu-only mode needs the specialist model. Automatic recognition also needs multilingual Small. The installer checks file sizes and SHA-256 hashes before storing the models in your Application Support directory. To use a local copy, pass `--source /path/to/model` with `--model telugu` or `--model multilingual`. See [model setup and provenance](Docs/Telugu/RECOGNITION-QUALITY-FIX.md).

## Privacy and text delivery

- **Speech stays on-device.** With the necessary speech assets installed, dictation uses local recognition with no cloud transcription fallback. macOS manages Apple speech and Apple Intelligence assets.
- **History is optional.** Wesley Flow stores no microphone recordings. If you enable dictation history, transcripts are stored locally in plaintext under your user account and may be included in backups. Manage history in **General**.
- **Your clipboard is protected during supported pastes.** Wesley Flow restores the previous clipboard after verified delivery if it still owns the clipboard. If delivery is uncertain, use the app’s recovery prompt to review the backup. Wesley Flow preserves newer clipboard content and never automatically retries uncertain delivery.
- **You stay in control of submission.** Dictation inserts text for you to review. Wesley Flow never automatically submits a message or prompt. Secure fields are excluded, and Apple Terminal uses manual copy.

Editor compatibility depends on the accessibility information each app exposes. The network switch in **Privacy** governs Wesley Flow’s own HTTP connections. macOS services and other apps manage their own network access.

## Run the checks

Point `DEVELOPER_DIR` to the full Xcode toolchain on your Mac. Use a fresh output directory for each check.

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
python3 Tools/CI/run_checks.py test --output Evidence/TestCheck
python3 Tools/CI/run_checks.py concurrency --output Evidence/ConcurrencyCheck
```

The deterministic checks use fixtures. See [Contributing](CONTRIBUTING.md) for additional checks and the [GitHub Actions workflow](.github/workflows/ci.yml) for hosted CI.

## Release and license

Wesley Flow 1.0.0 is available as source for local builds. See the [1.0.0 release notes](RELEASE-NOTES.md) for the original checkpoint and the [development history](Docs/Engineering/DEVELOPMENT-HISTORY.md) for earlier work.

Wesley Flow is licensed under [MIT](LICENSE). Third-party code and models retain their own licenses. See [Third-party notices](THIRD_PARTY_NOTICES.md).
