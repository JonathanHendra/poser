import 'package:sqlite3/wasm.dart';

Future<CommonSqlite3> loadBackupEngine() =>
    WasmSqlite3.loadFromUrl(Uri.base.resolve('sqlite3.wasm'));
