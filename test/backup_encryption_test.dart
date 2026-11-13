import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/library/backup_encryption.dart';

void main() {
  test(
    'encrypted backups authenticate chunks, reject wrong passwords and preserve source files',
    () async {
      final root = await Directory.systemTemp.createTemp('linqo-encryption-');
      try {
        final clear = List<int>.generate(270000, (i) => i % 251);
        final input = await File('${root.path}/source.zip').writeAsBytes(clear);
        final encrypted = await BackupEncryption.encrypt(
          input,
          File('${root.path}/one.linqo'),
          'a long private password',
        );
        expect(await BackupEncryption.isEncrypted(input), false);
        expect(await BackupEncryption.isEncrypted(encrypted), true);
        final restored = await BackupEncryption.decrypt(
          encrypted,
          File('${root.path}/restored.zip'),
          'a long private password',
        );
        expect(await restored.readAsBytes(), clear);
        final second = await BackupEncryption.encrypt(
          input,
          File('${root.path}/two.linqo'),
          'a long private password',
        );
        expect(
          await second.readAsBytes(),
          isNot(await encrypted.readAsBytes()),
        );
        final wrong = File('${root.path}/wrong.zip');
        await expectLater(
          BackupEncryption.decrypt(encrypted, wrong, 'wrong password'),
          throwsFormatException,
        );
        expect(await wrong.exists(), false);
        final bytes = await encrypted.readAsBytes();
        bytes[bytes.length - 1] ^= 1;
        final damaged = await File(
          '${root.path}/damaged.linqo',
        ).writeAsBytes(bytes);
        final partial = File('${root.path}/partial.zip');
        await expectLater(
          BackupEncryption.decrypt(damaged, partial, 'a long private password'),
          throwsFormatException,
        );
        expect(await partial.exists(), false);
        final truncated = await File(
          '${root.path}/truncated.linqo',
        ).writeAsBytes(bytes.sublist(0, bytes.length - 1));
        await expectLater(
          BackupEncryption.decrypt(
            truncated,
            partial,
            'a long private password',
          ),
          throwsFormatException,
        );
        final header = Uint8List.fromList(bytes);
        ByteData.sublistView(header).setUint32(8, 0xffffffff);
        final expensive = await File(
          '${root.path}/bad-header.linqo',
        ).writeAsBytes(header);
        await expectLater(
          BackupEncryption.decrypt(
            expensive,
            partial,
            'a long private password',
          ),
          throwsFormatException,
        );
        await expectLater(
          BackupEncryption.decrypt(
            encrypted,
            restored,
            'a long private password',
          ),
          throwsFormatException,
        );
        expect(await input.readAsBytes(), clear);
        expect(await restored.readAsBytes(), clear);
        await expectLater(
          BackupEncryption.encrypt(
            input,
            File('${root.path}/weak.linqo'),
            'short',
          ),
          throwsFormatException,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
