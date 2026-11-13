# Production account setup and acceptance

**Current prebuild (build 25, 13 November 2026):** Free 100 saves/5 collections, XL 500/30, XXL without product quotas. Limits apply locally; existing/restored content is preserved. Payments remain disabled by choice. Request reviewed prebuild access at aryandurgude123@gmail.com; donations do not automatically grant access. Polar verification/working withdrawals are owner-reported. Earlier payment and quota gate notes below are historical. See [current review](PREBUILD_REVIEW.md).


Linqo remains in active development. The owner confirmed OAuth Audience **In production** and Data Access **Verification not required** on 2026-11-08. Branding rejected the Firebase homepage as not registered to the owner. The owner chose to leave branding pending rather than register a custom domain now. This is not Google brand approval or live Cashfree purchase acceptance. Paid limits, checkout and contribution intake remain disabled. Contributions are also gated off in the client: stored opt-in cannot queue/send source text or enable the switch. Before a future build lifts that gate, audit restored Google/Drive provenance and exclude it from training; the current implementation's public-source flags alone are insufficient for that review.

## Public OAuth pages

Static pages are hosted on Firebase Spark at:

- Home: https://linqo-app-notal2.web.app/
- Privacy: https://linqo-app-notal2.web.app/privacy
- Terms: https://linqo-app-notal2.web.app/terms
- Support: https://linqo-app-notal2.web.app/support
- Planned purchases/refunds: https://linqo-app-notal2.web.app/purchases
- Digital delivery: https://linqo-app-notal2.web.app/shipping

Build with `python tools/build_public_site.py`, then deploy **Hosting only** with the official Firebase CLI, project `linqo-app-notal2`, owner account `gamer12773@gmail.com`. Source: `hosting/`, `policies/`, `firebase.json`. Only the allowlisted generated `.hosting-public/` directory is deployed; it contains no credentials, APKs or web tracking scripts. Do not point Hosting at the repository root. Current public support/purchase/refund contact is aryandurgude123@gmail.com. The Firebase owner login above is unchanged.

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

`integration_test/drive_acceptance_test.dart` uses separate temporary SQLite libraries, a synthetic binary attachment, notes/favourite/collection fixtures and unique QA snapshot markers. The first live run rejected its invalid synthetic internal filename; that fixture is corrected. However, Flutter drive's host cleanup uninstalled the target app and deleted its data, despite the Dart test itself not opening the main library. A second run exposed the lost identity before any upload. **Do not run this harness against the user's installed application identity.** Use a separately registered test app identity. `scripts/flutter.ps1` now rejects drive commands without explicit `--keep-app-running`, and rejects `--no-keep-app-running`; this was verified to stop before SDK/device work. The full automated attachment/corrupt-archive live harness remains unqualified.

Recovery used the normal signed APK and the verified 2026-11-07 21:43:28 IST Drive snapshot. Four saves/favourites were recovered; original local settings were reset. The owner subsequently confirmed there were no newer changes or settings to recover. The exact 396,705,472-byte Qwen model was restored from a laptop copy matching the pinned SHA-256, imported to private app storage and verified installed after restart; the temporary shared recovery copy was removed. Google sign-in/Drive were reconnected, two CPU threads are the default and the original USB sleep setting was restored to 0.

The normal app then completed four verified uploads at 00:58:34, 00:58:43, 00:58:52 and 00:59:01 IST on 2026-11-08. The picker retained three snapshots from this fresh installation plus the older recovery snapshot. Explicit newest-snapshot merge showed successful restoration, kept exactly four saves without duplicates and survived a cold restart. This is evidence of real reinstall recovery, per-installation retention and duplicate-safe normal-app restoration, not physical second-device or attachment acceptance. One automatic empty snapshot created during reconnection was superseded/pruned by the verified normal uploads; the older recovery snapshot remained intact.

Still required: genuine second-device identity acceptance; explicit account-switch consent on real accounts; provider full-storage behavior where a suitable test account exists; elapsed-day scheduling/backoff; physical-device interruption/revocation cases; attachment/corrupt-archive acceptance in a separately registered QA app; Redmi scrolling/extraction under cloud-related memory and lifecycle pressure. Mock coverage and same-phone reinstall recovery are not physical multi-device acceptance.

## Cashfree purchase setup

Latest status (2026-11-11): the owner reports the actual checkout domain Approved and production webhook saved. Both live credentials are confirmed encrypted Worker secrets. Sandbox XL checkout and configured-version payment delivery passed. After Cashfree support credited test balance, a fresh ₹449 payment and full refund reached PAID/refund SUCCESS and were recorded in Linqo; the older refund remains ONHOLD. Separate Linqo QA and normal installations on the Redmi resolve to the same Google-linked account; the Free restoration state survives QA restart. Real paid restoration/revocation, settlement and required seller disclosures remain pending. Public creator NotAl2, support aryandurgude123@gmail.com and a 15-day refund-request window are published. Checkout and paid limits remain disabled. Historical setup notes below are superseded by this status and CASHFREE_VERIFICATION.md where applicable.

The current implementation uses Cashfree hosted checkout for domestic INR payments: XL ₹449 once (500 saves/30 collections), XXL ₹649 once (unlimited product quotas and compatible custom-model imports). Cashfree international payments are unavailable. Manual international upgrades (US$4.99 XL / US$6.99 XXL) require email confirmation, a Google-linked account code and owner verification. Ordinary donations do not automatically grant a tier. See MANUAL_UNLOCKS.md.

Follow [Cashfree setup](CASHFREE_SETUP.md) and [verification evidence](CASHFREE_VERIFICATION.md). Existing Shop test evidence is historical, not Cashfree acceptance. The earlier Payment Gateway “Product is not activated” dashboard state followed KYC submission. As recorded in the latest status above, sandbox/live credentials, checkout-domain approval, production webhook setup and sandbox XL checkout are now complete. Confirm live product activation and finish real domestic payment/settlement/paid-restoration/completed-refund acceptance before enabling public checkout or quotas.

Local server defaults are sandbox and payments disabled. No Cashfree credentials are embedded in Dart. Cloudflare device authorization subsequently succeeded on 2026-11-09. The zero-financial-history guard passed, migration 0003 applied and the Cashfree replacement deployed with payments off, sandbox mode and contributions off. The original Google identity link was preserved. Retired Shop routes return 404 and its signing secret was removed; donations remain separate. Updated Cashfree INR policies are published on Firebase Hosting. Cashfree test/live credentials were subsequently configured; live acceptance and the full sandbox refund remain pending as described above. See the verification record for deployment evidence.

The guarded migration refuses to delete any non-empty Shop financial ledger and preserves Google identity links. Production signed entitlements keep their existing issuer, audience and signing key. Sandbox orders never grant production tiers. Paid limits remain off throughout beta. Google branding and the remaining Drive/device qualification gates above are independent.

## Polar migration update — 12 November 2026

See [Polar setup](POLAR_SETUP.md) for the current new-checkout implementation and release gates. The older Cashfree-only status is historical: Cashfree financial records and revocation remain supported, but new checkout selects Polar. The isolated QA free production order, signed fulfillment, sign-out and Google-account restoration passed; public checkout and paid quotas remain off while Polar withdrawals are unavailable. Build 24 removes the phone prompt for Polar and hides developer checkout controls.
