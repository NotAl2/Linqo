# v0.9.0 beta verification

**Current prebuild (build 25, 13 November 2026):** Free 100 saves/5 collections, XL 500/30, XXL without product quotas. Limits apply locally; existing/restored content is preserved. Payments remain disabled by choice. Request reviewed prebuild access at aryandurgude123@gmail.com; donations do not automatically grant access. Polar verification/working withdrawals are owner-reported. Earlier payment and quota gate notes below are historical. See [current review](PREBUILD_REVIEW.md).


Active development. Earlier Razorpay and Buy Me a Coffee Shop experiments are retired. The maintained implementation and evidence are in [Cashfree verification](CASHFREE_VERIFICATION.md), [setup](CASHFREE_SETUP.md), [production status](PRODUCTION_SETUP.md) and [manual international upgrades](MANUAL_UNLOCKS.md). Historical project snapshots remain in private milestone backups.

Current policy: Free 100 saves/5 collections; XL ₹449, 500 saves/30 collections; XXL ₹649, no product quotas and compatible custom-model imports. Built-in English extraction and backups remain free. Paid limits remain disabled until real payment, restoration and refund acceptance pass.

Cashfree is the sole automatic purchase provider. Buy Me a Coffee remains optional support and separately reviewed manual international upgrades, with no donation webhook. Keep applied financial migrations and rejection tests for retired routes; deleting them would compromise fresh installation or ledger preservation.

## Polar migration update — 12 November 2026

See [Polar setup](POLAR_SETUP.md) for the current new-checkout implementation and release gates. The older Cashfree-only status is historical: Cashfree financial records and revocation remain supported, but new checkout selects Polar. The isolated QA free production order, signed fulfillment, sign-out and Google-account restoration passed; public checkout and paid quotas remain off while Polar withdrawals are unavailable. Build 24 removes the phone prompt for Polar and hides developer checkout controls.
