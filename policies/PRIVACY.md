# Linqo privacy — development preview

Linqo is in active development. Optional cloud features are configuration-gated; current preview builds with no Firebase configuration keep the library local. This document describes the implemented feature boundaries, not proof that checkout is live.

## Your library

Saves, notes, file copies and English AI inference live on your device. Public title/caption/preview requests contact the original providers; optional model downloads contact the model host. GitHub update checks contact GitHub. No hosted inference, general analytics or automatic crash upload is introduced. Local diagnostics remain separately opt-in.

## Optional accounts and purchases

Google sign-in uses Firebase Authentication. The purchase backend receives an authenticated account identifier, verified provider identity and purchase/order records; Razorpay handles payment information. Card/bank details are not stored by Linqo. Minimal keyed identity links and payment records are retained for purchase restoration, refunds and required records. Buy Me a Coffee donations are separate and confer no paid tier.

Signing out removes access to the account tier on this device while preserving local saves. Account deletion removes Firebase identity and retained contributions/consent; it does not erase local files, personal Drive backups or necessary purchase records. The same Google identity can restore a valid purchase after account recreation.

## Optional Drive backup

Drive access is requested separately using the app-data scope. Sign-in alone does not upload a library. Enabled backups contain saved content, notes, extracted details, collections and copied files in the user's Google storage. Models, credentials and purchase entitlements are excluded. Automatic backups run opportunistically while the app is open, idle and on Wi-Fi; this is not continuous sync or a guaranteed background schedule. Existing snapshots remain when backup is disabled or the user signs out. Users can manage/delete app data through Google Drive settings. Provider storage protection is used; Linqo does not claim end-to-end encryption. Portable local ZIPs are unencrypted.

## Optional extraction contributions

Default off and separate from account/backup/diagnostics consent. If enabled, Linqo can upload small eligible English public-source excerpts, category, model/schema version, extraction result and optional correction. Personal notes, files and manual/private inputs are excluded. Obvious links, emails, handles and long numbers are removed; sensitive-looking inputs are rejected. Filtering cannot guarantee anonymity or identify every private fact. Do not enable this option if you do not want any source excerpts uploaded.

Limits: two/account/day, 100 samples globally/day, 8 KiB each, bounded contribution storage. Raw server source/output expires after 30 days. Minimal contribution IDs/owner metadata remains to let you request deletion of exported examples. Maintainer copies are pulled privately, unreviewed copies expire after 90 days, and reviewed examples may be retained for permitted model development. A sample is not automatically considered correct or authorized for training merely because it is public.

View or delete contributions in Account & backup, including deletion requests for expired server examples. Deletions apply to maintainer copies at the next successful pull and invalidate prepared datasets. Opt-out immediately stops future queuing and persists locally even when the server is unavailable. Already completed/in-flight transfers may require a deletion request. Removal of an example cannot guarantee removal of its influence from an already trained model. No automatic phone training or model publication occurs.

## Controls and contact

Continue without an account, keep local ZIP backups, disable Drive, opt out of contributions, inspect/delete samples, or delete your account in Settings. Avoid posting private receipts or source text to public GitHub issues. Contact the seller using the private contact supplied on the live Razorpay checkout; live activation requires that actual seller/support information be configured first.

Google/Firebase, Cloudflare, Razorpay, GitHub and source providers apply their own policies. Secrets and content payloads are excluded from operational logs by design. Infrastructure quotas/outages can interrupt optional services without deleting the local library.
