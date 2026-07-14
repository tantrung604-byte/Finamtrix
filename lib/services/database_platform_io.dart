import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> initDatabasePlatform() async {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

Future<void> initDatabasePlatformForTesting() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

Future<String> resolveDatabasePath(String fileName) async {
  return join(await getDatabasesPath(), fileName);
}
