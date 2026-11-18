import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_umkm/src/features/cloud/data/drive_backup_api.dart';

void main() {
  test(
    'creates SQLite directly in the folder through resumable upload',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          expect(request.url.queryParameters['uploadType'], 'resumable');
          final body = jsonDecode(request.body) as Map;
          expect(body['name'], 'POS_Database.sqlite');
          expect(body['parents'], ['folder']);
          expect(body['mimeType'], 'application/vnd.sqlite3');
          return http.Response(
            '',
            200,
            headers: {'location': 'https://www.googleapis.com/upload/session'},
          );
        }
        expect(request.method, 'PUT');
        expect(request.bodyBytes, bytes);
        return http.Response(
          '{"id":"backup","md5Checksum":"hash","version":"1"}',
          200,
        );
      });
      try {
        final backup = await DriveBackupApi(
          client,
        ).upload('token', 'folder', 'a', 9, bytes);
        expect(backup.id, 'backup');
        expect(backup.checksum, 'hash');
      } finally {
        client.close();
      }
    },
  );
  test(
    'preflight conflict prevents uploading over another device revision',
    () async {
      var uploads = 0;
      final client = MockClient((request) async {
        if (request.method != 'GET') uploads++;
        return http.Response(
          '{"id":"backup","md5Checksum":"new","version":"2"}',
          200,
        );
      });
      try {
        await expectLater(
          DriveBackupApi(client).upload(
            'token',
            'folder',
            'a',
            9,
            Uint8List(1),
            existing: const DriveBackup(
              id: 'backup',
              checksum: 'old',
              version: '1',
            ),
          ),
          throwsA(isA<BackupConflict>()),
        );
        expect(uploads, 0);
      } finally {
        client.close();
      }
    },
  );
  test('update uses conditional headers and preserves file identity', () async {
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
          '{"id":"backup","md5Checksum":"old","version":"1"}',
          200,
        );
      }
      expect(request.headers['If-Match'], 'etag-1');
      if (request.method == 'PATCH') {
        expect(request.url.path, '/upload/drive/v3/files/backup');
        expect(
          (jsonDecode(request.body) as Map).containsKey('parents'),
          isFalse,
        );
        return http.Response(
          '',
          200,
          headers: {'location': 'https://www.googleapis.com/upload/session'},
        );
      }
      return http.Response(
        '{"id":"backup","md5Checksum":"new","version":"2"}',
        200,
      );
    });
    try {
      final result = await DriveBackupApi(client).upload(
        'token',
        'folder',
        'a',
        9,
        Uint8List(1),
        existing: const DriveBackup(
          id: 'backup',
          checksum: 'old',
          version: '1',
          etag: 'etag-1',
        ),
      );
      expect(result.id, 'backup');
    } finally {
      client.close();
    }
  });
}
