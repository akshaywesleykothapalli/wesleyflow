# Wesley Flow 1.0.0

A product-interface and source checkpoint of the current working dictation app.

- Simplified General, Smart Formatting and Privacy settings around the working voice workflow.
- Removed historical phase/build aliases from product-facing status, preview titles and copied diagnostics. Diagnostics retain normal app version/build metadata.
- Removed redundant manual-preview controls, development counters and unused alternate-model wiring from the production composition. Existing settings/history/model files are preserved.
- Kept English/Telugu selection, Telugu-only/automatic recognition, dictionary, Command Mode, Option+1/2, clipboard recovery, permissions and launch/appearance controls.
- Retained the verified short-sentence Smart Polish speed improvement and the guarded browser/empty-editor insertion checks.

The app uses marketing version 1.0.0 and a monotonic internal build number. This does not certify every editor or OS version. Local ad-hoc signing, fixture verification and user-operated acceptance are distinct from a signed/notarized public binary release.

Local verification passed 1993 native cases, a Release concurrency build and four graphical checks, plus the repository tooling/offline gates. See the [checkpoint report](Docs/Engineering/PRODUCT-RELEASE-CHECKPOINT.md) for scope and limitations. GitHub CI has not been claimed for an unpushed revision. Engineering history and regression coverage remain in the repository; no remote push is part of this cleanup.

The local installation was verified as version 1.0.0 (build 46), with preferences preserved. The source checkpoint is committed locally; remote publication remains the owner's next step.
