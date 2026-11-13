# Polar acceptance setup

Active development. Build 25 enforces local tier limits and keeps payments disabled. The owner reports Polar verification and withdrawals working as of 13 November 2026; sales remain paused by choice. Earlier build-24 acceptance notes below record the state at the time. See PREBUILD_REVIEW.md.

## Implemented

- Separate sandbox/live products, tokens and signed Raw webhook endpoints pinned to API version `2026-10`.
- Durable signed receipt inbox, replay/conflict checks and bounded retry of authoritative order reads.
- Checkout binding to the authenticated Google account using an opaque external customer identity. Prices and private discounts are selected only on the server.
- Production fulfillment validates checkout, product, organization, customer, currency, total and discount before granting a signed entitlement. Refunds retain a revocation tombstone so delayed paid events cannot restore access.
- Restore reconciles only the signed-in account's bound checkouts. Existing Cashfree, manual and gift history remains intact.
- Private acceptance requires an exact account allowlist, an API-only discount and a zero total on both server and QA client. Ordinary checkout cannot inherit that coupon.

## Verified before live acceptance

The Redmi QA library retains nine saves. Restoring the refunded sandbox XL purchase reports FREE; sandbox purchases do not grant real paid access. Backend tests cover owner/price/coupon validation, duplicate requests, refund replay, missed deliveries and provider outages. The Android artifact uses `dev.linqo.linqo.qa`; normal Linqo is not replaced.

## Live zero-total acceptance — 12 November 2026

The account-bound production XXL checkout displayed INR 0 and completed without a payment. Signed `order.paid` and `order.updated` receipts were both processed; the authoritative order granted XXL, and QA restored the signed XXL entitlement. Signing out returned QA to Free with all nine saves intact. Fresh Google sign-in automatically restored XXL. Restarting QA retained all nine saves, and the explicit Restore live purchase action again confirmed XXL without another checkout. The private free-checkout flag is now disabled; public paid checkout and quotas remain off. Normal Linqo was not updated or signed out.

## Operational controls

Apply purchases migrations through `0009_polar_checkout_requests.sql` after a private recovery export. Keep deployment configuration and credentials under the protected private setup, never in this guide or Git. Use `POLAR_FREE_ACCEPTANCE_ENABLED` only during a controlled zero-price check, then disable it. Leave `PAYMENTS_ENABLED`, `POLAR_LIVE_APPROVED` and public client checkout/quotas off until release qualification. Build 24 switches the public purchase flow to Polar, removes the pre-checkout phone request, validates exact live/sandbox hosts and prices, and exposes the purchase/refund policy. It omits all QA checkout controls. Health and signed-in entitlement responses identify the active provider. Old Cashfree quotes do not apply the private INR 1 offer to Polar.

Before public launch, finish seller/purchase/privacy disclosures, USD pricing, approval and real-customer payment/payout qualification. A free checkout does not test UPI money movement, settlement or a bank refund. Rotate expiring setup access tokens before launch.

## Build 24 beta gates

The owner reports Polar still displays “Withdrawals are currently unavailable for your organization.” Public checkout remains off pending provider clarification, seller/policy readiness and final review. The support email validates; Gmail/business-domain warnings are not evidence of payout approval. Current automated quotes remain fixed INR; enabling USD or promising every payment method requires its own quote and currency coverage.

Full local regression: 204 Flutter tests passed (four configuration-gated cases passed separately), 53 backend tests and seven Python tooling/backup tests passed. Full Flutter analysis found no issues. A separate nine-case adversarial request check rejected missing/forged authentication, forged or oversized webhooks and retired routes. TruffleHog scanned working files and Git history offline; only known Firebase client config, test credentials and archived-binary false positives were identified. The production npm audit reports zero known advisories. A completed Strix pentest remains unavailable because of the previously documented model-provider access restriction. CodeRabbit raised seven issues across the initial and expanded reviews; all were fixed. The final focused review raised zero issues. See BETA_SECURITY_REVIEW.md. These checks do not certify the absence of vulnerabilities.

The deployment schema was compared against the earlier Polar migrations before repairing missing 0007/0008 migration-registry entries. Migration 0009 now reserves checkout requests atomically before provider creation. A private recovery export was saved before this non-destructive correction.

The build-24 QA upgrade preserved nine saves and restored XXL online after the update. No QA checkout controls are rendered, standard XXL pricing is ₹649, and purchase actions remain disabled. The normal app was not updated. The standard APK's signature matches the existing beta identity; this remains the existing development signing identity, not a newly qualified production/Play release.
