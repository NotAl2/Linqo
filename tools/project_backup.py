"""Verified local milestone archives. Run through scripts/Backup-Project.ps1.

Archives contain private project configuration and signing material. The wrapper
restricts the destination ACL before any content is written. Nothing is uploaded.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import uuid
import zipfile

FORMAT = 'linqo-project-backup-v1'
MANIFEST = 'BACKUP-MANIFEST.json'
EXCLUDED_DIRS = {'.git', '.project-backups', '.tools', '.dart_tool', '.firebase',
                 '.hosting-public', '.idea', '.impeccable', '.wrangler', '.gradle',
                 'build', 'coverage', 'node_modules', '__pycache__'}
EXCLUDED_FILES = {'.flutter-plugins-dependencies', 'local.properties'}
EXCLUDED_SUFFIXES = {'.log', '.pyc', '.pyo', '.part', '.gguf', '.apk', '.aab',
                     '.db-wal', '.db-shm'}


def linked(path):
    info = path.lstat()
    return path.is_symlink() or bool(getattr(info, 'st_file_attributes', 0) &
                                    getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400))


def git(project, *args):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0')
    result = subprocess.run(['git', '-C', str(project), *args], env=env,
                            capture_output=True, check=True)
    return result.stdout.decode('utf-8', errors='replace').strip()


def project_files(project):
    for directory, dirs, files in os.walk(project, followlinks=False):
        parent = Path(directory)
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED_DIRS and not linked(parent / d))
        for name in sorted(files):
            path = parent / name
            if name in EXCLUDED_FILES or path.suffix.lower() in EXCLUDED_SUFFIXES:
                continue
            if linked(path):
                raise ValueError('Refusing linked source file: ' + str(path.relative_to(project)))
            yield path


def digest_stream(stream):
    result, size = hashlib.sha256(), 0
    while chunk := stream.read(1024 * 1024):
        result.update(chunk)
        size += len(chunk)
    return result.hexdigest(), size


def verify(archive, project):
    with zipfile.ZipFile(archive) as zipped:
        manifest = json.loads(zipped.read(MANIFEST))
        if manifest.get('format') != FORMAT or manifest.get('project') != str(project):
            raise ValueError('Archive does not belong to this project.')
        expected = {row['path'] for row in manifest['files']}
        names = zipped.namelist()
        if len(names) != len(set(names)) or set(names) != expected | {MANIFEST}:
            raise ValueError('Archive entries do not match the manifest.')
        for row in manifest['files']:
            with zipped.open(row['path']) as content:
                checksum, size = digest_stream(content)
            if checksum != row['sha256'] or size != row['bytes']:
                raise ValueError('Archive checksum failed: ' + row['path'])
        if 'git/repository.bundle' not in expected:
            raise ValueError('Git recovery bundle is missing.')
        return manifest


def create_backup(project, milestone, signing_key=None):
    project = Path(project).resolve(strict=True)
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,70}', milestone):
        raise ValueError('Use a short milestone name with letters, digits, hyphens or underscores.')
    backup_root = project / '.project-backups'
    backup_root.mkdir(exist_ok=True)
    if linked(backup_root) or backup_root.resolve().parent != project:
        raise ValueError('Backup destination escaped the project or is linked.')
    # Exclusive lock prevents concurrent writers and retention races.
    lock = backup_root / '.backup.lock'
    handle = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.write(handle, f'pid={os.getpid()}\n'.encode('ascii'))
    os.close(handle)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    identity = f'linqo-{stamp}-{milestone}'
    temporary = backup_root / (identity + '.part')
    destination = backup_root / (identity + '.zip')
    bundle = backup_root / ('.git-' + uuid.uuid4().hex + '.bundle')
    try:
        head = git(project, 'rev-parse', 'HEAD')
        status = git(project, 'status', '--porcelain=v1', '--untracked-files=normal')
        git(project, 'bundle', 'create', str(bundle), '--all', 'HEAD')
        git(project, 'bundle', 'verify', str(bundle))
        sources = [(path, 'project/' + path.relative_to(project).as_posix())
                   for path in project_files(project)]
        sources.append((bundle, 'git/repository.bundle'))
        apk = project / 'build/app/outputs/flutter-apk/app-release.apk'
        if apk.is_file() and not linked(apk):
            sources.append((apk, 'recovery/current-release.apk'))
        if signing_key is not None and Path(signing_key).is_file():
            key = Path(signing_key)
            if linked(key):
                raise ValueError('Refusing a linked signing key.')
            sources.append((key, 'recovery/signing/debug.keystore'))
        manifest = {'format': FORMAT, 'project': str(project), 'milestone': milestone,
                    'created_utc': datetime.now(timezone.utc).isoformat(),
                    'git_head': head, 'git_status': status,
                    'excluded_directories': sorted(EXCLUDED_DIRS),
                    'excluded_suffixes': sorted(EXCLUDED_SUFFIXES), 'files': []}
        original_stats = {}
        with zipfile.ZipFile(temporary, 'x', compression=zipfile.ZIP_DEFLATED,
                             compresslevel=3, allowZip64=True) as zipped:
            for path, archive_name in sources:
                before = path.stat()
                checksum, size = hashlib.sha256(), 0
                with path.open('rb') as source, zipped.open(archive_name, 'w', force_zip64=True) as output:
                    while chunk := source.read(1024 * 1024):
                        checksum.update(chunk)
                        size += len(chunk)
                        output.write(chunk)
                after = path.stat()
                if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                    raise ValueError('Source changed while backing up: ' + archive_name)
                original_stats[path] = (after.st_size, after.st_mtime_ns)
                manifest['files'].append({'path': archive_name, 'bytes': size,
                                          'sha256': checksum.hexdigest()})
            if git(project, 'rev-parse', 'HEAD') != head:
                raise ValueError('Git HEAD changed during backup; retry when idle.')
            if set(project_files(project)) != {path for path, name in sources if name.startswith('project/')}:
                raise ValueError('Project files changed during backup; retry when idle.')
            for path, expected in original_stats.items():
                current = path.stat()
                if (current.st_size, current.st_mtime_ns) != expected:
                    raise ValueError('Source changed before backup completed; retry when idle.')
            zipped.writestr(MANIFEST, json.dumps(manifest, ensure_ascii=False, indent=2))
        verify(temporary, project)
        os.replace(temporary, destination)
        # Only our project's verified archives participate in retention. Unknown
        # files are preserved; never delete arbitrary ZIPs or follow links.
        owned = []
        for archive in backup_root.glob('linqo-*.zip'):
            if linked(archive):
                raise ValueError('Refusing linked backup archive.')
            with zipfile.ZipFile(archive) as zipped:
                item = json.loads(zipped.read(MANIFEST))
            if item.get('format') == FORMAT and item.get('project') == str(project):
                owned.append((item['created_utc'], archive))
        owned.sort(reverse=True)
        for _, archive in owned[:3]:
            verify(archive, project)
        removed = []
        for _, archive in owned[3:]:
            if archive.resolve().parent != backup_root.resolve() or linked(archive):
                raise ValueError('Unsafe retention target.')
            archive.unlink()
            removed.append(archive.name)
        with destination.open('rb') as data:
            checksum, size = digest_stream(data)
        return {'archive': str(destination), 'sha256': checksum, 'bytes': size,
                'files': len(manifest['files']), 'retained': min(len(owned), 3),
                'removed': removed}
    finally:
        for path in (temporary, bundle, lock):
            if path.exists() and path.parent.resolve() == backup_root.resolve() and not linked(path):
                path.unlink()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True, type=Path)
    parser.add_argument('--milestone', required=True)
    args = parser.parse_args()
    print(json.dumps(create_backup(args.project, args.milestone,
                                  Path.home() / '.android/debug.keystore'), indent=2))
