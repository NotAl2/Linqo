import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../library/library_backup.dart';
import '../library/backup_encryption.dart';
import '../library/library_controller.dart';
import 'components.dart';
import 'backup_password_dialog.dart';

class BackupSection extends StatefulWidget {
  const BackupSection({super.key, required this.controller});
  final LibraryController controller;
  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  bool busy = false;
  String activity = '';
  Future<void> run(bool importing) async {
    if (busy) return;
    setState(() {
      busy = true;
      activity = importing ? 'Importing your saves…' : 'Preparing your backup…';
    });
    Directory? work;
    try {
      final temp = await getTemporaryDirectory();
      work = await Directory(
        '${temp.path}/library-backups',
      ).create(recursive: true);
      work = await work.createTemp('work-');
      final attachments =
          widget.controller.attachmentDirectory ??
          Directory(
            '${(await getApplicationSupportDirectory()).path}/attachments',
          );
      final backup = LibraryBackup(widget.controller.store, attachments);
      if (importing) {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.any,
          withData: false,
        );
        if (picked == null || !mounted) return;
        final path = picked.files.single.path;
        if (path == null) {
          throw const FormatException(
            'Choose a backup from a local file provider.',
          );
        }
        var file = File(path);
        if (await BackupEncryption.isEncrypted(file)) {
          if (!mounted) return;
          final password = await backupPassword(context, creating: false);
          if (password == null || !mounted) return;
          setState(() => activity = 'Unlocking and checking your backup…');
          file = await BackupEncryption.decrypt(
            file,
            File('${work.path}/unlocked.zip'),
            password,
          );
        }
        final result = await backup.import(file, work);
        await widget.controller.refresh();
        if (mounted) {
          message(
            context,
            '${result.added} saves imported · ${result.skipped} already in your library.',
          );
        }
      } else {
        if (!mounted) return;
        final password = await backupPassword(context, creating: true);
        if (password == null || !mounted) return;
        setState(() => activity = 'Protecting your backup…');
        final zip = await backup.export(work);
        final file = await BackupEncryption.encrypt(
          zip,
          File('${work.path}/protected.linqo'),
          password,
        );
        await zip.delete();
        final name =
            'Linqo-backup-${DateTime.now().toIso8601String().substring(0, 10)}.linqo';
        String? saved;
        if (Platform.isAndroid) {
          // Stream to the chosen document provider without passing ZIP bytes
          // through the Flutter platform channel or UI isolate.
          saved = await const MethodChannel('dev.linqo/backup')
              .invokeMethod<String>('save', {
                'path': file.path,
                'name': name,
                'encrypted': true,
              });
        } else {
          saved = await FilePicker.platform.saveFile(
            fileName: name,
            type: FileType.custom,
            allowedExtensions: ['linqo'],
            bytes: Platform.isIOS ? await file.readAsBytes() : null,
          );
          if (saved != null && !Platform.isIOS) await file.copy(saved);
        }
        if (saved != null && mounted) {
          message(context, 'Backup exported. Keep it somewhere safe.');
        }
      }
    } catch (e) {
      if (mounted) message(context, 'Backup could not finish. $e');
    } finally {
      if (work != null && await work.exists()) {
        try {
          await work.delete(recursive: true);
        } on FileSystemException {
          /* The OS can reclaim this private cache. */
        }
      }
      if (mounted) {
        setState(() {
          busy = false;
          activity = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keep your finds safe',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'Export a password-protected backup of saves, notes, collections, favourites and file copies. Choose Drive in the Android Files picker to keep it in your Google Drive. Import from Files to restore it.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep your backup password: Linqo cannot recover it. Models, credentials and cached previews are excluded. Legacy unencrypted ZIP backups can still be imported. Restore merges your saves and preserves current settings.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => run(false),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Export saves'),
              ),
              TextButton.icon(
                onPressed: busy ? null : () => run(true),
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Import saves'),
              ),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(activity)),
          ],
        ],
      ),
    ),
  );
}
