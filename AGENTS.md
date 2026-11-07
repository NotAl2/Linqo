# Linqo project working rules

- After every major implementation, setup, release, or recovery milestone, run `scripts/Backup-Project.ps1 -Milestone <short-name>` before reporting completion. The user explicitly requested local milestone backups, retaining the newest three verified versions.
- Backups live beside the project in `C:/Projects/Linqo Backups/`, outside the repository, and use `Linqo-v<pubspec-version>-<UTC timestamp>-<milestone>.zip` names. They include local project secrets. Never upload or commit these archives. Use the PowerShell wrapper so Windows access restrictions are applied before writing.
- The backup command verifies a new archive before removing older owned backups. If verification fails, preserve existing versions and report the failure. Do not manually delete unknown archives or broaden the retention target.
- Run backup with development/build writers idle. Keep downloaded SDKs, model weights and rebuildable caches excluded. The archives cover this project, not a phone's application data.
- Never run Flutter integration tests against the user's main Linqo application identity. Use a separate QA identity. Flutter drive defaults to uninstalling its target app; the project wrapper requires explicit `--keep-app-running` as an additional safeguard.
