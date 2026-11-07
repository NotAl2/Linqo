# Local project milestone backups

Run from the project root after every major milestone:

```powershell
.\scripts\Backup-Project.ps1 -Milestone completed-step-name
```

The command creates a versioned ZIP beside the project in `C:/Projects/Linqo Backups/`, for example `Linqo-v0.9.0+17-<UTC timestamp>-<milestone>.zip`. The version comes from `pubspec.yaml`. It keeps the newest **three verified project archives** across app versions, removing older owned versions only after the new archive and retained versions pass SHA-256 verification. Concurrent backups are blocked. Source changes during backup fail the run; retry with development writers idle. Failed verification never triggers pruning. Unknown files are not deleted.

Included: the working source tree (including uncommitted/untracked work), assets, docs, lockfiles, local project configuration/private data, an all-refs Git bundle, the current release APK when available, and the current user's Android debug signing key when present. The manifest lists checksums, exclusions, Git HEAD and working-tree status. Current preview signing recovery is separate from any future externally stored production key; add that key to the recovery plan before changing signing.

Excluded: downloaded SDKs/tools/models, rebuildable output/caches/dependencies, logs, and the backup directory itself. These are **project** backups, separate from phone-library backups. The script does not read or change a phone, deploy, upload, or schedule a timed job.

Archives include secrets and are not encrypted. The PowerShell wrapper restricts access to the current Windows user and SYSTEM before writing; the directory is outside the repository. The legacy in-project `.project-backups/` location stays Git-ignored. Do not upload archives or extract their private configuration into a public repository.

## Verify and recover

Each archive contains `BACKUP-MANIFEST.json`, `project/`, `git/repository.bundle` and optional `recovery/` files. To recover, extract into a **new** private directory, clone `git/repository.bundle` into a new checkout, then overlay `project/` to recover the exact working files, including uncommitted changes. Retain the recovery signing key privately for reproducing the preview signing identity. Reinstall SDK/dependency caches from the recorded lockfiles. Never overwrite another signing key without checking the certificate.

For an independent integrity check, use the backup module's `verify(archive_path, original_project_path)` function. The original project path is recorded in the manifest; integrity verification does not require the original source files to exist.

Tests: `python -m unittest discover -s tools/tests -p test_project_backup.py -v`. They exercise real Git bundle restoration, uncommitted/private/untracked files, four-to-three retention, corruption protection and concurrency locking in disposable fixture repositories.
