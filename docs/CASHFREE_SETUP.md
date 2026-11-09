# Cashfree setup — domestic INR beta

Linqo remains in active development. No paid limits until a real payment, settlement, same-Google restoration and refund pass acceptance. XL is **₹449 once / 250 saves / 25 collections**. XXL is **₹649 once / no product quotas / compatible custom-model imports**. Free remains 50 saves/5 collections when limits are eventually activated. Built-in English extraction and local/Drive backups stay free. International payments are deferred. Buy Me a Coffee is donations only.

## Account and provider activation

The owner submitted/completed Cashfree KYC, but the Payment Gateway dashboard displayed **Product is not activated**. General account access does not establish live PG activation. Ask Cashfree support to activate domestic Payment Gateway for one-time digital software upgrades distributed as a GitHub APK, using hosted checkout. No international approval is required for this domestic-INR milestone; payment-method eligibility remains Cashfree's decision.

In the PG dashboard use **Switch to Test → Developers** for sandbox API credentials. Store them directly as encrypted Worker secrets `CASHFREE_TEST_APP_ID` and `CASHFREE_TEST_SECRET_KEY`. Do not paste values in chat, Dart, Git, CLI arguments or screenshots. Live credentials later use `CASHFREE_APP_ID` and `CASHFREE_SECRET_KEY`, separately. The PG secret key verifies webhooks; there is no invented separate webhook key. Use the same selected API/webhook version **2025-01-01**. Confirm support for that pinned version before live activation.

Whitelist the actual checkout origin `https://linqo-cloud.aryandurgude123.workers.dev` with Cashfree, not just the Firebase information site. If their domain audit rejects a workers.dev subdomain, resolve domain approval with Cashfree before enabling checkout; do not spoof an approved origin. Publish accurate seller identity, final tax/fee treatment and refund terms. The current policies remain development notices and must be reviewed before sales.

## Deploy with checkout off

1. Authenticate Wrangler locally. Do not print OAuth tokens or put them in repository files.
2. Query aggregate counts of `bmc_purchases` and `bmc_refunds`. Export a private recovery copy before migration. The append-only `0003_cashfree.sql` deliberately refuses a non-empty Shop financial ledger. Never bypass that guard; any actual prior paid licences need a deliberate migration.
3. Apply purchases D1 migrations, then deploy checked-in config: `PAYMENTS_ENABLED=false`, `CASHFREE_MODE=sandbox`, `CASHFREE_LIVE_APPROVED=false`. Preserve existing identity HMAC and entitlement signing keys. No app-library migration is required.
4. Verify `/health` identifies Cashfree, sandbox=true, payments_enabled=false, contributions_enabled=false. Retired `/shop/start` and `/webhooks/buymeacoffee` return 404. Remove the obsolete BMC signing secret only after successful replacement and preserve private recovery backups. Donations need no unlock webhook.
5. Configure signed Cashfree webhooks to `/webhooks/cashfree/sandbox` in sandbox and `/webhooks/cashfree/production` in production. Subscribe to successful payments, refund status and auto-refund status; failed/pending events never unlock. Verify a provider-originated delivery, not just synthetic tests.

## Sandbox acceptance

After test credentials and approved origin are available, enable only `PAYMENTS_ENABLED=true`, leaving `CASHFREE_MODE=sandbox` and `CASHFREE_LIVE_APPROVED=false`. A separate client acceptance config sets `LINQO_CHECKOUT_ENABLED=true` and keeps `LINQO_PAID_LIMITS_ENABLED=false`. Normal builds keep both false.

Sign into Google, choose XL/XXL, enter a phone number with country code after the disclosure, then continue to the browser. The backend creates a server-priced INR order already bound to the verified Google identity. No BMC product, manual purchase code, payment-email matching or client-supplied price is used. Phone numbers are forwarded to Cashfree and not stored in the library or ledger. Use Cashfree's published sandbox payment details only. No real charge or paid production entitlement is produced by sandbox events.

Verify both prices, failed/cancelled/retried payments, duplicate webhooks, return-to-app restoration, account switching, backend outages, completed refunds before/after captures and genuine provider signature handling. Sandbox must always restore Free. Use a separate QA app identity for automated phone integration tests; never Flutter drive the user's main app. Normal updates must use in-place install, not uninstall.

## Live gate

Only after domestic PG activation, settlement account and domain approval, test acceptance, actual merchant/refund disclosures and production signing review, configure production credentials and set `CASHFREE_MODE=production`, `CASHFREE_LIVE_APPROVED=true`, `PAYMENTS_ENABLED=true` for an authorized real acceptance window. Paid app limits stay false. Confirm a real payment, settlement, restoration on another device and completed refund. Close the window with PAYMENTS_ENABLED=false when testing stops. Enabling checkout does not enable quotas.

Orders are retry-idempotent, capped at ten new starts/account/day and expire after one hour. Restore uses signed webhooks plus owner-only, bounded API reconciliation of one due order per call (up to three provider requests, rate-spaced per order). Repeated restoration eventually checks other orders; it is not continuous polling. Outages preserve the known ledger. Offline entitlements have no routine expiry, so a revocation takes effect only after reconnecting. Successful partial refunds revoke once cumulative refunds reach the full price for that payment. Chargeback handling still needs qualification before stable release; this beta does not claim unattended dispute management.

Official references: [hosted checkout](https://www.cashfree.com/docs/payments/online/web/redirect), [create order](https://www.cashfree.com/docs/api-reference/payments/latest/orders/create-order), [raw-body signatures](https://www.cashfree.com/docs/payments/online/webhooks/signature-verification), [idempotency](https://www.cashfree.com/docs/payments/online/webhooks/webhook-indempotency), [payment events](https://www.cashfree.com/docs/api-reference/payments/latest/payments/webhooks), [refund events](https://www.cashfree.com/docs/api-reference/payments/latest/refunds/webhooks), [refund reconciliation](https://www.cashfree.com/docs/api-reference/payments/latest/refunds/get-all-refunds-for-an-order).
