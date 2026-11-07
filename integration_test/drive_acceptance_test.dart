import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:linqo/library/library_backup.dart';
import 'package:linqo/library/library_store.dart';
import 'package:linqo/library/models.dart';
import 'package:linqo/services/account_identity.dart';
import 'package:linqo/services/drive_backup.dart';

// Requires a configured build and an already signed-in, Drive-authorized account.
// Run only with a separate test application identity. Flutter drive defaults to
// uninstalling its target package on exit; the project wrapper now rejects that
// mode without --keep-app-running. Never target the user's installed library.
// Uses isolated databases and a unique Drive device marker. No main-library
// database, preferences, model files or non-test snapshot is changed.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Drive retention and portable attachment recovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Linqo Drive checks\nYour main library is preserved.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final identity = GoogleAccountIdentity();
      await identity.initialize();
      expect(
        identity.uid,
        isNotNull,
        reason: 'Sign into the normal app first.',
      );
      await identity.driveHeaders();
      final owner = identity.uid;
      final drive = DriveBackup(identity);
      final root = await (await getTemporaryDirectory()).createTemp(
        'linqo-drive-qa-',
      );
      final source = await LibraryStore.open(path: '${root.path}/source.db');
      final target = await LibraryStore.open(path: '${root.path}/target.db');
      final device = 'qa-${LibraryBackup.newKey()}';
      final cleanup = http.Client();
      final report = <String, Object?>{
        'synthetic_library': true,
        'qa_device_marker': device,
      };
      binding.reportData = report;
      bool allowed() => identity.uid == owner;
      try {
        final attachments = await Directory('${root.path}/files').create();
        final random = Random(731);
        final bytes = List.generate(128 * 1024, (_) => random.nextInt(256));
        await File('${attachments.path}/123.bin').writeAsBytes(bytes);
        final collection = await source.saveCollection('[QA] Cookbook', 0);
        final recipe = await source.save(
          SaveDraft(
            title: '[QA] Tomato pasta',
            kind: SaveKind.recipe,
            body:
                'Serves 2. Ingredients: 2 tomatoes. Steps: Chop the tomatoes.',
            notes: 'Synthetic private note',
            collectionIds: [collection],
          ),
        );
        await source.favorite(recipe, true);
        await source.save(
          const SaveDraft(
            title: '[QA] Attachment',
            kind: SaveKind.file,
            fileName: 'fixture.bin',
            attachment: '123.bin',
          ),
        );
        await target.setPreference('theme', 'dark');
        final archive = await LibraryBackup(
          source,
          attachments,
        ).export(await root.createTemp('export-'));
        expect(await drive.list(device: device), isEmpty);
        final timer = Stopwatch()..start();
        for (var n = 1; n <= 4; n++) {
          await drive.upload(archive, device, allowed);
          final snapshots = await drive.list(device: device);
          expect(snapshots.length, min(n, 3));
          report['verified_uploads'] = n;
          debugPrint('LINQO_DRIVE_QA_UPLOAD_$n');
          // Distinct timestamps make provider ordering unambiguous.
          if (n < 4) await Future<void>.delayed(const Duration(seconds: 1));
        }
        report['four_uploads_ms'] = timer.elapsedMilliseconds;
        report['three_snapshot_retention'] = true;
        final snapshot = (await drive.list(device: device)).first;
        final downloaded = await drive.download(
          snapshot,
          await root.createTemp('download-'),
          allowed: allowed,
        );
        expect(
          await sha256.bind(downloaded.openRead()).first,
          await sha256.bind(archive.openRead()).first,
        );
        final restoredFiles = Directory('${root.path}/restored-files');
        final backup = LibraryBackup(target, restoredFiles);
        expect(
          await backup.import(downloaded, await root.createTemp('import-')),
          (added: 2, skipped: 0),
        );
        expect(
          await backup.import(downloaded, await root.createTemp('duplicate-')),
          (added: 0, skipped: 2),
        );
        expect(await target.count(), 2);
        final item = (await target.query(query: 'Tomato')).single;
        expect(item.notes, 'Synthetic private note');
        expect(item.favorite, true);
        expect(item.collectionNames, ['[QA] Cookbook']);
        final attachment = (await target.query(query: 'Attachment')).single;
        expect(
          await File(
            '${restoredFiles.path}/${attachment.attachment}',
          ).readAsBytes(),
          bytes,
        );
        expect(await target.preference('theme'), 'dark');
        report['portable_restore_attachment_notes_favourite_collection'] = true;
        report['duplicate_restore_preserved_settings'] = true;
        report['archive_bytes'] = await archive.length();
        final invalid = await File(
          '${root.path}/invalid.zip',
        ).writeAsString('Not a Linqo ZIP');
        await drive.upload(invalid, '$device-corrupt', allowed);
        final bad = (await drive.list(device: '$device-corrupt')).single;
        final rejected = await drive.download(
          bad,
          await root.createTemp('invalid-'),
        );
        await expectLater(
          backup.import(rejected, await root.createTemp('reject-')),
          throwsA(anything),
        );
        expect(await target.count(), 2);
        report['invalid_remote_archive_kept_library'] = true;
      } finally {
        // Query and delete only the unique QA markers from this test run.
        var removed = 0;
        try {
          for (final marker in [device, '$device-corrupt']) {
            for (final snapshot in await drive.list(device: marker)) {
              final response = await cleanup
                  .delete(
                    Uri.https(
                      'www.googleapis.com',
                      '/drive/v3/files/${snapshot.id}',
                    ),
                    headers: await identity.driveHeaders(),
                  )
                  .timeout(const Duration(seconds: 30));
              expect(response.statusCode, 204);
              removed++;
            }
            expect(await drive.list(device: marker), isEmpty);
          }
          report['test_snapshots_removed'] = removed;
        } finally {
          cleanup.close();
          drive.close();
          await source.close();
          await target.close();
          await root.delete(recursive: true);
        }
      }
      debugPrint('LINQO_DRIVE_QA_PASSED');
    });
  }, timeout: const Timeout(Duration(minutes: 12)));
}
