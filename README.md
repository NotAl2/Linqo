# Linqo

A private Flutter bookmark app for links, reels, videos, places, files and notes—with collections, fast local search and optional on-device AI extraction.

**Linqo is still in active development.** The current Android release is an early preview: features, previews and extraction quality are evolving. Keep originals of important files; export/backup and cloud sync are not implemented.

[Download the latest APK](https://github.com/NotAl2/Linqo/releases) · [Report an issue](https://github.com/NotAl2/Linqo/issues) · [Buy me a coffee](https://buymeacoffee.com/notal2)

<img src="assets/brand/linqo-full.png" alt="Linqo's cheerful bookmark collector" width="170">

## What works today

- Save immediately into a persistent SQLite library, with favourites, editable collections and indexed search.
- Share text/links from Android apps, including Instagram, YouTube, websites and locations. Add private file copies from the file picker.
- Automatic titles and genuine cached preview images, independent of AI. Manually edited titles stay protected; **Refresh details** retries unavailable metadata.
- Automatic source text: public Instagram captions, structured recipe ingredients/steps, readable webpage text, supported public place details and YouTube descriptions are saved when exposed by the provider. No manual caption copying is needed for supported public links.
- Static video thumbnails with a play action that opens the original provider. No autoplay, embedded browser or video downloading.
- Lavender/purple mascot theme, rounded offline fonts, light/dark/system appearance, adaptive phone/tablet layouts and reduced-motion support.
- Optional English text extraction: summaries, recipe details and places with source evidence. A serial worker keeps browsing available, and extraction can be stopped.
- Optional support link in **Settings → Support Linqo**. No donation is required to use the app.

<img src="docs/screenshots/library-light.png" alt="Linqo library with synthetic sample saves" width="260"> <img src="docs/screenshots/library-dark.png" alt="Linqo library in dark mode" width="260">

Screenshots use synthetic demonstration saves; the app starts with your own library.

## Install

Download the **ARM64 APK** from [Releases](https://github.com/NotAl2/Linqo/releases). Requires **Android 10 / API 29 or newer** on an ARM64 device. Allow installation from your browser/file manager when Android asks.

Install updates over the existing app to retain saves and settings. **Uninstalling or clearing app data deletes saves, collections, notes, imported file copies and models.** This preview uses the existing development signing identity to remain compatible with earlier test installs; it is not a Play Store/production-signed release. A later signing transition may require an explicit migration.

No model is bundled or downloaded automatically. The APK works as a bookmark library without AI. Release assets include a SHA-256 checksum file.

## Optional on-device AI

Settings offers a resumable, checksum-verified download of [Qwen3-0.6B Q4_K_M](https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/blob/50968a4468ef4233ed78cd7c3de230dd1d61a56b/Qwen3-0.6B-Q4_K_M.gguf): **396,705,472 bytes**, about **397 MB**. Importing a local GGUF is also supported. Model licenses are separate from the app license.

Inference runs locally through llamadart/llama.cpp with **two CPU threads**, a 2,048-token context and one active extraction at a time. Selection persists; weights load on demand and unload after processing/backgrounding. Download size is not a RAM estimate: inference can use considerably more memory and depends on your device.

Sharing or saving a link starts public content fetching automatically. The fetched caption, recipe or webpage text appears in **Content for extraction**, independently of the optional model. Sender-provided text is retained; manually edited source text and **Your notes** stay protected. A source label distinguishes captions, caption excerpts, webpage text and video descriptions; a YouTube description is not a transcript.

With a model installed, **Settings → Summarize saves automatically** defaults on. New saves can queue English summarization after their source text arrives; each save can opt out, and Stop remains available. Existing empty link saves are eligible for content fetching after migration. Failed public fetches can retry on restart or returning to the foreground; repeated foreground recovery has a one-minute cooldown per app session. **Retry content fetch** and **Refresh details** are also available. No model is downloaded automatically. Review generated results; source citations do not guarantee factual accuracy.

## Limitations and next work

- Public title/image previews are best effort. Private, removed, region-restricted or login-only posts may show a platform fallback; Instagram access is not guaranteed.
- Public content extraction is best effort. Login walls, private posts, JavaScript-only pages and unavailable descriptions can expose no text. Metadata-only captions are marked as excerpts; no login/session bypass is used.
- Video/audio transcription, protected captions, OCR, semantic search, export/backup and sync are not implemented. YouTube descriptions are supported where public HTML exposes them; arbitrary YouTube subtitle-track downloads are not implemented.
- Up to 30,000 source characters are retained; bounded/truncated results are marked partial. Automatic AI summarization accepts at most 8,000 characters and is also constrained by the model's smaller token budget. Longer sources stay saved and can be shortened in-app. Smaller models can omit or misinterpret details; broader accuracy, thermal, battery and low-memory testing remains necessary.
- File-provider/viewer compatibility and more Android/OEM combinations need testing. Android sharing currently receives text/link shares, not arbitrary image/video-only shares.
- Flutter code is shared, but **no native iOS target is implemented or tested yet**.
- `file_picker` currently emits a Flutter/Kotlin migration warning. It builds with the pinned toolchain; a plugin upgrade is needed before a future incompatible Flutter upgrade.

The [automatic content report](docs/AUTOMATIC_CONTENT.md) and earlier [release review](docs/RELEASE_REVIEW.md) record checks, fixes and practical test boundaries.

## Privacy and storage

Saves and file copies live in private app storage. No Linqo account, hosted inference service or cloud sync is used. Android cloud backup is disabled. Adding/sharing or refreshing a link contacts its public provider for metadata/images; optional model setup contacts Hugging Face, and the donation button opens Buy Me a Coffee externally.

Metadata/content fetching is bounded to two jobs, a ten-second deadline, 1 MiB HTML per response and 700 KiB per image. The thumbnail disk cache is expendable and capped at 16 MiB/80 entries. Browsing uses local cached previews. No login cookies, WebView or JavaScript runtime are used for previews.

## Build and test

Validated toolchain: **Flutter 3.47.7 / Dart 3.13.5**, **Java 21**, Android SDK API 36. Install/configure Flutter and Android SDK first; SDKs, caches, model weights and signing secrets are excluded from this repository.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d <android-device-id>
flutter build apk --release --target-platform android-arm64 --target=lib/main.dart
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. On Windows, `scripts/flutter.ps1` uses ignored project-local tools when present and otherwise your installed Flutter. Release builds currently use the local Android debug signing key; do not distribute private keys in source. Forks build with their own local key, so their APKs cannot update a differently signed installed app.

Device integration harnesses live in `integration_test/`. They use separate QA databases, and some require a selected model or a host-side viewport coordinator. Read each harness before running it. Always build `lib/main.dart` for distribution, rather than a test entry point.

## Code map

| Path | Purpose |
|---|---|
| `lib/library` | SQLite, collections, search and processing orchestration |
| `lib/sharing` | Incoming text/link shares and bounded metadata/image fetching |
| `lib/ui`, `lib/theme.dart` | Native Flutter screens, mascot theme and responsive layouts |
| `lib/domain` | Extraction schema, source evidence and recovery rules |
| `lib/inference` | Model import, optional download and native runtime |
| `android` | Android platform and durable share inbox |
| `test`, `integration_test` | Host regressions and device harnesses |

Bug reports and contributions are welcome. Include Android/device details, reproduction steps and a redacted example when reporting preview or extraction problems. Please avoid posting private saves or model files.

## License and support

Original code: [Apache License 2.0](LICENSE). Fonts, dependencies and optional models retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md), the [accompanying license bundle](THIRD_PARTY_LICENSES.txt) attached to Releases, and **Settings → Open-source licenses**. Keep the license bundle with redistributed APKs; native runtime attribution supplements Flutter's generated list. The license does not grant trademark rights.

If Linqo is useful to you, [buy me a coffee](https://buymeacoffee.com/notal2) to support its development. Donations are optional.
