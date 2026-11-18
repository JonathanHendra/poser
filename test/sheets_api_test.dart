import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_umkm/src/features/cloud/data/sheets_api.dart';

void main() {
  final bytes = Uint8List.fromList(ascii.encode('RIFF1234WEBPdata'));
  test(
    'photos upload actual WebP bytes and references, not binary Sheets cells',
    () async {
      final client = MockClient((request) async {
        if (request.method == 'GET') return http.Response('{"files":[]}', 200);
        if (request.method == 'POST') {
          expect(request.url.queryParameters['uploadType'], 'resumable');
          expect(jsonDecode(request.body)['mimeType'], 'image/webp');
          expect(jsonDecode(request.body)['name'], 'pos_event.webp');
          return http.Response(
            '',
            200,
            headers: {
              'location':
                  'https://www.googleapis.com/upload/drive/v3/files?upload_id=test',
            },
          );
        }
        expect(request.method, 'PUT');
        expect(request.bodyBytes, bytes);
        expect(request.headers['Content-Type'], 'image/webp');
        return http.Response('{"id":"photo-file"}', 200);
      });
      try {
        expect(
          await SheetsApi(client).uploadPhoto('token', 'pos_event', bytes),
          'photo-file',
        );
      } finally {
        client.close();
      }
    },
  );
  test('a completed upload is reused but an incomplete file is not', () async {
    var posts = 0;
    var complete = false;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'files': [
              {
                'id': 'existing',
                'size': complete ? bytes.length.toString() : '0',
              },
            ],
          }),
          200,
        );
      }
      if (request.method == 'POST') {
        posts++;
        return http.Response(
          '',
          200,
          headers: {
            'location':
                'https://www.googleapis.com/upload/drive/v3/files?upload_id=test',
          },
        );
      }
      return http.Response('{"id":"new"}', 200);
    });
    final api = SheetsApi(client);
    try {
      expect(await api.uploadPhoto('token', 'pos_event', bytes), 'new');
      expect(posts, 1);
      complete = true;
      expect(await api.uploadPhoto('token', 'pos_event', bytes), 'existing');
      expect(posts, 1);
    } finally {
      client.close();
    }
  });
  test('duplicate database names are not silently selected', () async {
    final client = MockClient(
      (_) async => http.Response('{"files":[{"id":"one"},{"id":"two"}]}', 200),
    );
    try {
      await expectLater(
        SheetsApi(client).findOrCreate('token', 'device'),
        throwsA(isA<SheetsFailure>()),
      );
    } finally {
      client.close();
    }
  });
}
