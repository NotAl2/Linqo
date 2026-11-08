# Buy Me a Coffee Shop setup

Active development; checkout and paid limits stay off until live acceptance. Ordinary support donations never grant XL/XXL. The owner reports existing payouts verified. Google Audience is In production; branding remains pending separately.

## Shop drafts

| Item | USD once | Saves | Collections | Custom model import | Product ID |
| --- | --- | --- | --- | --- | --- |
| Linqo XL | $5 | 250 | 25 | No | 596224 |
| Linqo XXL | $7 | No product quota | No product quota | Compatible models | 596225 |

The owner saved both drafts using Chrome after the form failed in Helium. Continue using Chrome for setup. Under Advanced Settings add **Linqo purchase code** as the question and make it required where supported. Keep quantity selection, member pricing, discounts and pay-what-you-want off. Launch supports one product/quantity one per order.

Suggested descriptions:

**XL:** “One-time Linqo XL unlock: up to 250 saves and 25 collections. Start in Linqo while signed into Google, copy the purchase code and paste it when asked below. Restore later with the same Google account. Built-in English AI and backups remain free. Custom-model imports require XXL. Linqo is in active development.”

**XXL:** “One-time Linqo XXL unlock: no product quotas on saves/collections and compatible custom-model imports. Device capacity and documented backup safety limits apply. Start in Linqo while signed into Google, copy the purchase code and paste it when asked below. Restore later with the same Google account. XXL is $7 even if you already bought XL; no prorated upgrade initially. Linqo is in active development.”

Choose redirect delivery to `https://linqo-app-notal2.web.app/support` and use confirmation text: “Return to Linqo and choose Restore purchase with the same Google account. If the tier has not updated after a short wait, contact support privately with your Shop order reference.” The redirect itself is not proof of payment. Review the required product-guidelines checkbox yourself. Keep products as drafts while configuring/testing the webhook and application.

## Connect the webhook

1. In Buy Me a Coffee → Integrations → Webhooks, create a Linqo Shop webhook pointing to **https://linqo-cloud.aryandurgude123.workers.dev/webhooks/buymeacoffee**.
2. Subscribe to **extra_purchase.created**, **extra_purchase.updated** and **extra_purchase.refunded**. Keep ordinary donation webhooks separate; they cannot unlock the app even if accidentally delivered here.
3. Buy Me a Coffee generates a signing secret. Copy it directly into Cloudflare → Workers & Pages → **linqo-cloud** → Settings → Variables and Secrets as secret **BMC_WEBHOOK_SECRET**, then deploy/save that secret. Do not paste it into chat or a source/config file. Alternatively run the local interactive command `node node_modules/wrangler/bin/wrangler.js secret put BMC_WEBHOOK_SECRET` from `cloud/` and enter it privately.
4. Send a dashboard test Shop event. Expect an HTTP 200 acknowledgement indicating an ignored test event, with no account unlock. Confirm the delivery is successful and the webhook remains enabled. If it fails, share only the HTTP status/error code, not its signature, secret, headers or buyer information.
5. The owner must confirm the live Shop payload includes the product's purchase-code answer and that users cannot unknowingly skip it. A missing/invalid code produces an unmatched order for support, never an email-based unlock. Do not enable general sales before this acceptance boundary is met.

No API token, account password or separate email provider is needed for the code-linking flow. Account ownership is derived from the code generated under verified Google sign-in, never the email typed into checkout.

## Controlled live acceptance

Once configuration and test deliveries pass, publish only for an explicitly authorized real purchase test consistent with Buy Me a Coffee's rules. A tester signs into the configured Linqo acceptance build, chooses the tier, copies the code and pastes it into Shop's question. Avoid self-payment arrangements that conflict with the provider's policies.

The maintainer enables server **PAYMENTS_ENABLED** for the acceptance window and client **LINQO_CHECKOUT_ENABLED** in the private test build. Keep **LINQO_PAID_LIMITS_ENABLED=false**. The normal preview remains unlimited until acceptance; no payment is made automatically by tests or deployment.

Required: XL at $5, XXL at $7, signed webhook completion, donation/test-event isolation, duplicate/retried events, refund-before-purchase, refund fallback to a separately bought XL, malformed/reused/missing code, same-Google restoration on a second device or safe reinstall, account switching, offline cached access and a backend outage. Use a separate QA application identity for automated device harnesses; never use Flutter drive on the user's app. Normal in-place APK updates must preserve its data.

A real purchase/refund cannot be certified by unit fixtures or dashboard test events. Review actual support/refund timelines, provider fees, payout eligibility and seller disclosures before enabling public limits. Monitor webhook delivery failures and retry/replay through the creator dashboard after outages. Pending/failed/out-of-order events never justify guessing ownership.

## Current evidence

- Signed Shop backend fixtures and app purchase-dialog/tier/account-switch tests are implemented.
- No new Flutter payment SDK, embedded browser, email infrastructure or persistent polling worker is added.
- Previous hosted checkout page, provider calls and verification routes are removed. A guarded schema migration refuses to discard any non-empty legacy financial ledger; production orders/payments were checked empty before replacement.
- The owner added the signing key as a plain-text Worker variable. It was converted to encrypted secret **BMC_WEBHOOK_SECRET** without displaying the value, with a protected recovery copy retained for project backups. A locally signed non-live event returned HTTP 200 `ignored:test_event`; purchases and sessions remained zero, and checkout remained disabled.
- Live Shop payment/restoration/refund acceptance is not complete. Provider-originated test delivery and required-question behavior still need confirmation. A locally signed probe verifies deployment wiring, not Buy Me a Coffee's actual delivery/signing configuration.

See [build/deployment verification](BMC_SHOP_VERIFICATION.md) for test counts, artifact/signing hashes and remaining release gates.

Official references: [Shop setup](https://help.buymeacoffee.com/en/articles/9905719-a-complete-guide-on-buy-me-a-coffee-shop), [signed webhooks](https://help.buymeacoffee.com/en/articles/15743173-how-to-setup-and-use-buy-me-a-coffee-webhooks), [event schema](https://cdn.buymeacoffee.com/assets/integrations/bmc-webhooks-openapi.json), [fees](https://help.buymeacoffee.com/en/articles/8105744-how-to-calculate-charges-on-your-payment).
