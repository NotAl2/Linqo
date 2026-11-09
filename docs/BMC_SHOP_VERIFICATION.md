> Historical Shop integration, retired on 2026-11-09. Do not follow these activation steps. Current purchases use [Cashfree](CASHFREE_SETUP.md); Buy Me a Coffee is donations only.

# Shop migration verification — v0.9.0+18

Active development. Implementation and controlled fixtures pass; real Shop payment/restoration/refund acceptance is still pending. Normal-build checkout, paid limits and contributions remain disabled. The controlled server checkout window is noted below.

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
- The acceptance APK passed the 336-entry private-credential scan and expected public Firebase configuration check. Build log: `.tools/bmc-acceptance-build.log`. At build preparation, server payments were disabled and the APK was not installed. The subsequent in-place Redmi installation and controlled server-window state are recorded below.
- Required purchase-code question behavior must be confirmed before a controlled real transaction. No real funds have been charged, and the dashboard acknowledgement does not establish payment, settlement, refund or cross-device restoration acceptance.

## Backups and remaining gates

Verified private checkpoints are maintained in `C:/Projects/Linqo Backups/`, retaining the newest three across app versions. A pre-switch snapshot and Shop-core checkpoint were created; final artifact/setup evidence receives another checkpoint. The backup wrapper now reuses an already-correct private ACL rather than unnecessarily attempting a privileged ACL rewrite.

Google brand/domain verification remains pending at the owner's request. Required-question validation, live purchase/refund/restoration, genuine second-device acceptance, production signing migration and broader Drive/performance gates must pass before public paid-limit/stable activation. Neither unit fixtures nor the existing development signing certificate establish those results.

## Redmi checkout acceptance started — 2026-11-08

- Owner screenshot confirms Ask a question enabled with “Linqo purchase code” and quantity selection off. No Required toggle is visible in that screenshot; blank-answer behavior remains a checkout acceptance item. Discounts/pay-what-you-want need confirmation from the other product settings.
- Before updating the physical Redmi, observed four saves, zero collections, Google signed in, light theme, Drive enabled and installed Qwen3-0.6B-Q4_K_M.gguf (397 MB). A fresh manual Drive backup completed at 18:52 IST. This library backup excludes settings and model weights.
- Saved a protected copy of the installed APK and verified its signing SHA-256 equals the acceptance APK. Installed only with `adb install -r`; no uninstall, app-data clearing or Flutter integration harness. Android retained userId 10186 and firstInstallTime 2026-11-08 00:47:25 while versionCode advanced 17 → 18. The four saves, same Google session, light theme and installed model were observed after update.
- Opened a controlled server checkout window using a deployment override `PAYMENTS_ENABLED:true`; the checked-in default remains false. Health confirmed payments_enabled=true, contributions_enabled=false. The normal client configuration and paid-limit flags remain disabled. Shop items are still drafts according to the owner; this does not establish general sales readiness. Deploying the ordinary checked-in configuration closes the server window.
- Google-authenticated Choose XL produced the native US$5 / 250-save / 25-collection dialog and a valid-format purchase code on the phone. Copy code and Open Shop were exercised, handing off to the external browser. No payment has been submitted. Real checkout question, captured-payment linking, settlement, restoration and refund acceptance remain pending.

- The external browser displayed Buy Me a Coffee 404 for the unpublished XL item. Requested the owner publish only XL for the controlled form check; XXL remains a draft. No card/payment details were entered or submitted. Blank-answer enforcement and real financial acceptance are still unverified. The owner must reload the product after publishing and stop before payment.

## Shop verification unblocked; configuration gate — 2026-11-08

- The owner confirmed the copied public XL link exactly matches the generated URL. Both the direct and www-redirected link still returned 404 during the initial check, while the creator profile returned 200; no application URL change was justified.
- The owner subsequently completed account verification and reported the item works. The Redmi browser now visibly loads Linqo XL with “250 saves, 25 collections,” confirming the public item is accessible. XXL publication has not been confirmed and should remain a draft.
- The page displays INR ₹470.45 and an “Enter a fair price” field with a plus suffix. This is not the required fixed-USD acceptance configuration. Requested pay-what-you-want off and the base XL price USD $5. Creator Localized Pricing must also be off for the initial USD-only webhook validator. USD payout settlement alone does not demonstrate USD event currency.
- No Add to cart or payment submission was performed in this check. Required code-answer behavior, live payment linkage, refund and restoration remain unverified. Existing phone data and paid-limit flags were not changed.

## Fixed-price public item check — 2026-11-09

- After the owner corrected the product's publication state, a fresh request to the configured XL URL returned HTTP 200. Reloading Chrome on the Redmi showed the same live item and no “Enter a fair price” field.
- The owner reports pay-what-you-want and Localized Pricing are off. Chrome still displays INR (₹469.26); fixed USD checkout is not yet verified. Requested the owner choose USD in the page footer and confirm $5 before proceeding.
- Automatic approval review rejected the assistant's footer currency-selector tap as potentially entering a payment flow. The action was not bypassed. The owner was asked to manually select USD, add the item to the cart and inspect the question, stopping before payment and without entering card data.
- Purchase-code requiredness, real payment and restoration remain pending. No payment submission or app-data reset occurred. The controlled server checkout window remains enabled; paid limits and contributions stay disabled.

## Recurring provider verification blocker — 2026-11-09

- The owner reports the product returned to 404 and the identity-verification banner reappeared after completing KYC. This prevents further real checkout acceptance; no conclusion about approval/rejection is possible from the banner alone. Requested exact verification status and provider support review if it persists.
- Attempted to restore the checked-in PAYMENTS_ENABLED=false deployment. Wrangler failed before deployment because local Cloudflare authentication was unavailable in the non-interactive session. No temporary account was created and no credentials were requested in chat. A subsequent health check still returned payments_enabled=true and contributions_enabled=false. Do not claim server checkout was disabled.
- Owner was given dashboard steps to set PAYMENTS_ENABLED=false and deploy until verification is resolved. Paid limits stay off, no payment was submitted, and the phone's app data/model/settings were not modified in this check.
