# Linqo account and Shop backend

Active development preview. Library storage and English AI stay local. Optional Google identity uses Firebase Spark; purchase entitlements use Cloudflare Workers/D1; optional backups use the user's Drive. No hosted inference, Firebase Functions or hosted library database is added.

## Current configuration

- Worker: https://linqo-cloud.aryandurgude123.workers.dev
- Separate D1 databases: linqo-purchases and linqo-contributions.
- Firebase project linqo-app-notal2; billing unlinked. Owner-confirmed Audience In production. Non-sensitive scopes require no scope verification; brand/domain verification remains pending by owner choice.
- Shop products: XL 596224, US$5 once, 250 saves / 25 collections; XXL 596225, US$7 once, no product quotas and compatible custom-model imports.
- PAYMENTS_ENABLED=false, client checkout/paid limits off. Contribution uploads paused in both client and server. Shop products remain drafts until acceptance.
- Signing/HMAC secrets stay in ignored .private/linqo-cloud/ and Worker secrets. Preserve these keys: changing them can break account links or offline entitlements. Project backups include them and must remain private.

See [Shop setup](../docs/BMC_SHOP_SETUP.md), [production status](../docs/PRODUCTION_SETUP.md), [privacy](../policies/PRIVACY.md) and [purchase policy](../policies/PURCHASES.md).

## Purchase flow

1. Google sign-in is optional for local free use, required to buy/restore. The server verifies Google's signed Firebase token, project, provider and verified-email claim. A keyed Google provider subject resolves to a stable purchase owner, even if its Firebase identity is recreated. Payment email does not assign ownership.
2. Authenticated POST /shop/start accepts a tier, not a client price. It issues a random 128-bit code bound to the account/product/fixed USD price for 30 days. Only its hash is stored; at most ten starts/account/day.
3. The native app shows the price/account, asks the buyer to copy the code, then opens the exact buymeacoffee.com/notal2/e/<configured product> URL externally. No embedded browser, checkout JavaScript SDK, email service or polling service is added. Paste the code when Shop asks for Linqo purchase code.
4. POST /webhooks/buymeacoffee verifies x-signature-sha256 over the exact raw body before parsing. Only live completed Shop events with matching product/price/currency and valid pre-issued code link an unlock. Ordinary donation/membership events and dashboard tests never grant a tier.
5. A code can link only one order. Product ownership cannot be reassigned by a later event. Signed updates can supply a missing answer before an order is linked. Unmatched completed orders retain minimal metadata for private support; there is no public email/receipt-ID claim shortcut.
6. Signed refund events create a tombstone even if delivered before purchase. Delayed/repeated events cannot restore a refunded unlock. GET /entitlement signs the highest remaining valid tier using the current Firebase UID. Offline unlocks have no routine expiry; online checks apply refunds. Sign-out removes the account tier locally without deleting saves.

Supported launch checkout: one product/quantity one, fixed USD prices, no discounts or mixed carts. Full XXL after XL costs US$7 separately. Device capacity and backup safety bounds still apply. Monitor delivery failures in Buy Me a Coffee; retries are finite and persistently failing webhooks may be disabled. A long outage may need creator replay/support review; failed event delivery is not treated as proof of payment.

## Deploy and build

From cloud/: npm ci, npm test, then Wrangler d1 migrations apply linqo-purchases --remote and Wrangler deploy. Migration 0002_shop.sql removes the unused former checkout ledger only when orders/payments are empty. It preserves stable identity links and fails instead of deleting financial records. Applied migrations are append-only; do not edit 0001.sql.

Set the creator-generated BMC_WEBHOOK_SECRET through Cloudflare Worker secret settings or Wrangler's interactive secret put command. Never put it in Dart, Git, chat or command arguments. Product IDs are public configuration in wrangler.jsonc. A Buy Me a Coffee API token is not needed.

Use scripts/Configure-Firebase.ps1 with the downloaded SDK file to validate the project/package and generate private Flutter configuration. Build with scripts/Build-CloudPreview.ps1 using that private configuration. Its allowlist excludes provider secrets and keeps paid limits off. Client checkout is a separate flag for an authorized acceptance build. Run tools/check_apk_secrets.py against the result. Missing cloud configuration preserves local guest use.

Do not enable public paid limits before verified Shop payment, same-Google restoration, refund, retry and account-switch acceptance. No script upgrades Firebase/Cloudflare to a paid infrastructure plan. Provider fees and tax obligations remain separate.

## Other API boundaries

- GET /health: public readiness booleans only. Checkout readiness requires both product IDs, webhook secret and server enable flag.
- The former /checkout and /orders flows are removed. Only Shop starts, signed Shop webhooks and authenticated entitlements handle purchases.
- PUT /consent, POST/GET /samples, DELETE /samples/:id and DELETE /account are authenticated contribution controls. Intake stays off pending consent/provenance review. Account deletion removes contribution data/consent; minimal purchase bindings/records remain for restoration/refunds. Source text, buyer emails and raw webhook payloads are not operational logs.
- Separate contribution database: 2/account/day, 100 globally/day, 8 KiB/sample, 100 MB payload budget, 30-day raw retention. Private exports apply deletion tombstones; nothing trains automatically. See [training workflow](../tools/training/README.md).

The private weekly Windows export task remains independent of purchases. It uses protected local credentials, atomic checksummed batches and manual model curation/training. No model improvement or production cloud qualification is claimed from mock tests.
