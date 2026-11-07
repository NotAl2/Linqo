import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linqo/services/account_identity.dart';
import 'package:linqo/services/drive_backup.dart';

class _Identity implements AccountIdentity {
  @override
  String? get uid => 'user';
  @override
  String? get email => 'user@example.com';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
  @override
  Future<String> idToken() async => 'firebase-token';
  @override
  Future<Map<String, String>> driveHeaders({bool interactive = false}) async =>
      {'Authorization': 'Bearer drive-token'};
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

void main() {
  late Directory work;
  setUp(() async {
    work = await Directory.systemTemp.createTemp('linqo-drive-test-');
  });
  tearDown(() async {
    await work.delete(recursive: true);
  });
  test(
    'network interruption during download removes partial file without importing',
    () async {
      final drive = DriveBackup(
        _Identity(),
        client: _StreamingClient((request) async {
          Stream<List<int>> broken() async* {
            yield [1, 2];
            throw const SocketException('Synthetic connection loss');
          }

          return http.StreamedResponse(broken(), 200);
        }),
      );
      try {
        await expectLater(
          drive.download(
            DriveSnapshot({
              'id': 'one',
              'name': 'Backup',
              'size': '4',
              'createdTime': '2026-11-07T00:00:00Z',
            }),
            work,
          ),
          throwsA(isA<SocketException>()),
        );
        expect(await File('${work.path}/restore.zip').exists(), false);
      } finally {
        drive.close();
      }
    },
  );
  test(
    'backgrounding during a restore stops the stream before metadata lookup',
    () async {
      var allowed = true;
      var requests = 0;
      var cancelled = false;
      final drive = DriveBackup(
        _Identity(),
        client: _StreamingClient((request) async {
          requests++;
          Stream<List<int>> bytes() async* {
            try {
              yield [1, 2];
              allowed = false;
              yield [3, 4];
            } finally {
              cancelled = true;
            }
          }

          return http.StreamedResponse(bytes(), 200);
        }),
      );
      try {
        await expectLater(
          drive.download(
            DriveSnapshot({
              'id': 'one',
              'name': 'Backup',
              'size': '4',
              'createdTime': '2026-11-07T00:00:00Z',
            }),
            work,
            allowed: () => allowed,
          ),
          throwsStateError,
        );
        expect(cancelled, true);
        expect(requests, 1);
        expect(await File('${work.path}/restore.zip').exists(), false);
      } finally {
        drive.close();
      }
    },
  );
  test(
    'upload streams archive, verifies remote checksum and only then prunes device snapshots',
    () async {
      final file = await File(
        '${work.path}/archive.zip',
      ).writeAsBytes([1, 2, 3, 4]);
      var verified = false;
      final deleted = <String>[];
      final drive = DriveBackup(
        _Identity(),
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer drive-token');
          if (request.method == 'POST') {
            expect(
              request.headers['Content-Type'],
              contains('multipart/related'),
            );
            expect(request.bodyBytes, containsAllInOrder([1, 2, 3, 4]));
            verified = true;
            return http.Response(
              jsonEncode({
                'id': 'new',
                'md5Checksum': md5.convert([1, 2, 3, 4]).toString(),
                'size': '4',
              }),
              200,
            );
          }
          if (request.method == 'GET') {
            expect(verified, true);
            expect(request.url.queryParameters['q'], contains("key='device'"));
            return http.Response(
              jsonEncode({
                'files': [
                  for (final id in ['new', 'b', 'c', 'old'])
                    {
                      'id': id,
                      'name': 'Backup',
                      'size': '4',
                      'createdTime': '2026-11-07T00:00:00Z',
                    },
                ],
              }),
              200,
            );
          }
          deleted.add(request.url.pathSegments.last);
          return http.Response('', 204);
        }),
      );
      await drive.upload(file, 'a' * 64, () => true);
      expect(deleted, ['old']);
      drive.close();
    },
  );
  test(
    'failed checksum removes only new invalid upload and preserves previous backups',
    () async {
      final file = await File('${work.path}/archive.zip').writeAsBytes([1, 2]);
      final methods = <String>[];
      final drive = DriveBackup(
        _Identity(),
        client: MockClient((request) async {
          methods.add(request.method);
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({'id': 'bad', 'md5Checksum': 'wrong', 'size': '2'}),
              200,
            );
          }
          expect(request.url.pathSegments.last, 'bad');
          return http.Response('', 204);
        }),
      );
      await expectLater(
        drive.upload(file, 'a' * 64, () => true),
        throwsStateError,
      );
      expect(methods, ['POST', 'DELETE']);
      drive.close();
    },
  );
  test('cancelled upload never prunes existing snapshots', () async {
    final file = await File('${work.path}/archive.zip').writeAsBytes([1, 2]);
    var requests = 0;
    final drive = DriveBackup(
      _Identity(),
      client: MockClient((request) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      drive.upload(file, 'a' * 64, () => false),
      throwsStateError,
    );
    expect(requests, 0);
    drive.close();
  });
  test(
    'corrupted downloaded backup is rejected before it reaches library import',
    () async {
      final snapshot = DriveSnapshot({
        'id': 'one',
        'name': 'Backup',
        'size': '3',
        'createdTime': '2026-11-07T00:00:00Z',
      });
      final drive = DriveBackup(
        _Identity(),
        client: MockClient(
          (request) async => request.url.queryParameters['alt'] == 'media'
              ? http.Response.bytes([1, 2, 3], 200)
              : http.Response(
                  jsonEncode({'md5Checksum': 'wrong', 'size': '3'}),
                  200,
                ),
        ),
      );
      await expectLater(drive.download(snapshot, work), throwsFormatException);
      expect(await File('${work.path}/restore.zip').exists(), false);
      drive.close();
    },
  );
  test(
    'full Drive storage gives an actionable error without pruning',
    () async {
      final file = await File('${work.path}/archive.zip').writeAsBytes([1]);
      final methods = <String>[];
      final drive = DriveBackup(
        _Identity(),
        client: MockClient((request) async {
          methods.add(request.method);
          return http.Response(
            jsonEncode({
              'error': {
                'errors': [
                  {'reason': 'storageQuotaExceeded'},
                ],
              },
            }),
            403,
          );
        }),
      );
      try {
        await expectLater(
          drive.upload(file, 'a' * 64, () => true),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('storage is full'),
            ),
          ),
        );
        expect(methods, ['POST']);
      } finally {
        drive.close();
      }
    },
  );
  test(
    'revoked access and rate limits never delete existing snapshots',
    () async {
      for (final status in [401, 403, 429, 503]) {
        final methods = <String>[];
        final file = await File('${work.path}/archive.zip').writeAsBytes([1]);
        final drive = DriveBackup(
          _Identity(),
          client: MockClient((request) async {
            methods.add(request.method);
            return http.Response('{}', status);
          }),
        );
        try {
          await expectLater(
            drive.upload(file, 'a' * 64, () => true),
            throwsStateError,
          );
          expect(methods, ['POST']);
        } finally {
          drive.close();
        }
      }
    },
  );
  test('pause after successful upload prevents listing and pruning', () async {
    var allowed = true;
    final methods = <String>[];
    final file = await File('${work.path}/archive.zip').writeAsBytes([1]);
    final drive = DriveBackup(
      _Identity(),
      client: MockClient((request) async {
        methods.add(request.method);
        allowed = false;
        return http.Response(
          jsonEncode({
            'id': 'new',
            'md5Checksum': md5.convert([1]).toString(),
            'size': '1',
          }),
          200,
        );
      }),
    );
    try {
      await expectLater(
        drive.upload(file, 'a' * 64, () => allowed),
        throwsStateError,
      );
      expect(methods, ['POST']);
    } finally {
      drive.close();
    }
  });
  test(
    'cancelled restore makes no request and creates no partial archive',
    () async {
      var requests = 0;
      final drive = DriveBackup(
        _Identity(),
        client: MockClient((_) async {
          requests++;
          return http.Response.bytes([1], 200);
        }),
      );
      try {
        await expectLater(
          drive.download(
            DriveSnapshot({
              'id': 'one',
              'name': 'Backup',
              'size': '1',
              'createdTime': '2026-11-07T00:00:00Z',
            }),
            work,
            allowed: () => false,
          ),
          throwsStateError,
        );
        expect(requests, 0);
        expect(await File('${work.path}/restore.zip').exists(), false);
      } finally {
        drive.close();
      }
    },
  );
  test(
    'changed remote size rejects download and removes temporary archive',
    () async {
      final drive = DriveBackup(
        _Identity(),
        client: MockClient(
          (request) async => request.url.queryParameters['alt'] == 'media'
              ? http.Response.bytes([1, 2, 3], 200)
              : http.Response(
                  jsonEncode({
                    'md5Checksum': md5.convert([1, 2, 3]).toString(),
                    'size': '4',
                  }),
                  200,
                ),
        ),
      );
      try {
        await expectLater(
          drive.download(
            DriveSnapshot({
              'id': 'one',
              'name': 'Backup',
              'size': '3',
              'createdTime': '2026-11-07T00:00:00Z',
            }),
            work,
          ),
          throwsFormatException,
        );
        expect(await File('${work.path}/restore.zip').exists(), false);
      } finally {
        drive.close();
      }
    },
  );
  test(
    'snapshot listing paginates within app data and the requested device',
    () async {
      var requests = 0;
      final drive = DriveBackup(
        _Identity(),
        client: MockClient((request) async {
          requests++;
          expect(request.url.queryParameters['spaces'], 'appDataFolder');
          expect(
            request.url.queryParameters['q'],
            contains("value='device-a'"),
          );
          final page = request.url.queryParameters['pageToken'];
          return http.Response(
            jsonEncode({
              if (page == null) 'nextPageToken': 'next',
              'files': [
                {
                  'id': page == null ? 'first' : 'second',
                  'name': 'Backup',
                  'size': '3',
                  'createdTime': '2026-11-07T00:00:00Z',
                },
              ],
            }),
            200,
          );
        }),
      );
      try {
        expect((await drive.list(device: 'device-a')).map((e) => e.id), [
          'first',
          'second',
        ]);
        expect(requests, 2);
      } finally {
        drive.close();
      }
    },
  );
}
