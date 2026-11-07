# Linqo account, purchase and contribution backend

Development preview, not a verified live checkout. No Firebase Functions, Firestore library, hosted inference or model upload service is used. Production launch remains gated on the checklist below.

## Provisioned in this workspace

- Worker: `https://linqo-cloud.aryandurgude123.workers.dev`
- Separate D1 databases: `linqo-purchases`, `linqo-contributions`.
- `PAYMENTS_ENABLED=false`, `CONTRIBUTIONS_ENABLED=false`, Firebase project unset.
- Signing and HMAC secrets are generated locally under ignored `.private/linqo-cloud/` and uploaded as Worker secrets. Back them up privately. Never replace them casually: account links and existing signed offline entitlements depend on them.
- The old `linqo-license` stub/database is separate and is not used by this implementation.

## Finish setup without a paid infrastructure plan

1. Create a Firebase project on **Spark**, without Analytics, Identity Platform upgrades, Firestore, Storage or billing. Add Android app `dev.linqo.linqo`; enable Google in Authentication. Configure OAuth Android SHA-1/SHA-256 for each signing certificate used. Create/record the Web OAuth client ID for Google Sign-In's `serverClientId`.
2. Enable Google Drive API in that same Google Cloud project. Configure consent branding/support/privacy links; request `drive.appdata` only when users enable backup. Add test users during development. Resolve production consent/publishing requirements in Google's console before launch; do not assume a testing OAuth configuration is production-ready.
3. Set `FIREBASE_PROJECT_ID` in `wrangler.jsonc`, then deploy. Do not enable Firebase billing. Firebase client options and OAuth IDs are public app configuration; service-account keys are not needed in the APK or Worker. The Worker verifies Google-signed Firebase ID tokens with issuer/audience/provider checks.
4. Create a Razorpay merchant account and complete the owner's identity/bank/website checks. Request international/USD payments and confirm eligibility for this software business. Set live `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` using `wrangler secret put NAME`; do not place them in Dart or Git. Register `/webhooks/razorpay` for `payment.captured`, `order.paid`, `refund.processed`. Donation webhooks are not used.
5. Before accepting real purchases, publish the actual seller/support/refund information linked from checkout. Confirm USD checkout and settlement on the approved account, including the intended customer countries. Indian domestic payment methods/currency availability must be verified; there is no invented INR price or FX conversion fallback.
6. Leave the shipped preview's client paid-limits flag off. For a private acceptance build, enable `LINQO_CHECKOUT_ENABLED` separately, with the server's payments flag/live credentials configured. This can charge real money but does not enforce library quotas. Only after an authorized real buyer's capture, entitlement, reinstall/second-device restoration, partial/full refund and delayed-event tests pass should a stable client enable limits. Account-wide outage tests must preserve the offline unlock. Test-mode Razorpay keys cannot grant production entitlements.
7. Enable contributions separately only after consent/deletion/export testing and a privacy review. Keep source payloads out of Worker logs; observability is off in the config.

Create a **private** `firebase-options.local.json` with these public client fields:

```json
{
  "LINQO_FIREBASE_PROJECT_ID": "your-project-id",
  "LINQO_FIREBASE_API_KEY": "your-firebase-client-api-key",
  "LINQO_FIREBASE_APP_ID": "your-android-app-id",
  "LINQO_FIREBASE_SENDER_ID": "your-project-number",
  "LINQO_GOOGLE_WEB_CLIENT_ID": "your-web-client-id.apps.googleusercontent.com",
  "LINQO_CLOUD_URL": "https://linqo-cloud.aryandurgude123.workers.dev",
  "LINQO_ENTITLEMENT_PUBLIC_KEY": "copy-public-key.txt",
  "LINQO_PAID_LIMITS_ENABLED": false,
  "LINQO_CHECKOUT_ENABLED": false
}
```

Use `scripts/Build-CloudPreview.ps1 -ConfigFile firebase-options.local.json`. Its allowlist rejects unexpected fields so payment secrets cannot accidentally be bundled. Missing config never prevents local library use. Sign-in alone never grants Drive permission or uploads a library.

## Deploy and test

From `cloud/`: `npm ci`, `npm test`, `npx wrangler d1 migrations apply linqo-purchases --remote`, `npx wrangler d1 migrations apply linqo-contributions --remote`, `npx wrangler deploy`. Setup is free-tier bounded; no script upgrades your plan. Do not edit an applied migration: add the next migration instead.

For a fresh deployment, generate signing/HMAC material once with `node cloud/tools/keys.mjs` from the project root, then `npx wrangler secret bulk ../.private/linqo-cloud/secrets.json` from `cloud/`. The generator refuses to overwrite existing keys. Deployments in a different account must replace the account/database IDs.

## API boundaries

- `GET /health`: public readiness; no library/account data.
- `POST /orders`, `GET /entitlement`, `POST /orders/verify`: Firebase Google bearer token; server-owned USD product prices. Signed Ed25519 entitlement includes subject, issuer, audience, tier and schema version, with no routine expiry.
- `/checkout`: short-lived opaque session in the URL fragment, cleared immediately. Server stores only its hash; session verifies against its original order. The checkout return page alone never unlocks the app.
- `PUT /consent`, `POST/GET /samples`, `DELETE /samples/:id`, `DELETE /account`: authenticated owner access. Last endpoint removes contribution data/consent; the app then deletes Firebase identity. Minimal keyed purchase identity links allow restoration with the same Google identity after account recreation.
- Contributions: 2/account/day, 100 globally/day, 8 KiB UTF-8 each, 100 MB payload ceiling and 30-day raw retention. Counters survive sample deletion. Minimal owner/ID metadata remains for later withdrawal of exported examples; expiration is distinct from a deletion request. History is paginated. Failed uploads have no bearing on saving/extraction.

## Private laptop pulls

`scripts/Export-Contributions.ps1` uses Wrangler's current-user OAuth store. Optional `-RegisterWeekly` adds Sunday 10:00 plus an overdue-only login trigger, current-user/non-admin, hidden window, network required, no embedded credentials. It skips scheduled pulls within seven days of success. A failed/missed run preserves its checkpoint and retries on a later eligible login/run. Remove through Task Scheduler or `Unregister-ScheduledTask` if unwanted.

The exporter writes private atomic, checksummed batches and acknowledges only verified files; deletes withdrawn examples, invalidates prepared datasets, and purges unreviewed copies after 90 days. It never downloads payment records or exports contributor identity hashes. Keep `.private` outside public sync and restrict it to the laptop user. Prepare/review/train with [training instructions](../tools/training/README.md); training is never scheduled.

## Operations and release gates

Monitor free Worker/D1 quotas, provider webhook deliveries and scheduled-task LastTaskResult. Keep purchase DB backups and signing keys separately secured. Daily read/write quotas can interrupt service; cached purchases and the local library continue. Optional contributions must be paused before they threaten capacity; no automatic paid upgrade.

No app analytics or automatic crash upload is added. Auth tokens are short-lived but token revocation/deletion may take up to their expiry to affect an already-issued server token. Data is protected by HTTPS and provider storage controls, not claimed to be end-to-end encrypted. Review privacy/merchant obligations before live activation.

**Not yet qualified:** real Google/Drive/Razorpay flows; production signing certificate migration; Redmi performance with live cloud flows; GPU training; model quality improvement. Unit tests/mocked Drive traffic are not evidence of successful real payments or backups.
