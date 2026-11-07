# Production account setup and acceptance

Linqo remains in active development. This checklist records preparation, not Google approval or live merchant activation. Paid limits, checkout and contribution intake remain disabled. Contributions are also gated off in the client: stored opt-in cannot queue/send source text or enable the switch. Before a future build lifts that gate, audit restored Google/Drive provenance and exclude it from training; the current implementation's public-source flags alone are insufficient for that review.

## Public OAuth pages

Static pages are hosted on Firebase Spark at:

- Home: https://linqo-app-notal2.web.app/
- Privacy: https://linqo-app-notal2.web.app/privacy
- Terms: https://linqo-app-notal2.web.app/terms
- Support: https://linqo-app-notal2.web.app/support
- Planned purchases/refunds: https://linqo-app-notal2.web.app/purchases
- Digital delivery: https://linqo-app-notal2.web.app/shipping

Build with `python tools/build_public_site.py`, then deploy **Hosting only** with the official Firebase CLI, project `linqo-app-notal2`, owner account `gamer12773@gmail.com`. Source: `hosting/`, `policies/`, `firebase.json`. Only the allowlisted generated `.hosting-public/` directory is deployed; it contains no credentials, APKs or web tracking scripts. Do not point Hosting at the repository root. Current public contact is the owner's previously supplied Gmail address.

Firebase billing was checked unlinked before setup. Hosting has free-tier storage/transfer quotas and can become unavailable when exhausted; no Blaze upgrade is authorized or scripted. Keep APK downloads on GitHub Releases.

## Owner's Google console steps

1. Open https://console.cloud.google.com/auth/branding?project=linqo-app-notal2 under the owning account. Use app name **Linqo**, an owner-monitored support/developer email, and the home/privacy/terms URLs above. Use the existing faithful mascot logo if adding a logo; it may require brand review.
2. Check Authorized domains. Use the app's own Hosting domain if Google accepts it. Do not claim ownership of `web.app`, `firebaseapp.com`, `github.com` or another provider's root domain. If Google requests DNS verification, record the exact finding; a verified custom domain may be needed. A successful Hosting deploy or URL-prefix verification does not prove Google's domain/brand requirement passed.
3. Open Data Access. Declare only `openid`, `userinfo.email`, `userinfo.profile` and `https://www.googleapis.com/auth/drive.appdata` as required by the sign-in/backup flow. The Drive app-data scope is non-sensitive; do not add full Drive, Drive read-only, Gmail or unrelated scopes.
4. Check Audience. External distribution needs **In production**. Only publish after the form is accurate and public pages are accepted. Record the actual resulting publishing status; pressing Publish is not brand approval.
5. Check Verification Center for required actions. Complete brand verification if requested and wait for the result. Basic non-sensitive scopes do not establish exemption from brand/domain requirements. Do not claim that every user can sign in based on one developer-account test.
6. Retest with a non-owner account and the release signing identity. Existing Redmi sign-in passed using a separate end-user account; production status and wider consent acceptance are still awaiting console confirmation.

Google's production policy calls for separate development and production projects. Treat the existing configured project as the production candidate; create/use a distinct staging project for future development OAuth clients before public launch. Do not remove the current signing fingerprint or change project IDs in installed users' builds without a tested migration. Production signing/key backup and upgrade migration remain separate release gates.

References: [scope classifications](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), [production OAuth policy](https://developers.google.com/identity/protocols/oauth2/production-readiness/policy-compliance), [domain verification](https://support.google.com/cloud/answer/13804266), [Hosting quotas](https://firebase.google.com/docs/hosting/usage-quotas-pricing).

## Drive test coverage

Passed previously on the Redmi: Google sign-in; separate Drive consent; manual upload; snapshot listing; explicit merge restore; four existing saves preserved without duplicates; model/settings preserved; process restart retained account, permission and last-success timestamp.

Expanded automated tests now exercise quota/permission/rate-limit/provider failures without pruning, post-upload cancellation, download cancellation before and during transfer, connection loss mid-stream, corrupt checksums, changed remote size, partial-file cleanup and listing pagination. These tests simulate failures; they do not fill or revoke a real user's Google account.

`integration_test/drive_acceptance_test.dart` is a real-Drive harness awaiting an unlocked, already authorized device. It uses separate temporary SQLite libraries, a synthetic binary attachment, notes/favourite/collection fixtures and unique QA snapshot markers. It checks four uploads retain three snapshots, portable recovery into an empty database, duplicate merging and invalid remote archive rejection. Its cleanup deletes only that run's uniquely marked QA snapshots. It never opens the main library database or changes model/settings files. Restore the normal APK in place after testing. If cleanup is interrupted, recover the QA marker from the test report and delete only those snapshots.

Still required: genuine second-device/restored-install identity acceptance; explicit account-switch consent on real accounts; real permission revocation/reconnection; provider full-storage behavior where a suitable test account exists; foreground/backoff scheduling over elapsed days; Redmi scrolling/extraction under cloud-related memory and lifecycle pressure. Mock coverage and an empty test database on the same phone are not physical multi-device acceptance.

## Owner's Razorpay steps

1. Sign up/sign in at https://dashboard.razorpay.com. The owner enters identity/PAN/bank details and accepts merchant terms directly. Never share these details, passwords or OTPs in chat or Git.
2. Select the truthful business type/category and complete onboarding/KYC. Confirm whether the account is individual/freelancer or registered business. Razorpay's current international-payments documentation routes individual/freelancer international acceptance through PayPal; the existing card checkout must not be enabled on an unapproved assumption. Check the dashboard/support decision for this specific account and intended countries.
3. Supply the real merchant identity and finalize support/refund terms, processing timeframes and required business disclosures before presenting the policy pages as live-sales-ready. Current pages explicitly state checkout is unavailable; draft purchase disclosures are not proof of merchant approval.
4. Request the approved international/USD method. Planned products remain XL US$5 once and XXL US$10 once, with no invented INR conversion. Verify domestic buyer support separately. An XL owner purchasing XXL pays the full US$10, disclosed before checkout.
5. After activation, create keys in the provider dashboard. Enter live `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` directly through Wrangler's local interactive secret prompt or Cloudflare Worker secrets. Do not paste values into chat, Flutter defines, source, task arguments or screenshots. Keep test payments in a separate staging Worker/database; test keys cannot grant production entitlements.
6. Register `https://linqo-cloud.aryandurgude123.workers.dev/webhooks/razorpay` for `payment.captured`, `order.paid` and `refund.processed`, using the same private webhook secret configured on the Worker.
7. Complete authorized real capture, settlement, restoration on another device/reinstall, full/partial refund and delayed/duplicate webhook acceptance. Only then enable public checkout/limits. No live key, charge, refund or paid-limit activation has been performed in this setup pass.

Buy Me a Coffee remains a voluntary donation link and does not grant a tier. Hosting free tiers do not remove Razorpay/PayPal transaction fees.

Reference: [Razorpay international onboarding and business-type requirements](https://razorpay.com/docs/payments/international-payments).
