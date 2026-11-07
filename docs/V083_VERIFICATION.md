# Linqo v0.8.3 verification — 7 November 2026

Linqo remains in active development. The public v0.8.3 release uses **build 16**, retaining compatible development signing so it can install over earlier local build 15 or public v0.8.2 without clearing app data.

## Weekly update checks

The normal app checks GitHub on foreground visits, after a short delay and only on a quiet library screen. Successful checks are limited to once per seven days; failures back off for a day and remain silent. No background service, exact alarm, automatic APK download or installation is added. The setting is on by default and can be disabled in **Settings → About & updates**.

A popup appears only for an eligible newer release with the expected ARM64 APK asset. Timing, preview-channel selection, pending release and reminder snoozing persist across restarts. **Later** snoozes for a week. Manual checks remain available and suppress an immediate duplicate automatic reminder. The release-page URL is restricted to this repository on GitHub. Existing update-check HTTP bounds remain a 12-second deadline and a 1 MiB response cap.

**153 host tests passed**, and static analysis is clean. Added checks cover persistent weekly cadence, restart/snooze behavior, offline retry backoff, opt-out, preview exclusions, invalid/old cached versions, concurrent foreground events, clock rollback and a dark enlarged-text popup. The weekly popup/scheduling addition was host-tested; it was not exercised as a real newer-release notification on a physical device. No new native inference benchmark is claimed.

## Other changes included since v0.8.2

- Optional Android local alerts for extraction completion, partial results and errors. Notification contents exclude saved titles, captions and URLs; result taps open the saved item. Permission and channel controls, a test action and disabled/denied recovery are provided in Settings. Cancelled/background-stopped jobs remain silent.
- Extraction progress shows validated part coverage, elapsed time and an explicitly approximate ETA when completed parts or comparable successful session timings are available. Loading and the first unchecked part remain indeterminate. The compact optional model and two-thread defaults are unchanged.
- **Diagnostics & logs** is visible near the top of Settings. Logs remain local, opt-in, non-retroactive and exportable/clearable; native crashes/OOM kills may be missed. The old seven-version-tap shortcut remains available.

The prior local build 15 passed physical Redmi Note 7 Pro/Android 12 checks for real Android completion/error posting, silent cancellation, visible diagnostics, light/dark layouts and search during a controlled pending worker. That controlled run preserved the normal library/settings/model-selection fingerprints. A subsequent real extraction on an existing labeled test recipe produced a notification; tapping it from Android's shade opened the correct recipe and cleared the alert. Temporary notification and USB stay-awake preferences were restored. Android 13+ permission-denial recovery has host coverage; its real permission dialog was not device-tested on that Android 12 phone.

Native checks above belong to local build 15. Build 16 adds the weekly-check policy and popup. Synthetic QA data and development toolchains are not shipped; the optional model is not bundled. The release includes SHA-256 checksums and dependency/native-runtime notices regenerated from the final APK. Broader accuracy, thermal, battery and OEM testing remains future work.

## APK integrity

ARM64 APK: **72,632,792 bytes (72.6 MB)**, version **0.8.3+16**. SHA-256:

```text
585bd45f8c9b8213ebe2f3e04556c7c8d5ed89116c10803b63cff1c72bccccf5
```
