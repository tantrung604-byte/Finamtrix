import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<void> initDatabasePlatform() async {
  databaseFactory = databaseFactoryFfiWeb;
}

Future<void> initDatabasePlatformForTesting() async {
  throw UnsupportedError('Backend tests must run on Windows/Linux VM.');
}

Future<String> resolveDatabasePath(String fileName) async {
  return fileName;
}
