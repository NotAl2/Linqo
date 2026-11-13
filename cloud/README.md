# Linqo account and purchase backend

**Build 27 paid beta:** checkout-capable Polar beta with Free 100/5, XL 500/30 at ₹449 once, and XXL at ₹649 once. The owner explicitly authorized live Polar payments and beta publication. Production configuration enables Polar checkout only; private acceptance/sandbox offers and training uploads remain off. Source uses server-verified account-bound prices/orders/refunds and preserves historical Cashfree/manual/gift restoration. Contributions and private acceptance offers remain disabled. Donations remain separate. See [review evidence](../docs/PREBUILD_REVIEW.md).


Active development. Unconfigured app builds keep checkout off. The authorized production template enables Polar checkout; contributions and new Cashfree checkout remain off. See [setup](../docs/CASHFREE_SETUP.md), [evidence](../docs/CASHFREE_VERIFICATION.md), [privacy](../policies/PRIVACY.md), [purchases](../policies/PURCHASES.md) and [production status](../docs/PRODUCTION_SETUP.md). Cashfree domestic PG activation and real payment acceptance are not established by unit tests. Buy Me a Coffee supports ordinary donations plus separately verified manual international upgrades (US$4.99 XL / US$6.99 XXL); no donation webhook or public grant endpoint is added. See [manual unlock operations](../docs/MANUAL_UNLOCKS.md).

## Architecture

Firebase Spark Google identity is optional for the local library and required for purchases/restoration. Cloudflare Workers/D1 keep minimal payment/account records, never the user's library. Drive backups stay in users' own Google storage. Purchases and contributions use separate D1 databases. No infrastructure plan is upgraded automatically.

- XL ₹449 once: 500 saves/30 collections. XXL ₹649 once: unlimited product quotas and compatible custom-model imports. Free 100/5 in official builds; built-in English AI and backups free. XXL after XL is a separate ₹649 purchase without proration.
- POST /checkout/start authenticates Google, validates a phone number and UUID request ID, and creates a fixed INR order bound to the stable Google provider identity. A retry reuses the order/idempotency key. Contact fields and raw provider payloads are not persisted. No client price, receipt ID, checkout email or account ID can assign ownership.
- GET /checkout/<opaque-key> renders a one-hour, no-store/no-referrer browser page using Cashfree JS SDK v3. No payment SDK or WebView is added to Flutter. The return page never confirms payment.
- POST /webhooks/cashfree/sandbox and /production verify base64 HMAC-SHA256 over timestamp+exact raw body using the respective PG secret. Only matching known INR orders and SUCCESS payment events count. Payment/refund IDs are idempotent; full refunds (including accumulated partial refunds) dominate delayed success events. Another valid purchase provides fallback.
- GET /entitlement authenticates the same Google identity, attempts bounded owner-only reconciliation, then signs the highest valid production tier using the existing Ed25519 key/issuer/audience. Sandbox never grants paid tiers. Account recreation remains restorable; signing out removes account access locally without deleting saves. Offline caches have no routine expiry; reconnect to apply revocations.
- GET /health returns provider, sandbox and readiness booleans, no secrets. Production requires PAYMENTS_ENABLED=true, CASHFREE_MODE=production, CASHFREE_LIVE_APPROVED=true, valid credentials and HTTPS CHECKOUT_ORIGIN. Default sandbox keys are distinct from production keys. Old Shop routes return 404.

## Migration and deployment

From cloud/: npm ci, npm test. Authenticate Wrangler; privately export and inspect aggregate legacy financial counts before applying D1 migrations. Append-only 0003_cashfree.sql removes only an empty Shop financial ledger; it aborts rather than discarding purchases/refunds. Preserve account links and entitlement signing keys. Never bypass a failed financial-history guard. Older migrations remain as applied history.

Use encrypted Worker secrets CASHFREE_TEST_APP_ID/CASHFREE_TEST_SECRET_KEY for sandbox and CASHFREE_APP_ID/CASHFREE_SECRET_KEY for production. Never put them in Dart, Git, chat, command arguments or the public information site. Keep checkout/paid limits off while credentials, domain and activation are pending. Whitelist the actual checkout origin with Cashfree. Once deployment succeeds, remove the retired BMC_WEBHOOK_SECRET from the Worker (keep protected recovery backups). BMC donations need no unlock endpoint.

Build the normal app through scripts/Build-CloudPreview.ps1 with the private public-client-only config. Its allowlist excludes provider secrets. A separately configured acceptance build can enable client checkout but never paid limits. Scan the APK using tools/check_apk_secrets.py. Missing cloud configuration preserves guest local use. Do not Flutter drive the owner's main application identity.

Successful sandbox, real domestic payment, settlement, refund, restoration, account-switch, outage and production-signing checks are prerequisites for public quotas. International/USD payments and unattended dispute management are deferred.

## Contributions

Contribution intake remains disabled in client and server. PUT /consent, POST/GET /samples, DELETE /samples/:id and DELETE /account retain the bounded existing behavior. Account deletion clears consent/contributions but keeps necessary purchase records and immutable identity bindings for restoration/refunds. Samples exclude identifiers and private content by policy; Google/Drive provenance review is still required before enabling uploads. No automatic training is scheduled. Existing private export/curation tooling and quotas are unchanged.

Private test offers/gifts: apply `0006_private_offers_gifts.sql` before deploying the matching Worker. Commands and constraints are documented in [account-access maintainer tool](tools/account-access.mjs). No payment-enable flag changes are required to manage eligibility.

Polar migration and private acceptance: see [Polar setup](../docs/POLAR_SETUP.md). Public checkout remains disabled; historical Cashfree purchases are preserved.

New checkout selects `PAYMENTS_PROVIDER=polar`. `/health` and authenticated `/entitlement` report the active provider; public availability requires payment enablement, explicit Polar approval, live token, live webhook secret and HTTPS checkout origin. The official beta client validates the corresponding provider host and quoted total. Legacy Cashfree records and refund endpoints remain to preserve historical purchases; the public Polar path cannot apply the old INR 1 offer.
