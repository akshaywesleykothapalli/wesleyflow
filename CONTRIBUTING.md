# Contributing

Use a full Xcode 27 toolchain on an Apple Silicon Mac. Keep the working dictation, insertion, clipboard, cancellation, language and permissions contracts intact.

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
python3 -m unittest discover -s Tools/CI/tests
python3 -m unittest discover -s Tools/Telugu/tests -p test_local_packaging.py
python3 Tools/CI/repository_checks.py
python3 Tools/CI/run_checks.py test --output Evidence/ContributionCheck
python3 Tools/CI/run_checks.py concurrency --output Evidence/ContributionCheck
```

Use a fresh output path for each native test run. Tests must use disposable fixtures; do not automate a user's microphone, clipboard or external editor. The default native lane excludes graphical checks, which must be run explicitly for UI changes. Native UI fixture captures may contain test data and belong in ignored local evidence, not publication artifacts.

Do not commit model weights, raw recordings, private transcripts, credentials, generated applications, DerivedData or evidence bundles. Preserve licensing notices and pinned model/XCFramework checksums. Do not relax delivery verification or automatically resend uncertain text.

Before pushing, inspect `git status` and the staged diff, run the relevant checks and commit the reviewed changes. Use ordinary pushes; do not rewrite public history to remove development labels. Historical documents and regression test names are retained for traceability; they are not product UI.

For distribution, configure a real signing identity and notarization. The explicit local ad-hoc preparation helper is for development on the local Mac and is not a production-signing replacement.
