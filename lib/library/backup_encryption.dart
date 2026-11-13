import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'library_backup.dart';

/// Authenticated, password-protected envelope around the portable ZIP format.
class BackupEncryption {
  static const _magic = 'LINQOBK1';
  static const _headerSize = 48;
  static const _chunkSize = 128 * 1024;
  static const _iterations = 600000;
  static const _maxPlain = LibraryBackup.maxBytes + LibraryBackup.maxManifest;
  static const maxBytes = _maxPlain + 128 * 1024;

  static Future<bool> isEncrypted(File file) async {
    final input = await file.open();
    try {
      return String.fromCharCodes(await input.read(8)) == _magic;
    } finally {
      await input.close();
    }
  }

  static Future<File> encrypt(File input, File output, String password) async {
    final path = await _worker(input.path, output.path, password, false);
    return File(path);
  }

  static Future<File> decrypt(File input, File output, String password) async {
    final path = await _worker(input.path, output.path, password, true);
    return File(path);
  }

  static Future<String> _worker(
    String input,
    String output,
    String password,
    bool decrypt,
  ) => Isolate.run(() => _transform(input, output, password, decrypt));

  static Future<String> _transform(
    String inputPath,
    String outputPath,
    String password,
    bool decrypt,
  ) async {
    if (inputPath == outputPath ||
        password.isEmpty ||
        utf8.encode(password).length > 1024 ||
        (!decrypt && password.length < 12)) {
      throw const FormatException(
        'Use a backup password of at least 12 characters.',
      );
    }
    final source = File(inputPath), destination = File(outputPath);
    if (await destination.exists()) {
      throw const FormatException('Backup output already exists.');
    }
    final size = await source.length();
    if (size < 1 || size > maxBytes) {
      throw const FormatException('Backup exceeds the supported size.');
    }
    final input = await source.open();
    RandomAccessFile? output;
    var complete = false;
    try {
      late Uint8List header;
      late int plainSize;
      if (decrypt) {
        header = await _read(input, _headerSize);
        final fields = ByteData.sublistView(header);
        plainSize = fields.getUint64(36);
        if (String.fromCharCodes(header.sublist(0, 8)) != _magic ||
            fields.getUint32(8) != _iterations ||
            fields.getUint32(44) != _chunkSize ||
            plainSize < 1 ||
            plainSize > _maxPlain ||
            size !=
                _headerSize +
                    plainSize +
                    16 * ((plainSize + _chunkSize - 1) ~/ _chunkSize)) {
          throw const FormatException(
            'This encrypted backup is damaged or unsupported.',
          );
        }
      } else {
        plainSize = size;
        if (plainSize > _maxPlain) {
          throw const FormatException('Backup exceeds the supported size.');
        }
        header = Uint8List(_headerSize)..setRange(0, 8, ascii.encode(_magic));
        final random = Random.secure();
        for (var i = 12; i < 36; i++) {
          header[i] = random.nextInt(256);
        }
        final fields = ByteData.sublistView(header);
        fields.setUint32(8, _iterations);
        fields.setUint64(36, plainSize);
        fields.setUint32(44, _chunkSize);
      }
      final key =
          await Pbkdf2(
            macAlgorithm: Hmac.sha256(),
            iterations: _iterations,
            bits: 256,
          ).deriveKey(
            secretKey: SecretKey(utf8.encode(password)),
            nonce: header.sublist(12, 28),
          );
      final cipher = AesGcm.with256bits();
      output = await destination.open(mode: FileMode.writeOnly);
      if (!decrypt) await output.writeFrom(header);
      var remaining = plainSize, index = 0;
      while (remaining > 0) {
        final length = min(remaining, _chunkSize);
        final nonce = Uint8List(12)..setRange(0, 8, header.sublist(28, 36));
        ByteData.sublistView(nonce).setUint32(8, index);
        final aad = Uint8List(_headerSize + 4)
          ..setRange(0, _headerSize, header);
        ByteData.sublistView(aad).setUint32(_headerSize, index);
        if (decrypt) {
          final bytes = await _read(input, length + 16);
          final clear = await cipher.decrypt(
            SecretBox(
              bytes.sublist(0, length),
              nonce: nonce,
              mac: Mac(bytes.sublist(length)),
            ),
            secretKey: key,
            aad: aad,
          );
          await output.writeFrom(clear);
        } else {
          final bytes = await _read(input, length);
          final box = await cipher.encrypt(
            bytes,
            secretKey: key,
            nonce: nonce,
            aad: aad,
          );
          await output.writeFrom(box.cipherText);
          await output.writeFrom(box.mac.bytes);
        }
        remaining -= length;
        index++;
      }
      if ((await input.read(1)).isNotEmpty) {
        throw const FormatException('Backup changed while processing.');
      }
      await output.flush();
      complete = true;
      return outputPath;
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Incorrect backup password or damaged backup. Your library has not changed.',
      );
    } finally {
      await input.close();
      await output?.close();
      if (!complete && await destination.exists()) await destination.delete();
    }
  }

  static Future<Uint8List> _read(RandomAccessFile input, int length) async {
    final bytes = Uint8List(length);
    var read = 0;
    while (read < length) {
      final count = await input.readInto(bytes, read, length);
      if (count == 0) {
        throw const FormatException(
          'Backup is incomplete. Your library has not changed.',
        );
      }
      read += count;
    }
    return bytes;
  }
}
