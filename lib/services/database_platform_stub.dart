import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

Future<void> initDatabasePlatform() async {}

Future<void> initDatabasePlatformForTesting() async {
  throw UnsupportedError('Backend tests must run on Windows/Linux VM.');
}

Future<String> resolveDatabasePath(String fileName) async {
  return join(await getDatabasesPath(), fileName);
}
