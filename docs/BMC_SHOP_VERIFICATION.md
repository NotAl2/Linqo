# Shop migration verification — v0.9.0+18

Active development. Implementation and controlled fixtures pass; real Shop payment/restoration/refund acceptance is still pending. Checkout, paid limits and contributions remain disabled.

## Implemented

- XL US$5 once: 250 saves / 25 collections. XXL US$7 once: unlimited product quotas and compatible custom-model imports. Free remains 50 saves / 5 collections when limits activate; built-in English AI and local/Drive backup stay free.
- Owner's saved draft products: XL 596224, XXL 596225. The owner reports payouts already verified. Draft creation worked in Chrome after failing in Helium. Required code-question behavior still needs confirmation.
- Google-authenticated starts issue 128-bit random single-use purchase codes bound to a canonical Google identity, exact product, amount/currency and validity window. Plaintext codes are not stored. A buyer's checkout email cannot claim an unlock.
- Native, large-text-safe copy-code dialog opens the exact creator Shop URL externally. No payment SDK, embedded browser, new Flutter dependency, email provider or background polling service added.
- Signed live Shop webhooks validate product ID, price, currency, completed status and pre-issued code. Test/donation/membership events cannot grant tiers. SQL uniqueness/conditional updates prevent code reuse; late signed updates can supply an initially missing answer. Refund tombstones handle refund-before-purchase and delayed/repeated captures.
- Same-Google restoration works through stable provider-subject mapping even after a Firebase identity is recreated. Entitlements remain signed for the current Firebase UID; offline caching and sign-out behavior are retained.
- Removed the former hosted checkout page, provider API calls and public checkout/verification routes. Unknown/retired paths return 404 before identity/database work. No active old-provider references remain in app code, backend source, pubspec, README, policies or current changelog.

## Deployment evidence

- Production was checked before replacement: zero legacy orders, payments and events. A recovery SQL export is stored under protected `.private/linqo-cloud/`; never publish it.
- Append-only migration `0002_shop.sql` applied remotely. A CHECK guard refuses to remove any non-empty financial ledger. The old orders/payments/events tables are gone; shop_sessions/bmc_purchases/bmc_refunds exist. One existing account link is preserved; Shop purchases count is zero.
- Worker version `cbf12594-26c1-4245-8d7e-bdf64bdcd7e6` deployed at `https://linqo-cloud.aryandurgude123.workers.dev`. Public health returned payments_enabled=false and contributions_enabled=false. Unsigned Shop POST returned 401 invalid_signature; retired checkout returned 404 not_found. Python's default HTTP client was rejected by Cloudflare; normal Windows HTTP requests verified these responses.
- Updated public privacy/purchase/terms/support pages deployed to Firebase Hosting. Purchase policy returned HTTP 200 with the new limits, US$7 XXL price and code-linking instructions. Checkout-not-live and active-development notices remain.
- The owner added BMC_WEBHOOK_SECRET as a plain-text variable in a dashboard version. Follow-up converted it to an encrypted Worker secret using protected files and child-process stdin; no secret was printed or put in command arguments. A protected recovery copy is retained for project backups; duplicate diagnostic copies were redacted. Existing signing/account keys and disabled sales flags were preserved.
- A locally signed non-live Shop event returned HTTP 200 `{"ok":true,"ignored":"test_event"}`. Encrypted-secret metadata confirmed the name; live purchases and purchase sessions remained zero, and health confirmed checkout/contributions disabled. The APK was rescanned against the newly configured private secret as well. This validates deployment wiring, not provider-originated delivery.
- On 2026-11-08 the owner reported the actual Buy Me a Coffee dashboard delivery returned HTTP 200 with `{"ok":true,"ignored":"test_event"}`. This confirms provider-originated test delivery and signature acceptance without granting access. Code-question capture and an authorized real payment/restoration/refund check remain pending. Dashboard tests acknowledge but never unlock. No funds were charged or refunded during this implementation.

## Automated checks and artifact

- 182 Flutter tests passed (`.tools/bmc-flutter-tests.log`), including 14 focused Shop/tier/account-switch/account-UI tests. XL boundary behavior, restored over-limit data, signed/offline entitlements, code copying and light/dark large-text layout are covered.
- 21 Node backend/export/dataset tests passed (`.tools/bmc-backend-tests.log`): signed Shop fixtures, product/amount validation, missing/reused/wrong-product code, expiry and delayed delivery, rate limiting, refund ordering/fallback, live-vs-test separation, stable account restoration and guarded legacy migration. These use synthetic provider events, not real money.
- Changed services, account screen, purchase dialog and Shop test passed targeted Dart analysis. The release build succeeded. Existing SDK/plugin deprecation warnings remain build-tool maintenance work; no dependency upgrade was introduced here.
- ARM64 APK: `.tools/Linqo-v0.9.0-bmc-preview-android-arm64.apk`, **74,815,399 bytes**, SHA-256 `5d27e231b33f454a026bb212d62c7047548a98e02ee7e6c463a4e8bdfd4e4e47`. Manifest confirms versionName 0.9.0, versionCode 18. Certificate SHA-256 remains `0fbd3e81d289c5cc9395eaf0a368add97a1e5b4f48d4bf62133f2a3c6c0e6b11`.
- The 336-entry APK scan found expected Firebase client configuration and no known private server credential values. Client checkout/paid limits are off. No phone was modified or test harness installed during this Shop implementation.

## Private acceptance artifact

- Prepared `.tools/Linqo-v0.9.0-bmc-acceptance-android-arm64.apk`: 74,815,399 bytes; SHA-256 `dbc458cdb1b96ead59ccec5c06c2ff5ac7c88306ea515b9c3ff97bcd8f50217c`. Client checkout is enabled only in this separate artifact; paid limits remain disabled. The normal private config was unchanged and the normal preview APK was restored to the default release output after the build.
- The acceptance APK passed the 336-entry private-credential scan and expected public Firebase configuration check. Build log: `.tools/bmc-acceptance-build.log`. Server payments remain disabled. This APK has not been installed on the owner's phone and cannot initiate checkout until the server acceptance window is explicitly enabled.
- Required purchase-code question behavior must be confirmed before a controlled real transaction. No real funds have been charged, and the dashboard acknowledgement does not establish payment, settlement, refund or cross-device restoration acceptance.

## Backups and remaining gates

Verified private checkpoints are maintained in `C:/Projects/Linqo Backups/`, retaining the newest three across app versions. A pre-switch snapshot and Shop-core checkpoint were created; final artifact/setup evidence receives another checkpoint. The backup wrapper now reuses an already-correct private ACL rather than unnecessarily attempting a privileged ACL rewrite.

Google brand/domain verification remains pending at the owner's request. Required-question validation, live purchase/refund/restoration, genuine second-device acceptance, production signing migration and broader Drive/performance gates must pass before public paid-limit/stable activation. Neither unit fixtures nor the existing development signing certificate establish those results.
