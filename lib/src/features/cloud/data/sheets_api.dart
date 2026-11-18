import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class SheetsFailure implements Exception {
  const SheetsFailure(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class SheetsApi {
  SheetsApi(this.client);
  final http.Client client;

  Future<Map<String, dynamic>> request(
    String method,
    Uri uri,
    String token, [
    Object? body,
  ]) async {
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 30)),
    ).timeout(const Duration(seconds: 30));
    validate(response);
    return response.body.isEmpty
        ? {}
        : jsonDecode(response.body) as Map<String, dynamic>;
  }

  void validate(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = switch (response.statusCode) {
        401 => 'Izin Google kedaluwarsa. Hubungkan kembali Google Drive.',
        403 =>
          'Akses Google ditolak. Hubungkan kembali akun dan periksa izin Drive.',
        404 =>
          'Cadangan tidak ditemukan. Periksa apakah file dihapus dari Drive.',
        429 => 'Batas Google API tercapai. Sinkronisasi akan dicoba kembali.',
        _ => 'Google Drive belum dapat diakses (${response.statusCode}).',
      };
      throw SheetsFailure(message, response.statusCode);
    }
  }

  Future<String> uploadPhoto(
    String token,
    String name,
    Uint8List bytes, {
    String? folderId,
  }) async {
    final webp =
        bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
    final filename = '$name.${webp ? 'webp' : 'bin'}';
    final found = await request(
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "trashed = false and name = '$filename'",
        'fields': 'files(id,size)',
      }),
      token,
    );
    final files = found['files'] as List;
    final complete = files.where(
      (file) => (file as Map)['size'] == bytes.length.toString(),
    );
    if (complete.isNotEmpty) {
      final id = (complete.first as Map)['id'] as String;
      if (folderId != null) await moveToFolder(token, id, folderId);
      return id;
    }
    final mime = webp ? 'image/webp' : 'application/octet-stream';
    final started = await client
        .post(
          Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
            'uploadType': 'resumable',
          }),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'X-Upload-Content-Type': mime,
          },
          body: jsonEncode({
            'name': filename,
            'mimeType': mime,
            if (folderId != null) 'parents': [folderId],
          }),
        )
        .timeout(const Duration(seconds: 30));
    validate(started);
    final location = started.headers['location'];
    if (location == null) {
      throw const SheetsFailure(
        'Google Drive tidak memberikan alamat unggah foto.',
      );
    }
    final uri = Uri.parse(location);
    if (uri.scheme != 'https' || uri.host != 'www.googleapis.com') {
      throw const SheetsFailure('Alamat unggah Google Drive tidak valid.');
    }
    final uploaded = await client
        .put(
          uri,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': mime},
          body: bytes,
        )
        .timeout(const Duration(seconds: 60));
    validate(uploaded);
    return (jsonDecode(uploaded.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<String> findOrCreate(
    String token,
    String tab, {
    String? folderId,
  }) async {
    var existing = await findExisting(token, folderId: folderId);
    if (existing == null && folderId != null) {
      existing = await findExisting(token);
    }
    if (existing != null) {
      if (folderId != null) await moveToFolder(token, existing, folderId);
      return existing;
    }
    if (folderId != null) {
      final created = await request(
        'POST',
        Uri.https('www.googleapis.com', '/drive/v3/files', {'fields': 'id'}),
        token,
        {
          'name': 'POS_Database_Jangan_Dihapus',
          'mimeType': 'application/vnd.google-apps.spreadsheet',
          'parents': [folderId],
        },
      );
      return created['id'] as String;
    }
    final created = await request(
      'POST',
      Uri.https('sheets.googleapis.com', '/v4/spreadsheets'),
      token,
      {
        'properties': {'title': 'POS_Database_Jangan_Dihapus'},
        'sheets': [
          {
            'properties': {'title': tab},
          },
        ],
      },
    );
    return created['spreadsheetId'] as String;
  }

  Future<String> ensureBackupFolder(String token) async {
    const name = 'POSPRO_Backup_Jangan_Dihapus';
    final found = await request(
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q':
            "trashed = false and mimeType = 'application/vnd.google-apps.folder' and name = '$name'",
        'fields': 'files(id)',
        'pageSize': '100',
        'orderBy': 'createdTime',
      }),
      token,
    );
    final files = found['files'] as List;
    if (files.isNotEmpty) return (files.first as Map)['id'] as String;
    final created = await request(
      'POST',
      Uri.https('www.googleapis.com', '/drive/v3/files'),
      token,
      {
        'name': name,
        'mimeType': 'application/vnd.google-apps.folder',
        'description':
            'Cadangan database dan foto POSPRO. Jangan hapus file di dalam folder ini.',
      },
    );
    return created['id'] as String;
  }

  Future<void> moveToFolder(String token, String file, String folder) async {
    final metadata = await request(
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files/$file', {
        'fields': 'parents,trashed',
      }),
      token,
    );
    if (metadata['trashed'] == true) {
      throw const SheetsFailure(
        'File database berada di sampah Google Drive.',
        404,
      );
    }
    final parents = (metadata['parents'] as List? ?? []).cast<String>();
    if (parents.contains(folder)) return;
    await request(
      'PATCH',
      Uri.https('www.googleapis.com', '/drive/v3/files/$file', {
        'addParents': folder,
        if (parents.isNotEmpty) 'removeParents': parents.join(','),
        'fields': 'id,parents',
      }),
      token,
      <String, Object?>{},
    );
  }

  Future<String?> findExisting(String token, {String? folderId}) async {
    final found = await request(
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q':
            "trashed = false and mimeType = 'application/vnd.google-apps.spreadsheet' and name = 'POS_Database_Jangan_Dihapus'${folderId == null ? '' : " and '$folderId' in parents"}",
        'fields': 'files(id)',
        'pageSize': '100',
      }),
      token,
    );
    final files = found['files'] as List;
    if (files.length > 1) {
      throw const SheetsFailure(
        'Ada lebih dari satu database POS di Drive. Periksa file sebelum sinkronisasi.',
      );
    }
    if (files.isNotEmpty) return (files.single as Map)['id'] as String;
    return null;
  }

  Future<void> deleteDatabase(String token, String id) async {
    final photos = <String>{};
    for (final tab in await tabs(token, id)) {
      if (!tab.startsWith('device_')) continue;
      for (final event in await events(token, id, tab)) {
        if (event.entity != 'product_photos' || event.payload.isEmpty) continue;
        final record = jsonDecode(event.payload) as Map<String, dynamic>;
        final photo = record['image_drive_file_id'];
        if (photo is String && photo.isNotEmpty) photos.add(photo);
      }
    }
    for (final file in [...photos, id]) {
      try {
        await request(
          'DELETE',
          Uri.https('www.googleapis.com', '/drive/v3/files/$file'),
          token,
        );
      } on SheetsFailure catch (e) {
        if (e.status != 404) rethrow;
      }
    }
  }

  Future<void> prepare(
    String token,
    String id,
    String tab,
    int rows,
    int columns,
  ) async {
    final metadata = await request(
      'GET',
      Uri.https('sheets.googleapis.com', '/v4/spreadsheets/$id', {
        'fields': 'sheets.properties',
      }),
      token,
    );
    final sheets = metadata['sheets'] as List;
    final matching = sheets.where(
      (s) => (s as Map)['properties']['title'] == tab,
    );
    Map<String, Object> change;
    if (matching.isEmpty) {
      change = {
        'addSheet': {
          'properties': {
            'title': tab,
            'gridProperties': {'rowCount': rows, 'columnCount': columns},
          },
        },
      };
    } else {
      final properties = (matching.single as Map)['properties'] as Map;
      final grid = properties['gridProperties'] as Map;
      change = {
        'updateSheetProperties': {
          'properties': {
            'sheetId': properties['sheetId'],
            'gridProperties': {
              'rowCount': rows > (grid['rowCount'] as int)
                  ? rows
                  : grid['rowCount'],
              'columnCount': columns > (grid['columnCount'] as int)
                  ? columns
                  : grid['columnCount'],
            },
          },
          'fields': 'gridProperties(rowCount,columnCount)',
        },
      };
    }
    await request(
      'POST',
      Uri.https('sheets.googleapis.com', '/v4/spreadsheets/$id:batchUpdate'),
      token,
      {
        'requests': [change],
      },
    );
    await write(token, id, "'$tab'!A1", [
      'event_id',
      'entity',
      'operation',
      'created_at',
      'record_json_1',
    ]);
  }

  Future<List<String>> tabs(String token, String id) async {
    final metadata = await request(
      'GET',
      Uri.https('sheets.googleapis.com', '/v4/spreadsheets/$id', {
        'fields': 'sheets.properties.title',
      }),
      token,
    );
    final sheets = metadata['sheets'] as List;
    return [
      for (final sheet in sheets)
        ((sheet as Map)['properties'] as Map)['title'] as String,
    ];
  }

  Future<List<SheetEvent>> events(String token, String id, String tab) async {
    final escaped = tab.replaceAll("'", "''");
    final response = await request(
      'GET',
      Uri.https(
        'sheets.googleapis.com',
        '/v4/spreadsheets/$id/values/\'$escaped\'!A2:ZZ',
        {'valueRenderOption': 'UNFORMATTED_VALUE'},
      ),
      token,
    );
    final values = response['values'] as List? ?? const [];
    final events = <SheetEvent>[];
    for (final row in values) {
      if (row is! List || row.length < 5) continue;
      final id = int.tryParse(row[0].toString());
      final createdAt = int.tryParse(row[3].toString());
      if (id == null || createdAt == null) continue;
      events.add(
        SheetEvent(
          tab: tab,
          id: id,
          entity: row[1].toString(),
          operation: row[2].toString(),
          createdAt: createdAt,
          payload: row.skip(4).map((cell) => cell.toString()).join(),
        ),
      );
    }
    events.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      if (byTime != 0) return byTime;
      final byTab = a.tab.compareTo(b.tab);
      if (byTab != 0) return byTab;
      return a.id.compareTo(b.id);
    });
    return events;
  }

  Future<void> write(
    String token,
    String id,
    String range,
    List<String> values,
  ) async {
    final uri = Uri.https(
      'sheets.googleapis.com',
      '/v4/spreadsheets/$id/values/$range',
      {'valueInputOption': 'RAW'},
    );
    await request('PUT', uri, token, {
      'range': range,
      'majorDimension': 'ROWS',
      'values': [values],
    });
  }
}

class SheetEvent {
  const SheetEvent({
    required this.tab,
    required this.id,
    required this.entity,
    required this.operation,
    required this.createdAt,
    required this.payload,
  });
  final String tab, entity, operation, payload;
  final int id, createdAt;
}
