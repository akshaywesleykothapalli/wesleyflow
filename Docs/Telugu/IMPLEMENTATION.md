# Offline Romanised Telugu: repository audit and slice

Audit: 2026-11-01. Repository `/Users/akshaywesley/Developer/WesleyFlow`, initial HEAD `c1a9a3e`, clean `main`. The ChatGPT project directory is a reference mirror, not this Git repository.

- App: native SwiftUI, macOS 26 arm64, Swift 6, local WesleyFlowCore package. Explicit project source membership.
- Capture: AppleDictationInput implements DictationInput, AgentDictationInput, metering, diagnostics and recovery. Apple SpeechTranscriber/DictationTranscriber with legacy on-device fallback. No Parakeet/WhisperKit/whisper.cpp implementation found in production source.
- Gesture: NativeDictationShortcut supplies bound origin identity; SystemWideDictationCoordinator captures the original target before microphone startup, filters short presses, requires release before insertion, ignores callbacks for old sessions, and has an eight-second finalization watchdog.
- Delivery: TextInsertionService preserves target identity, clipboard leases, verification and no-second-dispatch rules. Terminal stays manual copy. No changes to these policies are needed.
- Dictionary: DictationFormattingOptions has protected vocabulary and explicit phrase replacements. DictationPreferenceStore stores version-one Codable preferences with backward-compatible defaults.
- Tests: Swift Testing app suites plus package suites; four graphical layout checks are explicitly manual in existing CI. Existing regression counts are historical until rerun.
- Permissions/signing: microphone usage text and audio-input entitlement already present; hardened runtime and ad-hoc local signing. Production distribution signing is a separate gate.

Implementation boundaries: English/Agent capture continues through AppleDictationInput unchanged. New mode selects local multilingual Small; automatic language identification is default and Telugu-only is explicit. The recognizer owns one serial context, with no runtime network client. Romanisation and whole-token loanword restoration are deterministic; explicit user replacements take priority. Telugu skips English spelling/LLM cleanup.

Verification results and known limitations will be appended after actual builds and tests.
