import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

MODULE_PATH = Path(__file__).resolve().parents[1] / 'project_backup.py'
spec = importlib.util.spec_from_file_location('project_backup', MODULE_PATH)
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class ProjectBackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='linqo-project-backup-test-')
        self.project = Path(self.temp.name).resolve() / 'Linqo'
        self.project.mkdir()
        self.backup_root = self.project.parent / 'Linqo Backups'
        (self.project / 'pubspec.yaml').write_text('version: 0.9.0+17\n', encoding='utf-8')
        self.git('init', '-b', 'main')
        (self.project / 'app.dart').write_text('committed source', encoding='utf-8')
        (self.project / '.gitignore').write_text('.project-backups/\n.tools/\n.private/\n', encoding='utf-8')
        self.git('add', 'app.dart', '.gitignore')
        self.git('-c', 'user.name=Backup Test', '-c', 'user.email=backup@example.invalid', 'commit', '-m', 'fixture')

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.project), *args],
                              capture_output=True, check=True)

    def test_recovers_working_source_private_config_untracked_files_and_git_history(self):
        (self.project / 'app.dart').write_text('uncommitted work', encoding='utf-8')
        (self.project / 'notes.md').write_text('untracked notes', encoding='utf-8')
        (self.project / '.private').mkdir()
        (self.project / '.private/config.json').write_text('{"fixture":true}', encoding='utf-8')
        (self.project / '.tools').mkdir()
        (self.project / '.tools/cache.bin').write_bytes(b'not needed')
        result = backup.create_backup(self.project, 'first')
        archive = Path(result['archive'])
        self.assertEqual(archive.parent, self.backup_root)
        self.assertTrue(archive.name.startswith('Linqo-v0.9.0+17-'))
        backup.verify(archive, self.project)
        with zipfile.ZipFile(archive) as zipped:
            self.assertEqual(zipped.read('project/app.dart'), b'uncommitted work')
            self.assertEqual(zipped.read('project/notes.md'), b'untracked notes')
            self.assertEqual(json.loads(zipped.read('project/.private/config.json')), {'fixture': True})
            self.assertFalse(any('.tools/' in name for name in zipped.namelist()))
            bundle = self.project / 'restore.bundle'
            bundle.write_bytes(zipped.read('git/repository.bundle'))
        restored = self.project / 'restored'
        subprocess.run(['git', 'clone', '--branch', 'main', str(bundle), str(restored)],
                       capture_output=True, check=True)
        self.assertEqual((restored / 'app.dart').read_text(), 'committed source')

    def test_fourth_verified_backup_keeps_exactly_the_three_newest(self):
        paths = []
        for n in range(4):
            (self.project / 'app.dart').write_text(f'version {n}', encoding='utf-8')
            paths.append(Path(backup.create_backup(self.project, f'step-{n}')['archive']))
        self.assertFalse(paths[0].exists())
        self.assertEqual(set(self.backup_root.glob('*.zip')), set(paths[1:]))
        for n, archive in enumerate(paths[1:], start=1):
            backup.verify(archive, self.project)
            with zipfile.ZipFile(archive) as zipped:
                self.assertEqual(zipped.read('project/app.dart'), f'version {n}'.encode())

    def test_corrupt_retained_archive_prevents_pruning(self):
        paths = [Path(backup.create_backup(self.project, f'step-{n}')['archive']) for n in range(3)]
        broken = paths[-1]
        with zipfile.ZipFile(broken) as zipped:
            entries = {name: zipped.read(name) for name in zipped.namelist()}
        entries['project/app.dart'] = b'corruption'
        with zipfile.ZipFile(broken, 'w') as zipped:
            for name, data in entries.items():
                zipped.writestr(name, data)
        with self.assertRaisesRegex(ValueError, 'checksum failed'):
            backup.create_backup(self.project, 'must-not-prune')
        self.assertTrue(all(path.exists() for path in paths))
        self.assertFalse((self.backup_root / '.backup.lock').exists())

    def test_existing_lock_does_not_get_removed_or_write_archive(self):
        root = self.backup_root
        root.mkdir()
        (root / '.backup.lock').write_text('existing writer')
        with self.assertRaises(FileExistsError):
            backup.create_backup(self.project, 'blocked')
        self.assertEqual((root / '.backup.lock').read_text(), 'existing writer')
        self.assertEqual(list(root.glob('*.zip')), [])


if __name__ == '__main__':
    unittest.main()
