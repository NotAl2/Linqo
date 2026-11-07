# v0.9.0 account/backup beta verification

Linqo remains in active development. This is an unreleased development preview, not v1.0 or a qualified live purchase release.

## Implemented and checked

- Free/XL/XXL policy: 50/150/unlimited current saves, 5/30/unlimited collections, compatible custom-model import reserved for XXL when limits activate. SQL transaction checks preserve replayed share receipts, edits/deletion and existing/restored over-limit content. Preview limits remain off.
- Optional Google/Firebase identity adapter, narrow Drive authorization, signed account-bound offline entitlements and account-switch backup consent guard. Missing cloud configuration preserves local library use.
- Drive streaming, bounded download, remote checksum validation before pruning, three snapshots per installation, explicit merge restore, foreground daily Wi-Fi attempts and retry backoff. HTTP mocks cover corruption, cancellation and safe pruning; real Drive has not passed acceptance.
- Backend server-owned Razorpay prices, captured-payment ledger, webhook signatures, idempotence/refunds and stable keyed Google purchase identity. A recreated Firebase account and an older unexpired token resolve to the same canonical purchase account. The app token still names the current Firebase user.
- Separate contribution consent, bounded intake, registry/history/deletion after raw expiry, private incremental checksummed exports, and withdrawal application before dataset preparation.
- Dataset preparation uses the actual app evidence parser and exact numbered-source/system prompt. Invalid source references and unreviewed/unpermitted examples are rejected. GPU training is manual and has not run.

## Evidence

- 168 Flutter tests passed (`.tools/v090-tests.log`), including new tier, entitlement, Drive failure, account-switch, offline opt-out and large-text theme checks.
- 17 Node backend/export/dataset tests passed: signed mock Firebase identity, mocked Razorpay capture/refund, account recreation, contribution rules, interrupted exports and app-schema validation. These are provider mocks, not real money/account acceptance.
- Five Python training-input validation tests passed without importing GPU training libraries, downloading a model or starting training. Real training requires a successful deletion pull within five minutes; the manual wrapper refreshes exports and rebuilds reviewed data first.
- Android release APK built with Firebase/Google dependencies, existing development signing and optional model excluded. ARM64 preview is 74,815,335 bytes (74.8 MB decimal), SHA-256 `de6da26dc8b79412f7411c3efae7744f0d690116b0bb7052b3f9696493e646c3`. Its signing certificate matches the published v0.8.3 APK. Production signing migration remains unqualified.
- Static analysis passed with no issues (`.tools/v090-analyze.log`).
- Native Android emulator screenshots inspected for the account/tier and backup sections in light/dark themes. An initial emulator System UI hang occurred under laptop memory pressure; the emulator recovered after freeing idle Gradle resources. This is not a Redmi performance benchmark. Large text also passed widget checks.
- Redmi was detected, but its installed app/data/settings/model were not changed during this implementation.

## Provisioned external services

Worker `https://linqo-cloud.aryandurgude123.workers.dev` and separate `linqo-purchases` / `linqo-contributions` databases exist. Signing/HMAC secrets are stored privately and in Worker secrets. Public health confirmed payments/contributions disabled. No Razorpay secrets or live collection have been enabled.

An authenticated empty contribution export succeeded. Weekly Windows task `Linqo private contribution export` is registered for Sunday 10:00 India Standard Time plus an overdue-only login check. Its test run returned code 0; no training is scheduled. Private keys and datasets are restricted to the current Windows user and SYSTEM, and ignored by Git.

Firebase CLI Google authorization succeeded. Dedicated project creation failed with Google's `project quota exceeded` response. No existing unrelated project was modified; selecting an unused project, another owner account or a quota increase remains necessary.

## Required before beta cloud qualification / stable activation

1. Resolve Firebase project quota, register Android and signing fingerprints, enable Google identity/Drive, finish OAuth publishing/consent and test on real devices.
2. Complete the owner's Razorpay merchant/KYC/bank and international/USD activation, publish actual seller/support information, and perform authorized real payment, settlement, restoration/refund acceptance.
3. Configure a private checkout-enabled acceptance build while leaving paid limits off. Enable quotas only after acceptance. Donations remain independent.
4. Test real Drive quota/revocation/interruption and multi-device restore, live contribution consent/deletion and Redmi responsiveness during cloud work/extraction.
5. Qualify production signing and a compatible migration from existing development certificates; preserve saves and settings. Support for a signing config is implemented, but a production key/rotation has not been created or tested.
6. Review model adapters on held-out grounding/coverage fixtures and quantized Redmi memory/latency before publishing any replacement. Current model and two-thread default are unchanged.

Do not publish this as stable or claim automatic backups, purchase restoration or improved model quality are production-verified based solely on unit/mocked tests.
