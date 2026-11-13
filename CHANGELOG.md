# Changelog

## 0.9.2 build 27 — Polar paid beta

- Enable account-bound Polar checkout for XL ₹449 / XXL ₹649, preserving Free limits and historical purchase restoration.
- Show purchase/refund, privacy and terms before checkout; clarify sign-in and unavailable states.
- Publish supplier name/country/contact and consistent paid-beta disclosures. Donations and training uploads stay separate.


## 0.9.1 build 26 — offline policy reader fix

- Normalize Windows line endings so bundled legal notices display separate headings and readable body paragraphs.
- Preserve payments-disabled prebuild limits, saves and settings.

## 0.9.0 build 25 — limited prebuild

- Enable Free 100 saves/5 collections, XL 500/30 and XXL without product quotas, independently of sign-in/network setup. Preserve existing/restored over-limit content and installed models. Built-in English extraction and backups remain free.
- Keep payments disabled in both client and backend. Replace unavailable checkout actions with full-prebuild email access requests; donations remain separate.
- Polish account usage, over-limit explanations and tier states. Add offline privacy, terms and access/refund notices, plus full native/dependency attributions in the app.
- Update the README, website and GitHub funding links for the current prebuild. Polar verification/working withdrawals are owner-reported; payments remain paused by choice.

## 0.9.0 — unreleased account/backup beta

- Prepare build 24 with the public Polar checkout flow, provider-specific host/price validation, no in-app phone request for Polar, and updated purchase/privacy disclosures. Keep public sales, paid limits and contributions off pending merchant and release qualification. Preserve historical Cashfree/manual/gift restoration.
- Fix seven CodeRabbit issues: reserve checkout creation atomically, prevent stale account checks from replacing another account's state, respect a disabled public health response, block purchases in unlimited previews without delivered tier differences, correct backup guidance and Boolean build flags, and handle plural searches such as boxes/news. Final focused CodeRabbit review reports zero issues.

- Add isolated Polar evaluation: sandbox UPI checkout and same-Google-account restoration verified in QA; validate separate live INR products read-only. Add version-pinned, signed webhook receipt storage with replay/conflict checks and separate environment secrets. Add account-bound live fulfillment with authoritative order reconciliation, refund revocation and a private zero-total acceptance checkout. Verify a private 100%-discounted live XXL order, signed fulfillment, sign-out revocation and same-Google-account restoration after restart on Redmi QA. Close the private free offer after testing. Public paid checkout and limits remain disabled pending release qualification.

- Add optional Buy Me a Tea support for Indian supporters beside Buy Me a Coffee in the app, GitHub funding links and website. Donations remain separate from paid upgrades.

- Prepare build 23 security update: reject unsafe ZIP metadata before decoding backup contents and atomically reserve payment reconciliation cooldowns. Preserve the existing beta package/signing identity and keep paid limits, live checkout and contributions disabled pending release qualification.
- Prepare build 22 beta candidate with the updated support address aryandurgude123@gmail.com, creator name NotAl2 and a 15-calendar-day upgrade refund-request window. Fix quota enforcement during account startup and cover over-limit backup restoration. Remove retired Shop setup guides/configuration; retain applied database migrations and rejection tests. Cashfree is the only automatic payment provider. Paid limits remain disabled pending controlled live acceptance.
- Add a public product/policy information page to the hosted checkout origin for merchant review, keeping live checkout disabled. Add an explicitly separate Android QA identity for non-destructive account acceptance checks.
- Fix Cashfree requests on Cloudflare Workers by using supported manual redirect handling; reject redirects without forwarding credentials. Add sanitized failure diagnostics and regression coverage. Verify a ₹449 sandbox checkout on the Redmi without granting a real entitlement; live checkout remains disabled.
- Set current prices to XL ₹449 / US$4.99 and XXL ₹649 / US$6.99. Free has 100 saves/5 collections; XL has 500/30; XXL has no product quotas. Add owner-verified manual international upgrades with private Google-linked account codes, maintainer-only grant/revoke commands and signed entitlement restoration. Preserve historic Cashfree order amounts, fall back to other valid tiers after revocation and keep quotas off during beta. Ordinary donations do not automatically unlock access. Enhanced XL summarization and early app/model access are planned; future advanced local features belong to XXL as delivered.
- Improve offline search across titles, descriptions, notes, source text and verified extraction details. Rank exact/title matches first, expand a small set of related English words, handle plural queries and ignore conversational filler. Index save categories for searches such as “cold coffee recipes”; repair FTS4 prefix compatibility and reset the result position when queries change. No model, new dependency or network request is needed.
- Add optional Firebase Google identity and an Account, tiers & Drive backup screen. Continue without an account; missing configuration keeps the local library usable.
- Implement Free/XL/XXL policy (100/500/unlimited saves, 5/30/unlimited collections), with custom model imports reserved for XXL once limits are activated. Preserve existing/restored over-limit data and already installed models. Keep paid limits off in the preview.
- Add streamed, checksum-verified Drive app-data backups, daily foreground Wi-Fi scheduling with failure backoff, manual backup/merge restore and three verified snapshots per device.
- Switch one-time upgrades to Cashfree hosted checkout for Indian payments: XL ₹449 (500 saves/30 collections), XXL ₹649 (unlimited product quotas and compatible custom-model imports). Bind server-priced orders directly to Google sign-in, remove manual Shop codes and purchase webhooks, retain Buy Me a Coffee donations separately. Isolate sandbox from real entitlements; verify signed raw-body payment/refund events, retry orders idempotently and recover missed events on restoration. Checkout and paid limits remain disabled pending activation and live acceptance. Cashfree international payments are unavailable; international buyers use the owner-verified manual upgrade path.
- Add separately consented, tightly bounded contribution intake, history/deletion, raw retention and private checksummed laptop export tools with optional weekly scheduling. Prepare reviewed dataset and manual LoRA/QLoRA tooling; do not automatically train or publish models.
- Add production-signing configuration support without replacing the existing development signing key. Stable certificate migration remains a release gate.

## 0.8.3 — 2026-11-07 (development preview)

- Add persisted weekly foreground GitHub checks and a newer-version popup on quiet library screens. Snooze reminders for a week, back off offline failures for a day, and let users disable weekly checks or select the preview channel in Settings. Keep manual checks; never automatically download or install APKs. Publish as build 16, retaining compatible signing for in-place updates from local build 15.
- Add opt-in Android local notifications for extraction completion, partial results and errors, with Android 13+ permission handling, a test action and notification settings. Keep saved titles/text/URLs out of alerts. Tapping an alert opens its save; cancelled/background-stopped jobs remain silent. No server, push SDK or background extraction service is introduced.
- Show extraction part coverage, elapsed time and an explicitly approximate remaining-time estimate in the library and active save. Count parts only after evidence validation, use comparable successful session timings when available, and keep loading/uncalibrated work indeterminate.
- Expose **Diagnostics & logs** near the top of Settings. Explain opt-in, non-retroactive capture and native crash/OOM limitations; preserve local viewing, export, clearing and the old version-tap shortcut.

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
