# Build 24 beta review — 12 November 2026

Linqo remains in active development. Public Polar sales, paid quotas and contributions are disabled. The beta APK is not a production-signing or payout-readiness certification.

## Review and fixes

CodeRabbit completed three reviews over a locally secret-scanned, source-only snapshot. The expanded review explicitly included newly added Polar, encryption and search files. Seven issues were verified and fixed; the final focused fix review raised **0 issues**. Private credentials, payment ledgers, phone data and backup archives were excluded from the review upload.

- Atomically reserve account-bound checkout requests before calling Polar, with a concurrent-request regression. Migration 0009 is applied; existing financial history is preserved.
- Recheck Google-account ownership after an asynchronous entitlement preference write, preventing an old restore from replacing a new account's state.
- Respect a public health disable after refreshing account-specific entitlement settings.
- Block public purchase actions while the unlimited preview has no active paid feature differences.
- Correct the Files-based backup recovery message and the PowerShell string/Boolean sandbox check.
- Correct plural expansion for boxes/news without requiring model inference.

## Validation

- Full Flutter suite: 204 passing, four configuration-gated skips. The three configured background-account checks and delayed-write account race passed separately with synthetic credentials and mocked network responses.
- Backend suite: 53 passing, including money/owner/product validation, forged events, refund replay, provider outages and concurrent checkout requests.
- Python backup/tooling checks: seven passing. Full Flutter analysis: no issues.
- Nine local adversarial request checks passed. Four deployed checks confirmed Polar health with payments off, 401 for unauthenticated checkout/unsigned webhooks and 404 for the retired Shop endpoint. No real payment was created by these checks.
- TruffleHog 3.99.8 completed working-file and Git-history scans with credential network verification disabled. Matches were the previously identified private Firebase client-key copies, localhost TLS/URI test fixtures and archived-APK alphabet false positives. No new confirmed production-secret leak was identified. This does not establish Firebase API-key restrictions or absence of unsupported secrets.
- npm audit reports zero known advisories in production and development dependencies.
- APK scan found none of the locally available server credential values in either artifact. The standard APK has the expected main package and matches the previous beta signing identity; QA has its separate package.
- Redmi QA updated in place to build 24, retained nine saves, restored XXL online, showed standard pricing and no developer checkout controls. Normal Linqo was not updated or signed out.

## Limits and release gates

The prior Strix assessment failed at its model provider's cybersecurity-access restriction; no completed Strix pentest is claimed and no bypass was attempted. Local checks and CodeRabbit do not prove that the app has no vulnerabilities. Firebase client API restrictions, broader low-memory/thermal testing, physical second-device acceptance and production signing recovery still require separate evidence.

A temporary signed recovery-export download link accidentally appeared in a diagnostic during the migration check. It was not committed or included in the website/APK. The project diagnostic and this task's own Wrangler export log were redacted; the provider link expires one hour after generation. Protected recovery files remain local and excluded from Git.

The owner still sees Polar withdrawals unavailable. Resolve organization/payout status and required seller disclosures before public paid sales. The zero-price production test verifies fulfillment/restoration, not real UPI settlement, bank refunds or payouts. Automated beta prices remain fixed INR; USD checkout and universal payment-method coverage are not qualified. No real-card self-test purchase should be made with Polar.

## Artifact

Standard package: `dev.linqo.linqo`, version `0.9.0+24`, 74,946,983 bytes (about 71.5 MiB).

SHA-256: `ad0a63b91a5d43808d211eb028ce1bc6288c5775c4f8ce6122e52b499d06dc54`.

This beta preserves the previous development signing identity. Install updates in place; do not uninstall or clear storage to update. No GitHub release is implied by this local artifact.
