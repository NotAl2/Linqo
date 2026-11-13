# Build 24 beta candidate — 2026-11-12

**Current prebuild (build 25, 13 November 2026):** Free 100 saves/5 collections, XL 500/30, XXL without product quotas. Limits apply locally; existing/restored content is preserved. Payments remain disabled by choice. Request reviewed prebuild access at aryandurgude123@gmail.com; donations do not automatically grant access. Polar verification/working withdrawals are owner-reported. Earlier payment and quota gate notes below are historical. See [current review](PREBUILD_REVIEW.md).


Linqo is in active development. This is not v1.0 and not an activated paid-limit release.

## Current product

| Tier | Price | Saves | Collections | Custom model import |
| --- | --- | --- | --- | --- |
| Free | Free | 100 | 5 | No |
| XL | ₹449 once | 500 | 30 | No |
| XXL | ₹649 once | No product quota | No product quota | Compatible models |

Built-in English extraction and local/optional Drive backups remain free. Enhanced XL model options and future advanced XXL features are planned, not implemented benefits. Limits apply to new additions; existing/restored libraries and installed models survive downgrade. The beta candidate keeps paid limits off.

## Automatic and manual purchases

Polar is configured for new hosted checkout at fixed INR beta prices. Historical Cashfree purchases/refunds remain restorable; the old provider is not used for new public checkout. Orders and signed entitlements belong to the Google identity. Ordinary Buy Me a Coffee donations are separate; owner-verified manual international upgrades remain available only by prior agreement. Retired Shop/Razorpay runtime routes and dependencies are absent. Applied SQL migrations and negative tests for retired endpoints stay because fresh databases and historical financial records depend on them. External developer plugins are not APK integrations.

Public creator is NotAl2; support is aryandurgude123@gmail.com. Upgrade refund requests have a 15-calendar-day window. Confirm any provider-required legal seller disclosures and settlement details before live sales; the alias is not an invented registered company.

## Evidence and remaining gates

- Local regression covers persistence, sharing, title/preview recovery, grounding, model lifecycle/cancellation, search, backups, account isolation, signatures, payment/refund idempotency and quotas. Current evidence is in POLAR_SETUP.md; CASHFREE_VERIFICATION.md preserves historical payment evidence.
- Redmi sandbox XL checkout and 2025-01-01 payment webhook delivery passed. Two separate Redmi installations resolve to the same Google-linked purchase account and restore Free after restart. Normal app data was retained. This is not a real paid restoration or physical second-device test.
- After Cashfree support credited test balance, a fresh ₹449 sandbox payment and full refund passed (PAID → refund SUCCESS), and Linqo recorded the capture and refund. The original older refund remains ONHOLD. No real funds were transferred. This does not prove test payments automatically top up the refund wallet, or qualify real paid revocation.
- The owner reports production-domain approval and the production webhook configured. Live/test credentials exist as encrypted Worker secrets. Actual live credential authentication, activated domestic payment methods and settlement-account readiness still require provider acceptance.
- Next controlled live test: complete one authorized real purchase, confirm captured payment and signed XL/XXL, restore in the separate QA installation with the same Google identity, verify another account remains Free, then complete a real refund and observe online revocation without deleting saves. Provider fees may still apply. Settlement evidence is separate; an immediate refund does not prove settlement.
- Keep backend checkout disabled outside an attended test window. Keep paid limits off until the real payment/restoration/refund checks pass. Normal preview builder deliberately rejects a paid-limit build; do not remove this guard merely to call a build final.
- Production signing/key recovery and tested upgrade migration remain pending. Preserve the existing signing identity for in-place beta updates. Broader low-memory/thermal/latency and Drive interruption/account-switch hardware checks are not replaced by unit tests.
- Publish only after remaining failures are resolved: accurate active-development notes, APK checksum/credential scan, license notices, privacy/purchase disclosures and verified milestone backup. No GitHub release or v1.0 qualification is implied by this candidate.

## Superseding Polar gate

The earlier Cashfree-only gates above are historical. Polar sandbox UPI, refunded XL → Free, signed live zero-price XXL fulfillment, account sign-out and same-account restoration after restart have passed in isolated Redmi QA. Normal Linqo was not modified. Build 24 implements the public Polar UI with checkout-enable configuration but the server remains disabled; paid limits remain off. The owner must resolve Polar's withdrawal restriction before public paid sales. A free checkout does not verify a real customer's settlement, bank refund or payout. Final CodeRabbit review, APK scan and the latest verified milestone backup are recorded in the final beta evidence. Do not create real-card self-test purchases with Polar.
