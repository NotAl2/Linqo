# Release review — 0.4.1 preview

Reviewed on 3 November 2026. Linqo is in active development; this is an Android ARM64 prerelease, not a completed store release or a guarantee of extraction accuracy.

## Code and app review

Reviewed save/edit/delete transactions, attachment handling, indexed search, migrations, asynchronous metadata/title updates, title ownership, preview network/image bounds, durable Android share receiving, model import/download verification, cancellation/lifecycle cleanup, startup and release packaging. Existing phone/emulator evidence was checked against the current implementation. This is a bounded engineering review, not an exhaustive security audit.

Two concrete defects were found and fixed:

1. **Preview recovery stopped at sixteen saves.** Recovery now traverses bounded pages using a stable ID cursor. A restart regression creates 41 offline link saves and confirms all receive metadata; failed rows do not block traversing older saves.
2. **Replacing an attachment retained the old private file.** After the replacement database transaction commits, the controller removes the former app-owned copy. A regression verifies that a failed transaction preserves the original file/record, a successful replacement removes only the old copy, and deleting the save removes the replacement.

Added optional **Settings → Support Linqo → Buy me a coffee**, opening `https://buymeacoffee.com/notal2` externally with an actionable failure message. GitHub funding and README links use the same destination. Added **Open-source licenses**, including the application's Apache-2.0 license and bundled font notices.

## Automated verification

- All **86 unit/widget tests passed**, including both new regression cases and existing migration, sharing, title protection, preview, download, cancellation, evidence, persistence and responsive-layout tests.
- Static analysis passed with no issues. The emulator integration test passed for support controls and licenses navigation in light, dark and 2× text variants; all three screenshots were inspected without overflow. These are debug-mode layout/interaction checks, not performance benchmarks or a payment test. The donation URL is opened externally; no payment processing is embedded in Linqo.
- Normal `lib/main.dart` release APK built successfully: version 0.4.1, Android version code 5, minimum API 29, 71,844,380 bytes (about 68.5 MiB). ARM64 is the supported release runtime. Archive inspection confirms no model, partial download, test TLS fixture or signing key; app/dependency license assets are present.
- Current release APK SHA-256: `0fb436311b55a96e9dc01df870dd19dc59f69a4f542fb101290376dc81c788b6`.
- Earlier 0.4.0 was installed in place on a physical Edge 50 with its zero-save count, Light preference, existing compact model and two-thread setting retained. This 0.4.1 pass uses a separate emulator QA database and does not change the user's physical-phone data. It does not re-run a model accuracy/performance benchmark.

## Remaining limitations

- Instagram/public metadata availability varies; restricted sources can retain fallback covers. A thumbnail is not a video transcript.
- Webpage readable-content extraction, full supported captions, transcription, OCR, export/backup, sync, semantic search and iOS native support are not implemented.
- English extraction needs supplied text, sufficient device memory and a separately downloaded/imported model. Context/output limits and small-model errors remain. Existing source recovery rules are conservative, not universal recipe/place understanding.
- Broader accuracy, thermal, battery, low-memory and file-provider/viewer testing remains necessary. No new inference performance benchmark is claimed for this release.
- The APK retains the existing development signing identity for compatibility with earlier test installs. Production signing and a deliberate migration strategy remain future work. Private signing material is never included in source.
- Current Flutter emits a `file_picker` Kotlin migration warning; the pinned toolchain builds, but future Flutter upgrades need a compatible plugin.
- Android backup is disabled and export is absent. Uninstalling or clearing storage removes local data. Updates must be installed in place.

## Public-source boundary

Source includes the app, native Android project, pinned dependencies, tests, reproducible build instructions, license notices and synthetic demonstration screenshots. Local SDKs/caches/models, signing keys, private app databases, raw phone traces and development-session records are excluded. Release APKs and checksums are separate release assets, not committed binaries.
