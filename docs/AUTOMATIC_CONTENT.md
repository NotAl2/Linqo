# Automatic source content — 0.5.0 preview

Implemented on 4 November 2026. Previously Linqo fetched title/cover metadata but required manually pasted extraction text. Sharing or saving a link now also fetches supported public source content and stores it in the save's extraction body. Saving remains immediate.

## Supported inputs

- Instagram: public captioned embed text; fall back to a clearly labelled metadata caption excerpt. Prefer the fuller embed over early metadata to avoid losing late recipe steps.
- Recipe webpages: structured Recipe ingredients, quantities, servings/times and ordered HowToStep/HowToSection instructions. Preserve final steps and exclude unrelated page navigation/comments.
- Webpages: readable article/main content or prose paragraphs, with a labelled page-description fallback.
- YouTube: creator descriptions when exposed in the public watch page. These are not subtitles or transcripts. No video/audio download or transcription is added.
- Places: explicit structured public place data where available; generic Maps viewer text is rejected, with a labelled name derived from the saved URL retained instead.

Public access varies by provider, region, login/age restrictions and page changes. Private/login-only posts can still expose no usable text. Fetching does not execute JavaScript, use login cookies or bypass access restrictions.

## Data ownership and automation

Source fetching does not require a model. The optional installed model can automatically summarize English source text once it arrives; Settings and per-save controls allow opting out. Existing two-thread, serial native inference, cancellation and memory-release behavior is retained. No model is downloaded automatically.

The SQLite v3 → v4 migration preserves saves, collections, favourites, preferences, notes, attachments and existing manual body text. Empty legacy link bodies become eligible for content fetching. User-edited source text is protected from later requests. Sender text is retained when fetched content is added; personal notes remain a separate field. Source text becomes searchable in the same transaction. Requests for changed/deleted URLs cannot overwrite saves.

Startup/foreground recovery traverses bounded pages. Unavailable content may retry on a later restart/foreground recovery, with a one-minute in-process cooldown and no polling service. Stop/background guards prevent late metadata from unexpectedly starting inference while the app is backgrounded. Failed/cancelled summaries do not automatically loop.

## Bounds

Two concurrent public fetch jobs, ten seconds per job, at most 1 MiB HTML per response and 700 KiB per image. HTML/JSON parsing runs on a worker isolate; scrolling uses local data. Up to 30,000 source characters are stored; truncated content is labelled partial. Automatic AI accepts at most 8,000 characters and is still subject to the model's 2,048-token context. Longer source remains available and editable without copying it from another app. A URL-derived place name alone does not automatically load a model.

## Verification

Host regression coverage includes full Instagram captions beyond 400 characters, final recipe steps, nested structured instructions, article boilerplate removal, matching YouTube descriptions, login walls, content limits, Maps viewer rejection, delayed fetching, sender-text preservation, manual-edit protection, source indexing, automatic inference queueing with a fake runtime/two threads, no-model behavior, opt-out/background guards and v1/v2/v3 migrations. Existing storage/sharing/download/layout regressions are retained.

The final host suite passes **98 tests**. The live Android share/editor → saved body run also passes, and the detail/source/settings captures were inspected. Source fetching ran without a selected model. UI structure and the mascot theme are preserved; the new controls use existing Material components.

Final static analysis is clean. The normal ARM64 `lib/main.dart` release is **71,975,452 bytes** (about 68.6 MiB), version **0.5.0+6**, minimum API 29. Its signing certificate matches 0.4.1 for in-place updates. APK inspection found no bundled model weights, partial downloads, test TLS fixtures or private signing keys. SHA-256: `3b7fbff1d6c8bc33d25a02269965e6ae92cba44b7c65f9b15a6ed08a8969c413`.

A live Android emulator run saved the Instagram link before enrichment and obtained the source automatically, without manually entering captions. A separate QA database was used; no user's normal database or model was altered. Observations:

| Public source | Observed input | Result |
|---|---|---|
| Previously supplied Instagram post `De5LCBKuASV` | 1,084 characters | Full public caption, personal notes untouched |
| Budget Bytes `basic-chili` | 1,430 characters | Structured recipe including ingredients and steps |
| YouTube `aqz-KE-bpKQ` | 229 characters | Video description; page cap conservatively marked partial |
| Wikipedia digital bookmarks (host response) | 11,055 characters | Readable article text |

These are observed fixtures, not universal provider coverage. No new physical-phone AI accuracy, speed, thermal or memory benchmark is claimed. Automatic queue behavior is regression-tested with a fake runtime; the existing native engine is unchanged. Raw fetched pages and real-content UI screenshots remain local, rather than being published in this repository.

Structured recipe fields follow [Schema.org Recipe](https://schema.org/Recipe) and [Google's Recipe documentation](https://developers.google.com/search/docs/appearance/structured-data/recipe). YouTube's official [caption-download documentation](https://developers.google.com/youtube/v3/docs/captions/download) has separate authorization requirements; this implementation only reads publicly exposed descriptions.
