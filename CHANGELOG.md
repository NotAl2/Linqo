# Changelog

## 0.8.2 — 2026-11-06 (development preview)

- Expand the native first-start demos: Share → Linqo → optional extraction → done, and a sample caption becoming a recipe with ingredients, method and stated servings. Keep demonstrations finite, skippable, replayable and paused when inactive or processing.
- Classify the whole source before model-sized parts; reject publisher controls and author biographies as recipe evidence. Split supported inline recipe captions into original source spans while preserving the full saved caption.
- Show recipes with readable ingredients and numbered steps, stated serving size, articles with concise bullet highlights, tutorials as ordered instructions and places with their own layout. Remove repetitive per-fact dropdowns; move raw saved content to **View saved source** in the save menu.
- Remove ink splashes and whole-screen selection fading, use purple selection feedback and retain resolved cover handles across filter changes. Keep the existing compact optional model, two threads and local core.

## 0.8.1 — 2026-11-05 (development preview)

- Replace onboarding videos and image decoders with a native Flutter tutorial: short transitions, sample save feedback and collection choices. Retain Skip, replay, reduced-motion support and optional model setup. Remove bundled video/tutorial image assets.
- Remove the paid-unlock, quota, account and purchase-restoration integration and its cryptography dependency. Keep Linqo unlimited with optional Buy Me a Coffee donations. Set the unused licensing prototype aside outside the app and disable its hosted processing.
- Keep the local core and existing optional online caption/preview fetching, model download and manual GitHub update checks.

## 0.8.0 — 2026-11-05 (development preview)

- Add a skippable first-start welcome tour, replayable from Settings, with three lightweight Brag/Hyperframes tutorial clips for saving, organizing and optional AI. Respect reduced motion, backgrounding and extraction activity.
- Refine navigation easing and tab feedback while retaining library state and scroll positions. Keep routine motion short and avoid per-row animation work during extraction.
- Add manual GitHub release checks, semantic version comparison, a preview channel switch and a trusted release-page action. Never download/install updates silently.
- Add hidden, opt-in local diagnostics: tap the version seven times. Record bounded event codes, error types and sanitized Linqo stack locations, with export/clear controls and no automatic upload. Native process crashes may not be captured.
- Harden model downloading with exact pinned byte-count checks, stricter resume validation and bounded buffered writes. Cancel stalled native part streams; keep two CPU threads and on-demand memory release.
- Prototyped paid unlocking during development; this was removed from the app in 0.8.1. Donations remain optional.

## 0.7.0 — 2026-11-05 (preview)

- Replace model-written summaries with verified source excerpts selected by line reference. Re-ground existing summaries and backup imports, including the local search index, while preserving user fields.
- Process long saved text as token-checked parts within the existing context and two-thread defaults. Show part progress, retain original content and flag incomplete coverage. Retry prior context-limit failures after upgrade.
- Prefer article bodies over surrounding follow/thread controls when fetching webpages. Filter Google follow controls and hidden credits; use article-aware classification to avoid treating general articles as recipes or unrelated place lists.
- Add model deletion/redownload and check file presence/integrity on startup, foreground, Settings and before loading. Recover a single verified model whose selection manifest was lost, and clear stale installed/error states.
- Validate with 124 host tests, clean static analysis and physical Redmi Note 7 Pro tests for the supplied long article, grounded recipe extraction, cancellation, missing-file recovery, deletion and fresh model download. Keep the optional model and two CPU threads; preserve library data and preferences during updates.

## 0.6.2 — 2026-11-05 (preview)

- Add the optional Support Linqo popup after the first successful save, then at spaced random save intervals with a seven-day cooldown and at most one popup per session.
- Include Buy me a coffee, Later and a persistent Don’t show again checkbox. Wait for a quiet foreground library screen; edits, duplicate share receipts and imports do not advance reminders.

## 0.6.1 — 2026-11-04 (preview)

- Harden low-memory recovery: stop and drain native work, release the model, preserve interrupted saves and keep later foreground saves eligible for automatic extraction.
- Clear stale extraction results when a new source is rejected, preventing the previous save's output from being reused.
- Add physical-device coverage for automatic public reel captions, complete recipes, named places, cancellation, retry and Android memory warnings on a Redmi Note 7 Pro. Keep two CPU threads and the compact optional model.

## 0.6.0 — 2026-11-04 (preview)

- Show “Already installed” for the verified compact English model, including after restarting, and guard against redundant downloads.
- Add ZIP export/import for saves, notes, extraction results, favourites, collections and file copies. Imports merge by persistent backup IDs, preserve existing edits/settings and rebuild local search.
- Add a short “Why we made Linqo” section in Settings.

## 0.5.1 — 2026-11-04 (preview)

- Keep creator credits, social calls to action and hashtags out of recipe ingredients and preparation steps.
- Validate model-selected preparation text and flag ingredient-only captions as incomplete instead of claiming instructions are available.
- Verified automatic caption fetching and native extraction on a physical Android phone with the existing optional model and two threads. Added regression tests and a separate-library phone test to protect existing saves and settings.

## 0.5.0 — 2026-11-04 (preview)

- Automatically fetch public Instagram captions, structured recipe ingredients/steps, readable webpage text, public place data and YouTube descriptions.
- Save immediately; source content arrives in the background and becomes searchable. Keep personal notes and manually edited source text protected.
- Queue optional English summarization automatically when source text and a selected model are ready, retaining two inference threads. Added global/per-save controls and foreground/Stop guards.
- Migrate existing saves without resetting data; empty legacy link sources become eligible for fetching. Retry unavailable content on foreground recovery with a one-minute cooldown.
- Label metadata excerpts and partial content, distinguish video descriptions from transcripts, and preserve sender text alongside fetched captions.

## 0.4.1 — 2026-11-03 (preview)

- Added optional Buy Me a Coffee support in Settings and GitHub funding.
- Added an accessible open-source licenses page with application and font notices.
- Fixed startup metadata recovery leaving older pending saves untouched after the first sixteen.
- Fixed replaced attachments retaining obsolete private file copies; failed replacements preserve the original.
- Published the source under Apache-2.0 with build instructions and explicit active-development limits.

## 0.4.0 — 2026-11-02

- Adopted the cheerful bookmark collector identity: mascot-only Android launcher, full-logo startup and lavender/purple light/dark theme.
- Added offline Fredoka/Nunito typography and responsive mascot placement.

## Earlier development milestones

Persistent library, collections, local search, Android text/link sharing, automatic titles/public previews and optional English on-device extraction. These milestones were private development builds, not prior public GitHub releases.
