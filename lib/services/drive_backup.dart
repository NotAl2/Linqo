import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../library/library_backup.dart';
import 'account_identity.dart';

class DriveSnapshot {
  DriveSnapshot(Map<String, dynamic> row)
    : id = row['id'] as String,
      name = row['name'] as String,
      created = row['createdTime'] as String,
      bytes = int.tryParse('${row['size']}') ?? 0;
  final String id, name, created;
  final int bytes;
}

class _Upload extends http.BaseRequest {
  _Upload(
    super.method,
    super.url,
    this.file,
    this.prefix,
    this.suffix,
    this.allowed,
  );
  final File file;
  final List<int> prefix, suffix;
  final bool Function() allowed;
  @override
  http.ByteStream finalize() {
    super.finalize();
    Stream<List<int>> bytes() async* {
      yield prefix;
      await for (final chunk in file.openRead()) {
        if (!allowed()) {
          throw StateError(
            'Backup paused while Linqo is busy. Try again when idle.',
          );
        }
        yield chunk;
      }
      yield suffix;
    }

    return http.ByteStream(bytes());
  }
}

class DriveBackup {
  DriveBackup(this.identity, {http.Client? client})
    : client = client ?? http.Client();
  final AccountIdentity identity;
  final http.Client client;
  static const fields = 'id,name,size,createdTime,md5Checksum,appProperties';
  Future<Map<String, dynamic>> _json(http.BaseRequest request) async {
    request.headers.addAll(await identity.driveHeaders());
    final response = await client
        .send(request)
        .timeout(request is _Upload ? const Duration(minutes: 10) : const Duration(seconds: 30));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('Drive response was too large.');
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(switch (response.statusCode) {
        401 || 403 =>
          'Drive access failed. Reconnect Drive or check storage and permissions.',
        429 => 'Drive is busy. Try again later.',
        _ => 'Drive request failed. Your local library is safe.',
      });
    }
    return bytes.isEmpty
        ? {}
        : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<List<DriveSnapshot>> list({String? device}) async {
    final found = <DriveSnapshot>[];
    String? page;
    do {
      final q =
          "trashed=false and appProperties has { key='format' and value='linqo-v1' }${device == null ? '' : " and appProperties has { key='device' and value='$device' }"}";
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': q,
        'orderBy': 'createdTime desc',
        'pageSize': '100',
        'fields': 'nextPageToken,files($fields)',
        'pageToken': ?page,
      });
      final value = await _json(http.Request('GET', uri));
      found.addAll(
        (value['files'] as List).map(
          (e) => DriveSnapshot(Map<String, dynamic>.from(e as Map)),
        ),
      );
      page = value['nextPageToken'] as String?;
    } while (page != null && found.length < 1000);
    return found;
  }

  Future<void> upload(File file, String device, bool Function() allowed) async {
    final length = await file.length();
    final checksum = (await md5.bind(file.openRead()).first).toString();
    final boundary = 'linqo-${LibraryBackup.newKey()}';
    final metadata = jsonEncode({
      'name': 'Linqo-${DateTime.now().toUtc().toIso8601String()}.zip',
      'parents': ['appDataFolder'],
      'appProperties': {'format': 'linqo-v1', 'device': device},
    });
    final prefix = utf8.encode(
      '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n--$boundary\r\nContent-Type: application/zip\r\n\r\n',
    );
    final suffix = utf8.encode('\r\n--$boundary--\r\n');
    final request =
        _Upload(
            'POST',
            Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
              'uploadType': 'multipart',
              'fields': fields,
            }),
            file,
            prefix,
            suffix,
            allowed,
          )
          ..headers['Content-Type'] = 'multipart/related; boundary=$boundary'
          ..contentLength = prefix.length + length + suffix.length;
    final uploaded = await _json(request);
    final id = uploaded['id'] as String?;
    if (id == null ||
        uploaded['md5Checksum'] != checksum ||
        '${uploaded['size']}' != '$length') {
      if (id != null) {
        await _json(
          http.Request(
            'DELETE',
            Uri.https('www.googleapis.com', '/drive/v3/files/$id'),
          ),
        );
      }
      throw StateError(
        'Drive could not verify the new backup. Previous backups were kept.',
      );
    }
    // Only prune this installation's snapshots after server checksum verification.
    final snapshots = await list(device: device);
    for (final old in snapshots.skip(3)) {
      if (!allowed()) break;
      await _json(
        http.Request(
          'DELETE',
          Uri.https('www.googleapis.com', '/drive/v3/files/${old.id}'),
        ),
      );
    }
  }

  Future<File> download(DriveSnapshot snapshot, Directory work) async {
    const maximum = LibraryBackup.maxBytes + LibraryBackup.maxManifest;
    if (snapshot.bytes > maximum) {
      throw const FormatException(
        'This backup exceeds the supported archive size.',
      );
    }
    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files/${snapshot.id}',
      {'alt': 'media'},
    );
    final response = await client
        .send(
          http.Request('GET', uri)
            ..headers.addAll(await identity.driveHeaders()),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError(
        'Backup could not be downloaded. Check Drive permission.',
      );
    }
    final file = File('${work.path}/restore.zip'),
        sink = File('${work.path}/restore.zip').openWrite();
    var count = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        count += chunk.length;
        if (count > maximum) {
          throw const FormatException(
            'Backup exceeds the supported archive size.',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    final metadata = await _json(
      http.Request(
        'GET',
        Uri.https('www.googleapis.com', '/drive/v3/files/${snapshot.id}', {
          'fields': 'md5Checksum,size',
        }),
      ),
    );
    if ((await md5.bind(file.openRead()).first).toString() !=
            metadata['md5Checksum'] ||
        count != snapshot.bytes) {
      throw const FormatException(
        'Backup checksum failed. The library has not changed.',
      );
    }
    return file;
  }

  void close() => client.close();
}
