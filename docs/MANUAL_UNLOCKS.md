# Owner-verified manual upgrades

**Current prebuild (build 25, 13 November 2026):** Free 100 saves/5 collections, XL 500/30, XXL without product quotas. Limits apply locally; existing/restored content is preserved. Payments remain disabled by choice. Request reviewed prebuild access at aryandurgude123@gmail.com; donations do not automatically grant access. Polar verification/working withdrawals are owner-reported. Earlier payment and quota gate notes below are historical. See [current review](PREBUILD_REVIEW.md).


Current amounts: **XL US$4.99 (499 cents)**, **XXL US$6.99 (699 cents)**. Indian Cashfree prices are separately fixed at **₹449 / ₹649**. No live exchange-rate conversion is used. The development preview stays unlimited; don't invite real payments until provider eligibility, refund disclosures and the actual grant/restore flow have passed acceptance.

## Buyer flow

Sign in with the Google account that should own the upgrade. Open Account & backup, choose Get account code if necessary, then copy the `LQ-…` code. Email aryandurgude123@gmail.com before sending money. After receiving instructions and supporting through Buy Me a Coffee, email the provider payment reference, requested tier and code. No passwords, authentication tokens, card details or bank details belong in the email. The payment email need not match Google, because the verified Linqo code identifies the account.

The owner checks the actual settled payment, amount/currency and refund/dispute status in the provider dashboard. A screenshot or claimed receipt alone is insufficient. Review before granting; this is not automatic or instant. Ordinary donations without a manual upgrade request remain voluntary support. A payment cannot be reused for another account or tier.

Also verify that the requester controls the payer's contact/payment, rather than merely knowing a payment reference. If unclear, confirm through the payer contact recorded by the provider before granting. The payer contact can differ from the Google account; never bind ownership by an unverified email claim alone.

## Maintainer commands

Run from `cloud/` on the maintainer laptop with authenticated Wrangler access to the purchases D1 database. No administrator endpoint or key is shipped in Linqo. The command stores a SHA-256 hash of the provider reference, not its plaintext or buyer email. Codes are support identifiers, not login credentials. Keep the payment reference/code out of public issues and screenshots.

After verifying an XL payment of exactly US$4.99, substitute the real code/reference:

```powershell
node tools/manual-unlocks.mjs grant --code LQ_REPLACE_WITH_BUYER_CODE --tier xl --reference REPLACE_WITH_PROVIDER_PAYMENT_ID --amount-minor 499 --verified
```

For XXL use `--tier xxl --amount-minor 699`. Enter the actual verified USD cents if more was paid. Non-USD payments require a separately agreed verification policy; the tool deliberately does not invent exchange rates. `--verified` records your review decision; it does not call Buy Me a Coffee or verify a screenshot for you. Minimum amounts and known account codes are checked. Repeating the same unchanged grant is idempotent. A conflicting or revoked receipt is rejected.

After a refund, chargeback or incorrect grant, revoke that payment's grant:

```powershell
node tools/manual-unlocks.mjs revoke --reference REPLACE_WITH_PROVIDER_PAYMENT_ID --reason refund --confirm
```

Allowed reasons are `refund`, `chargeback`, `mistake`. Refunding through the provider does not automatically invoke this command. Keep monitoring refund/dispute messages and revoke when appropriate. This command revokes Linqo access only; it does not send a refund. Resolve mistaken account binding privately before attempting another grant; a revoked receipt cannot be silently reassigned.

## Restoration and revocation

Buyers choose Restore purchase after grant while signed into the same Google account. The existing canonical Google-provider binding survives Firebase account deletion/recreation, and returned Ed25519 tokens bind to the current Firebase UID. Reinstall/another device gets the same grant after sign-in. Other Google accounts cannot claim it. The highest unrevoked Cashfree/manual tier wins; revoking XXL falls back to independently paid XL or Free. Local saves/settings are never deleted by tier changes.

Tokens have no routine expiry, so revoked access can remain offline until the next successful online refresh. Signing out removes access to the previous account's cached tier. Minimal grant and account-binding records remain for restoration/refund support after account deletion; the privacy notice describes this retention.

## Deployment and qualification

Privately export purchases D1 before applying append-only migration `0004_manual_unlocks.sql`. It preserves historic ₹449/₹399 Cashfree orders and their payment/refund links. Migration `0005_manual_prices.sql` preserves older grants while allowing the revised USD amounts. Apply migration before deploying the updated Worker. Existing HMAC and entitlement signing keys must remain unchanged. Keep production checkout/paid limits disabled. Validate real account-code generation, an explicitly authorized test grant, same-account restoration on another installation, different-account rejection and revocation before enabling this channel. Synthetic local tests do not establish merchant approval or payment settlement.
