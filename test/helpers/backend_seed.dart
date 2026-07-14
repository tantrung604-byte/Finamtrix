import 'package:sqflite/sqflite.dart';
import 'package:finmatrix_flutter/services/database_helper.dart';

const testUserId = 'test_user';

Future<void> seedTestUser(Database db, {String yearMonth = '2026-06'}) async {
  await db.insert('users', {
    'user_id': testUserId,
    'phone_or_email': 'test@finmatrix.local',
    'display_name': 'Test User',
    'business_type': 'Thời trang',
    'subscription_tier': 'premium',
  });

  await db.insert('business_profile', {
    'user_id': testUserId,
    'effective_from': '2020-01-01',
    'gross_margin_pct': 45.0,
    'fixed_operating_cost': 15000000.0,
  });

  await db.insert('monthly_target', {
    'user_id': testUserId,
    'year_month': yearMonth,
    'target_revenue': 200000000.0,
  });

  await db.insert('user_channel_config', {
    'channel_config_id': 'test_tiktok_config',
    'user_id': testUserId,
    'channel_key': 'tiktok_ads',
    'effective_from': '2020-01-01',
    'revenue_share_pct': 100.0,
    'user_aov': 500000.0,
    'user_ad_cost_ratio': 25.0,
    'is_active': 1,
  });
}

Future<void> seedGoldPrices(Database db, {int days = 40, double basePrice = 88.5}) async {
  for (int i = 0; i < days; i++) {
    final date = DateTime.now().subtract(Duration(days: days - i - 1)).toIso8601String().split('T')[0];
    await db.insert('gold_price_daily', {
      'date': date,
      'price_buy': basePrice + (i * 0.1),
      'price_sell': basePrice + (i * 0.1) + 1.0,
      'source': 'SJC',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}

Future<void> seedUnderperformingChannel(Database db, String yearMonth) async {
  await db.insert('channel_actual_performance', {
    'channel_config_id': 'test_tiktok_config',
    'record_date': '$yearMonth-01',
    'actual_orders': 5,
    'actual_ad_spend': 1000000.0,
    'period_covers_days': 30,
  });
}

Future<void> seedFomoAlertData(Database db) async {
  await db.insert('fomo_score_daily', {
    'date': DateTime.now().toIso8601String().split('T')[0],
    'asset_type': 'gold',
    'fomo_score': 85.0,
    'zone': 'extreme',
    'calculation_mode': 'zscore',
    'days_of_data': 40,
    'change_7d_pct': 3.5,
    'data_anomaly_flagged': 0,
  });

  await db.insert('capital_intent', {
    'user_id': testUserId,
    'asset_type': 'gold',
    'planned_action': 'planning_to_buy',
  });
}

Future<Database> openSeededTestDatabase({String yearMonth = '2026-06'}) async {
  final db = await DatabaseHelper.openForTesting();
  await seedTestUser(db, yearMonth: yearMonth);
  return db;
}
