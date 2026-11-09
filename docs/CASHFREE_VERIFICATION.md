# Cashfree switch verification — v0.9.0+19

Active development. Indian one-time prices chosen by the owner: XL ₹449 and XXL ₹649. Limits remain 250 saves/25 collections for XL, unlimited product quotas/compatible custom-model imports for XXL. International payments are deferred; normal client checkout, paid limits and contributions remain off.

## Local implementation

- Replaced the BMC Shop service, native copy-code dialog and client Shop response parser. Cashfree orders are server-priced and pre-bound to the verified canonical Google account. Ordinary BMC donations remain separate. Old Shop endpoints return 404.
- A native themed phone/disclosure dialog opens external hosted checkout, with no new Flutter dependency or payment SDK. SDK v3 runs only on the short-lived browser checkout page. No background payment polling service is added.
- Separate sandbox/production keys, order prefixes and ledger environment prevent sandbox success from granting real access. Production enablement requires a separate approval flag. Cashfree raw-body timestamp/base64-HMAC signatures are verified before parsing; payment/refund IDs are immutable and idempotent.
- Orders survive create-API timeouts with the same request ID. Price/currency/provider URLs cannot be supplied by the client. A completed refund persists before a delayed successful payment, including cumulative partial refunds and fallback to another valid purchased tier.
- Restoring the same Google identity after Firebase-account recreation preserves ownership. Bounded API reconciliation can recover missed deliveries, with known entitlement state preserved during network failure.
- App library schema, saves, settings, model weights and entitlement signing format are unchanged. Guarded server migration 0003 aborts if any Shop financial history exists; no paid history is silently discarded.

## Checks

- 25 backend/export/dataset tests pass, including 11 new Cashfree tests using real SQLite migrations and synthetic provider HTTP/events. Cover forged signatures, altered prices/currency, sandbox isolation, replay, partial/full/refund-before-capture, account recreation, timeout/retry, rate caps, protected checkout page and legacy-ledger guards. Log: `.tools/cashfree-backend-tests.log`.
- 182 Flutter tests pass, including 14 focused checkout/account/quota tests. Phone validation and disclosure are checked in light/dark at 1.5× text, with keyboard insets. Log: `.tools/cashfree-flutter-tests.log`; focused log `.tools/cashfree-flutter-focused.log`.
- Targeted Dart analysis passes. No dependency upgrade introduced. Log: `.tools/cashfree-analyze.log`.

## External state and remaining checks

Cashfree credentials and provider-originated sandbox/live tests are not yet available. Account/KYC access was reported active, but the screenshot explicitly says Payment Gateway product is not activated. No real Cashfree payment was made. Domain approval, domestic PG activation, provider sandbox execution, settlement, actual second-device restoration, refunds, dispute policy and final seller disclosures remain release gates.

The initial attempt to disable the old Shop window was blocked by missing Cloudflare authorization. The subsequent verified deployment below supersedes that state: Cashfree is now deployed with checkout disabled.

Project backups are private, verified and retain the newest three beside the project. No phone has been modified by this provider-switch implementation so far.

- A fresh Cloudflare device authorization was started with account/user read and Worker/D1 write permissions, but timed out after five minutes without authorization. No remote migration or deployment was attempted without authenticated access. The previous Shop deployment must not be described as replaced/disabled yet.
- The connected Redmi was detected, but its display/app was locked when checking availability for this milestone. No APK was installed, no Flutter drive harness ran and no application data was cleared. Physical Cashfree checkout UI/latency acceptance remains pending.
- Ponytail 5.3.3 is installed/enabled in Codex with default full mode; its hook trust/new-session step remains separate. See DEV_TOOLS.md. Project backups include the setup record, not the global plugin cache.

## Built preview artifact

ARM64 APK `.tools/Linqo-v0.9.0-cashfree-preview-android-arm64.apk`: **74,815,335 bytes**, SHA-256 `428cc5f100b73a7ef4d5491ad6f6ac86fe94aad57634bd6af243f1588999ddff`. Final source includes checkout availability in authenticated entitlement responses so sign-in/restoration does not leave availability stale. The final backend tests pass after this change. The release compile verifies the corresponding client response fields.

The APK's 336-entry scan found expected public Firebase configuration and no known private server credential values. Client checkout and paid limits are false. Logs: `.tools/cashfree-release-build.log`. Existing KGP/SDK XML/plugin warnings remain toolchain maintenance work; no unrelated SDK/dependency upgrade was attempted. This is a local beta artifact, not a GitHub release or proof of production signing qualification.

## Verified deployment — 2026-11-09

- Fresh Cloudflare device authorization completed. Before migration, remote counts were purchases=0, refunds=0, Shop sessions=2 and account_links=1. A protected D1 recovery export was saved locally (`purchases-before-cashfree-20261109T071936Z.sql`, 2,261 bytes, SHA-256 `0c724c4990c62793d7b6c705b20650d752de2b1670d7e52c7456ae1dcd349c34`). No private rows or signed download URLs were printed.
- The owner confirmed Shop items were deactivated. Fresh public checks of both configured item URLs returned HTTP 404. The donation page is retained.
- Guarded migration 0003 applied, then the Cashfree Worker source deployed (source deployment ID `776963a4-777f-4f34-8e88-38075b17d3df`). Health returned HTTP 200 with provider=cashfree, sandbox=true, payments_enabled=false and contributions_enabled=false. Client paid limits remain off.
- Retired `/shop/start` and `/webhooks/buymeacoffee` return 404. Cashfree's unsigned sandbox webhook returns 401 invalid_signature; unauthenticated checkout start returns 401 sign_in_required. A forged success query on the return page does not confirm payment.
- Removed only BMC_WEBHOOK_SECRET from the deployed Worker after replacement. Existing ACCOUNT_HMAC_SECRET, CONTRIBUTOR_HMAC_SECRET and ENTITLEMENT_PRIVATE_JWK remain encrypted Worker secrets. Protected recovery copies remain in project backups. Cashfree keys have not been configured yet; no sandbox or real payment was attempted.
- Firebase Hosting pages were deployed successfully. Public purchase policy returned HTTP 200 with Cashfree, ₹449/₹649 and the checkout-not-live notice. Active development remains explicit.
- Post-migration verification confirms empty Cashfree order/payment/refund tables, the existing Google identity link preserved and no retired Shop tables. No app uninstall, phone data reset or new APK installation was performed during this deployment.
