# Changelog

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
