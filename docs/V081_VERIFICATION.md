# Linqo 0.8.1 verification — 5 November 2026

Final scope: a normal animated native tutorial, unlimited local library, optional Buy Me a Coffee donations, and the existing optional online features. Paid unlocks, save/collection quotas, accounts, purchase restoration and licensing connectivity were removed at the owner's request.

## Changes and cleanup

- Four skippable welcome/tutorial pages use Flutter widgets and short transitions. Native sample save/collection interactions do not write real library data. Reduced motion is supported; there are no tutorial videos, timers or image/video decoders.
- The tutorial remains replayable in Settings. Existing onboarding completion is respected on upgrade.
- Removed the entitlement client, quota exception/checks, unlock screen and cryptography package dependency. The library test explicitly creates 60 saves and 8 collections successfully. Input/storage safeguards are unrelated to monetization and remain in place.
- The discarded licensing prototype was archived in ignored local development storage outside the app. The provisioned Worker was changed to a disabled stub: health reports `payments_enabled: false` and `processing: false`; it performs no payment verification, D1 work or email delivery. Its unused database was not destroyed. If a Buy Me a Coffee webhook was created during setup, the owner can disable it in Integrations; donations require no webhook.
- Captions/previews, optional model download, manual GitHub update checks and the external donation link retain their existing network behavior. Library/search/notes/backups and inference remain local. No paid/account backend is used.

## Validation

**133 Flutter tests passed**, static analysis is clean, and `git diff --check` passed. Phone and tablet emulator integration checks passed with light/dark themes, enlarged text and reduced motion, covering Skip/completion persistence, native sample-save feedback, Settings, hidden diagnostics and no automatic model start/download. Native captures were inspected in one batched review; no further visual correction was required.

The real model runtime was not changed or re-benchmarked in this patch. Earlier Redmi model/cancellation/recovery measurements belong to v0.8.0 and are not new 0.8.1 performance claims.

The ARM64 APK is **72,500,652 bytes** (72.5 MB decimal), SHA-256:

`d722e2920b07e702c21131cf56db2157163e4fa4e69e5b1ffba38516ae8726e0`

APK inspection confirmed no tutorial media files, no bundled GGUF and no purchase-restoration markers in the app binary. Accompanying dependency notices and checksums were regenerated from that APK.

Installed in place on the connected Redmi as **0.8.1+13**, with the same CE data inode (34117). No uninstall, clear-data, model deletion or model download was performed. The normal emulator main entry point was restored, viewport overrides reset, and the headless test emulator stopped to free laptop memory. Phone USB stay-awake remains at its original value, 0.

These checks cover the build prepared for the [v0.8.1 GitHub release](https://github.com/NotAl2/Linqo/releases/tag/v0.8.1). This remains a development preview. Existing development signing is retained for compatible updates. Broader v1.0 optimization, battery/thermal/long-session/OEM checks remain later work.
