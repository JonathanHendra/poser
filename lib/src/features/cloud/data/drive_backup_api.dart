import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'sheets_api.dart';

class BackupConflict extends SheetsFailure {
  const BackupConflict()
    : super(
        'Data Google Drive berubah di perangkat lain. Pilih data yang akan digunakan sebelum menyinkronkan.',
        409,
      );
}

class DriveBackup {
  const DriveBackup({
    required this.id,
    required this.checksum,
    required this.version,
    this.etag,
  });
  final String id, checksum, version;
  final String? etag;
  factory DriveBackup.fromJson(Map<String, dynamic> json, [String? etag]) =>
      DriveBackup(
        id: json['id'] as String,
        checksum: json['md5Checksum'] as String? ?? '',
        version: json['version']?.toString() ?? '',
        etag: etag,
      );
}

class DriveBackupApi extends SheetsApi {
  DriveBackupApi(super.client);
  static const filename = 'POS_Database.sqlite';

  Future<DriveBackup?> findBackup(String token, String folder) async {
    final found = await request(
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "trashed = false and name = '$filename' and '$folder' in parents",
        'fields': 'files(id,md5Checksum,version)',
        'pageSize': '100',
      }),
      token,
    );
    final files = found['files'] as List;
    if (files.length > 1) {
      throw const SheetsFailure(
        'Ada beberapa cadangan SQLite dengan nama yang sama. Periksa folder backup sebelum sinkronisasi.',
      );
    }
    if (files.isEmpty) return null;
    return metadata(token, (files.single as Map)['id'] as String);
  }

  Future<DriveBackup> metadata(String token, String id) async {
    final response = await client
        .get(
          Uri.https('www.googleapis.com', '/drive/v3/files/$id', {
            'fields': 'id,md5Checksum,version,trashed',
          }),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));
    validate(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['trashed'] == true) {
      throw const SheetsFailure(
        'Cadangan SQLite berada di sampah Google Drive.',
        404,
      );
    }
    return DriveBackup.fromJson(json, response.headers['etag']);
  }

  Future<Uint8List> download(String token, String id) async {
    final response = await client
        .get(
          Uri.https('www.googleapis.com', '/drive/v3/files/$id', {
            'alt': 'media',
          }),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(minutes: 2));
    validate(response);
    return response.bodyBytes;
  }

  Future<DriveBackup> upload(
    String token,
    String folder,
    String owner,
    int schema,
    Uint8List bytes, {
    DriveBackup? existing,
  }) async {
    if (existing != null) {
      final latest = await metadata(token, existing.id);
      if (latest.version != existing.version ||
          latest.checksum != existing.checksum) {
        throw const BackupConflict();
      }
    }
    final start =
        http.Request(
            existing == null ? 'POST' : 'PATCH',
            Uri.https(
              'www.googleapis.com',
              '/upload/drive/v3/files${existing == null ? '' : '/${existing.id}'}',
              {'uploadType': 'resumable', 'fields': 'id,md5Checksum,version'},
            ),
          )
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'X-Upload-Content-Type': 'application/vnd.sqlite3',
            'X-Upload-Content-Length': bytes.length.toString(),
            if (existing?.etag != null) 'If-Match': existing!.etag!,
          })
          ..body = jsonEncode({
            'name': filename,
            'mimeType': 'application/vnd.sqlite3',
            if (existing == null) 'parents': [folder],
            'appProperties': {
              'owner_id': owner,
              'schema_version': schema.toString(),
              'format': 'pospro-sqlite-v1',
            },
          });
    final started = await http.Response.fromStream(
      await client.send(start).timeout(const Duration(seconds: 30)),
    );
    if (started.statusCode == 412) throw const BackupConflict();
    validate(started);
    final location = started.headers['location'];
    if (location == null) {
      throw const SheetsFailure(
        'Google Drive tidak memberikan alamat unggah database.',
      );
    }
    final uri = Uri.parse(location);
    if (uri.scheme != 'https' || uri.host != 'www.googleapis.com') {
      throw const SheetsFailure('Alamat unggah database tidak valid.');
    }
    final response = await client
        .put(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/vnd.sqlite3',
            if (existing?.etag != null) 'If-Match': existing!.etag!,
          },
          body: bytes,
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode == 412) throw const BackupConflict();
    validate(response);
    return DriveBackup.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      response.headers['etag'],
    );
  }

  Future<void> deleteBackup(String token, String id) async {
    try {
      await request(
        'DELETE',
        Uri.https('www.googleapis.com', '/drive/v3/files/$id'),
        token,
      );
    } on SheetsFailure catch (e) {
      if (e.status != 404) rethrow;
    }
  }
}
