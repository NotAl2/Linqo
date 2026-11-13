import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:linqo/inference/model_store.dart';
import 'package:linqo/library/library_backup.dart';
import 'package:linqo/library/backup_encryption.dart';
import 'package:linqo/library/library_controller.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/theme.dart';
import 'package:linqo/ui/settings_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('settings and native backup round trip in isolated library', (
    tester,
  ) async {
    final path = '${await getDatabasesPath()}/linqo-backup-qa.db';
    await deleteDatabase(path);
    final store = await LibraryStore.open(path: path);
    final c = LibraryController(store);
    await c.initialize(restoreModel: false);
    c.lab.model = ImportedModel(
      path: 'not-loaded.gguf',
      name: 'English model',
      bytes: 396705472,
      sha256: c.download.expectedSha,
    );
    final cache = await getTemporaryDirectory();
    final work = await Directory(
      '${cache.path}/library-backups',
    ).create(recursive: true);
    final run = await work.createTemp('qa-');
    final attachments = await Directory('${run.path}/attachments').create();
    binding.reportData = {'synthetic_fixtures': true, 'model_loaded': false};
    try {
      for (final variant in [
        (Brightness.light, 1.0, 'light'),
        (Brightness.dark, 1.0, 'dark'),
        (Brightness.light, 2.0, 'large-text'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: linqoTheme(variant.$1),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(variant.$2)),
              child: SettingsScreen(key: UniqueKey(), controller: c),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (variant.$3 == 'light') await binding.convertFlutterSurfaceToImage();
        final scrollable = find.byType(Scrollable).first;
        for (final section in [
          ('Already installed', 'model'),
          ('Export saves', 'backup'),
          ('Why we made Linqo', 'story'),
        ]) {
          await tester.scrollUntilVisible(
            find.text(section.$1),
            200,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await binding.takeScreenshot('backup-${section.$2}-${variant.$3}');
        }
      }
      final collection = await store.saveCollection('Little keepsakes', 1);
      await File(
        '${attachments.path}/123.txt',
      ).writeAsString('A lovely little find.');
      final id = await store.save(
        SaveDraft(
          title: 'A keepsake',
          body: 'A quiet afternoon.',
          notes: 'For later',
          kind: SaveKind.file,
          fileName: 'keepsake.txt',
          attachment: '123.txt',
          collectionIds: [collection],
        ),
      );
      await store.favorite(id, true);
      final backup = await LibraryBackup(store, attachments).export(run);
      final timer = Stopwatch()..start();
      final encrypted = await BackupEncryption.encrypt(
        backup,
        File('${run.path}/protected.linqo'),
        'Linqo synthetic QA password',
      );
      binding.reportData!['encryption_ms'] = timer.elapsedMilliseconds;
      const driveTest = bool.fromEnvironment('LINQO_TEST_DRIVE_PROVIDER');
      final saving = const MethodChannel('dev.linqo/backup')
          .invokeMethod<String>('save', {
            'path': encrypted.path,
            'name': driveTest
                ? 'Linqo-QA-encrypted-Drive-roundtrip.linqo'
                : 'Linqo-QA-encrypted-backup.linqo',
            'encrypted': true,
          });
      debugPrint('LINQO_QA_EXPORT_PICKER');
      final savedUri = await saving;
      expect(savedUri, isNotNull);
      if (driveTest) {
        expect(
          Uri.parse(savedUri!).authority,
          'com.google.android.apps.docs.storage',
        );
        binding.reportData!['drive_export_provider_verified'] = true;
      }
      binding.reportData!['native_export'] = true;
      final picking = FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );
      debugPrint('LINQO_QA_IMPORT_PICKER');
      final picked = await picking;
      expect(picked?.files.single.path, isNotNull);
      final targetPath = '${run.path}/restored.db';
      final restored = await LibraryStore.open(path: targetPath);
      try {
        await restored.setPreference('theme', 'dark');
        final importedFile = File(picked!.files.single.path!);
        expect(await BackupEncryption.isEncrypted(importedFile), isTrue);
        await expectLater(
          BackupEncryption.decrypt(
            importedFile,
            File('${run.path}/wrong.zip'),
            'wrong QA password',
          ),
          throwsFormatException,
        );
        expect(await File('${run.path}/wrong.zip').exists(), isFalse);
        expect(await restored.query(), isEmpty);
        timer.reset();
        final unlocked = await BackupEncryption.decrypt(
          importedFile,
          File('${run.path}/unlocked.zip'),
          'Linqo synthetic QA password',
        );
        binding.reportData!['decryption_ms'] = timer.elapsedMilliseconds;
        final restoredFiles = Directory('${run.path}/restored-files');
        final result = await LibraryBackup(
          restored,
          restoredFiles,
        ).import(unlocked, await run.createTemp('import-'));
        expect(result.added, 1);
        expect(await restored.preference('theme'), 'dark');
        final duplicate = await LibraryBackup(
          restored,
          restoredFiles,
        ).import(unlocked, await run.createTemp('repeat-'));
        expect(duplicate.added, 0);
        expect(duplicate.skipped, 1);
        final item = (await restored.get((await restored.query()).single.id))!;
        expect(item.notes, 'For later');
        expect(item.favorite, isTrue);
        expect(item.collectionNames, ['Little keepsakes']);
        expect(
          await File('${restoredFiles.path}/${item.attachment}').readAsString(),
          'A lovely little find.',
        );
        binding.reportData!['native_import'] = true;
        binding.reportData!['restored_file_notes_favourite_membership'] = true;
        binding.reportData!['wrong_password_and_duplicate_import_safe'] = true;
      } finally {
        await restored.close();
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await store.close();
      await deleteDatabase(path);
      await run.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
