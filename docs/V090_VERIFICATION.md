# v0.9.0 account/backup beta verification

Linqo remains in active development. This is an unreleased development preview, not v1.0 or a qualified live purchase release.

## Implemented and checked

- Free/XL/XXL policy: 50/150/unlimited current saves, 5/30/unlimited collections, compatible custom-model import reserved for XXL when limits activate. SQL transaction checks preserve replayed share receipts, edits/deletion and existing/restored over-limit content. Preview limits remain off.
- Optional Google/Firebase identity adapter, narrow Drive authorization, signed account-bound offline entitlements and account-switch backup consent guard. Missing cloud configuration preserves local library use.
- Drive streaming, bounded download, remote checksum validation before pruning, three snapshots per installation, explicit merge restore, foreground daily Wi-Fi attempts and retry backoff. HTTP mocks cover corruption, cancellation and safe pruning; manual upload/merge restore and cached access passed on the Redmi. Broader Drive failure/multi-device acceptance remains pending.
- Backend server-owned Razorpay prices, captured-payment ledger, webhook signatures, idempotence/refunds and stable keyed Google purchase identity. A recreated Firebase account and an older unexpired token resolve to the same canonical purchase account. The app token still names the current Firebase user.
- Separate contribution consent, bounded intake, registry/history/deletion after raw expiry, private incremental checksummed exports, and withdrawal application before dataset preparation.
- Dataset preparation uses the actual app evidence parser and exact numbered-source/system prompt. Invalid source references and unreviewed/unpermitted examples are rejected. GPU training is manual and has not run.

## Evidence

- 169 Flutter tests passed (`.tools/v090-tests.log`), including tier, entitlement, Drive failure, account-switch, offline opt-out, large-text theme and live-controller backup isolation checks. The focused backup/Drive suite also passed all 12 tests.
- 17 Node backend/export/dataset tests passed: signed mock Firebase identity, mocked Razorpay capture/refund, account recreation, contribution rules, interrupted exports and app-schema validation. These are provider mocks, not real money/account acceptance.
- Five Python training-input validation tests passed without importing GPU training libraries, downloading a model or starting training. Real training requires a successful deletion pull within five minutes; the manual wrapper refreshes exports and rebuilds reviewed data first.
- Android release APK built with Firebase/Google dependencies, existing development signing and optional model excluded. ARM64 preview is 74,815,335 bytes (74.8 MB decimal), SHA-256 `de6da26dc8b79412f7411c3efae7744f0d690116b0bb7052b3f9696493e646c3`. Its signing certificate matches the published v0.8.3 APK. Production signing migration remains unqualified.
- Static analysis passed with no issues (`.tools/v090-analyze.log`).
- Native Android emulator screenshots inspected for the account/tier and backup sections in light/dark themes. An initial emulator System UI hang occurred under laptop memory pressure; the emulator recovered after freeing idle Gradle resources. This is not a Redmi performance benchmark. Large text also passed widget checks.
- The Redmi was updated in place from v0.8.3 build 15 to the Firebase-connected v0.9.0 build 17. Android app-data identity stayed unchanged, the library retained four saves/zero collections and Settings still reported the optional model installed. Existing saves/settings/model were preserved.

## Provisioned external services

Worker `https://linqo-cloud.aryandurgude123.workers.dev` and separate `linqo-purchases` / `linqo-contributions` databases exist. Signing/HMAC secrets are stored privately and in Worker secrets. Public health confirmed payments/contributions disabled. No Razorpay secrets or live collection have been enabled.

An authenticated empty contribution export succeeded. Weekly Windows task `Linqo private contribution export` is registered for Sunday 10:00 India Standard Time plus an overdue-only login check. Its test run returned code 0; no training is scheduled. Private keys and datasets are restricted to the current Windows user and SYSTEM, and ignored by Git.

The first Google account reached its project quota. After the owner chose another account, dedicated Firebase project `linqo-app-notal2` (project number `22172552517`) was created without linking billing. Android app `1:22172552517:android:f30371f13e57c8c931822c` and the current development certificate's SHA-1/SHA-256 were registered. Google sign-in was enabled by the owner in the console; the official API confirmed it enabled. The supplied fresh SDK file contains Android/Web clients, matches the app package/certificate, and its Web client matches the provider. Drive/basic-auth APIs are enabled. No unrelated existing project was reused.

The earlier Firebase-connected ARM64 preview installed on the Redmi was 74,815,335 bytes, SHA-256 `a15552b3042930eea5762dde90b784f9fd361a3b143c1d2ad457baf029229285`. APK inspection scanned 336 entries, found all expected Firebase client configuration fields and no known private server credential values. Android accepted the in-place update with the existing signing identity. Its Cloudflare deployment binds the new Firebase project; payments/contributions remain off. A mismatched project file was rejected without overwriting the working private configuration.

Real Google sign-in passed on the Redmi with a separately selected end-user account. The app showed its signed-in identity, Free tier and all four saves without a cloud error; a read-only aggregate query confirmed one backend account link and zero payments. Drive backup remained disabled after login, and enabling it required a separate consent naming the destination account plus Google permission.

The initial real upload exposed an isolate-capture bug: backup workers captured the store/controller and an unsendable timer. A regression reproduced the failure before the fix; static data-only worker entry points now protect both export and import. After rebuilding and updating in place, Drive upload succeeded (last success 2026-11-07 21:43:31 IST). The snapshot appeared in Drive's restore picker, explicit merge restore completed without a cloud error, and the library retained exactly four saves without duplicates. A process restart retained the account, enabled Drive setting, last-success timestamp and snapshot access; another merge left the count unchanged. App-data inode remained 34117, model remained installed and the original USB sleep setting was restored to 0. This tests a same-device four-save library, not multi-device or large-attachment recovery.

## Required before beta cloud qualification / stable activation

### Additional production-preparation pass

Public homepage/privacy/terms/support/purchase/digital-delivery pages are deployed through Firebase Hosting, without billing or payment activation. Desktop and true 390-pixel mobile rendering were inspected; the deployed privacy page returned HTTP 200, had no horizontal overflow and contains the Google Limited Use disclosure. The public pages remain explicit that Linqo is in active development and checkout is unavailable. OAuth production/audience/brand status has not been confirmed by the owner.

Privacy review also found the old client could attempt an opted-in sample POST even when the server's intake flag was off. The preview now blocks enabling, queuing and sending contributions in the client itself; old stored consent cannot reactivate uploads. The Settings switch explains the pause. Before any future activation, ensure restored Google/Drive data cannot become a training candidate through retained public-source flags. A server-side rejection after receiving a request is not a no-upload guarantee.

Drive hardening adds specific full-storage/permission/rate-limit/provider errors, archive upload bounds, cancellation before pruning and during restore, remote-size verification and deletion of incomplete/invalid downloads. All 177 Flutter tests passed after the client upload gate (`.tools/v090-production-tests.log`); the 12 Drive tests also passed independently, and all 17 backend tests passed again. Full analysis found one missing-braces style warning in the new gate; after correction the service, account UI and config each passed targeted analysis (`.tools/v090-production-final-analyze.log` for the service). An isolated real-Drive acceptance harness is compiled; it tests synthetic attachment recovery, collections/notes/favourites, duplicate merge, four-upload/three-snapshot retention and invalid remote archives, cleaning up only its own QA markers. It has not yet run on the locked Redmi. No new live Drive failure/multi-device acceptance is claimed from the added mocks. See `docs/PRODUCTION_SETUP.md` for exact remaining owner/device actions.

The latest normal APK is `.tools/Linqo-v0.9.0-firebase-preview-android-arm64.apk`, 74,815,335 bytes, SHA-256 `5f358091823f1dd70a9a49d6c22c775caee935e7cf66420a60d06f6914f87b6e`. It built successfully and passed the 336-entry private-credential/client-configuration scan. It has not been installed during this pass because the device is locked and its owner has not yet confirmed readiness. The previous working normal app, saves/settings/model and USB sleep setting 0 remain unchanged.

1. Finish production OAuth publishing/consent and broader Drive acceptance. Project creation, provider/API enabling, client configuration, development fingerprints and Redmi Google sign-in/manual upload/merge/restart checks are complete.
2. Complete the owner's Razorpay merchant/KYC/bank and international/USD activation, publish actual seller/support information, and perform authorized real payment, settlement, restoration/refund acceptance.
3. Configure a private checkout-enabled acceptance build while leaving paid limits off. Enable quotas only after acceptance. Donations remain independent.
4. Test real Drive quota/revocation/interruption and multi-device restore, live contribution consent/deletion and Redmi responsiveness during cloud work/extraction.
5. Qualify production signing and a compatible migration from existing development certificates; preserve saves and settings. Support for a signing config is implemented, but a production key/rotation has not been created or tested.
6. Review model adapters on held-out grounding/coverage fixtures and quantized Redmi memory/latency before publishing any replacement. Current model and two-thread default are unchanged.

Do not publish this as stable or claim automatic backups, purchase restoration or improved model quality are production-verified based solely on unit/mocked tests.
