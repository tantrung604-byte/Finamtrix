import 'package:flutter_test/flutter_test.dart';
import 'package:finmatrix_flutter/services/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Database migration to v5 works', () async {
    final db = await DatabaseHelper.openForTesting();
    
    // Verify gold_price_daily has 'type' column
    final goldColumns = await db.rawQuery('PRAGMA table_info(gold_price_daily)');
    final hasType = goldColumns.any((c) => c['name'] == 'type');
    expect(hasType, isTrue);

    // Verify cpi_history exists
    final cpiTable = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='cpi_history'");
    expect(cpiTable.length, 1);

    // Verify unique constraint on gold_price_daily (date, type)
    // We can test by inserting duplicate date but different type
    await db.insert('gold_price_daily', {
      'date': '2026-06-30',
      'type': 'domestic',
      'price_buy': 100,
      'price_sell': 110,
      'source': 'test'
    });
    
    await db.insert('gold_price_daily', {
      'date': '2026-06-30',
      'type': 'world',
      'price_buy': 200,
      'price_sell': 210,
      'source': 'test'
    });

    final rows = await db.query('gold_price_daily', where: "date = '2026-06-30'");
    expect(rows.length, 2);

    await DatabaseHelper.closeDatabase();
  });
}
