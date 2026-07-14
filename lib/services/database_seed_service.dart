import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'fomo_service.dart';

const defaultUserId = 'default_user';

/// Idempotent MVP seed — safe to call from main and across tabs (Web).
class DatabaseSeedService {
  static Future<void>? _seedFuture;

  static Future<void> ensureMvpData() {
    return _seedFuture ??= _seed();
  }

  static Future<void> _seed() async {
    final db = await DatabaseHelper.instance.database;
    final today = DateTime.now().toIso8601String().split('T')[0];
    final yearMonth = today.substring(0, 7);

    await db.insert(
      'users',
      {
        'user_id': defaultUserId,
        'phone_or_email': 'user@example.com',
        'display_name': 'Tantr',
        'subscription_tier': 'premium',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await _ensureGoldPrices(db);

    await db.insert(
      'business_profile',
      {
        'user_id': defaultUserId,
        'effective_from': '2020-01-01',
        'gross_margin_pct': 45.0,
        'fixed_operating_cost': 15000000.0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await db.insert(
      'monthly_target',
      {
        'user_id': defaultUserId,
        'year_month': yearMonth,
        'target_revenue': 200000000.0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await _ensureChannels(db);
  }

  /// Paid-channel mix seeded for the budget allocation (shares sum to 100%).
  static const List<Map<String, dynamic>> _seedChannels = [
    {'id': 'default_config', 'key': 'tiktok_ads', 'share': 40.0, 'aov': 500000.0, 'adRatio': 25.0},
    {'id': 'default_facebook', 'key': 'facebook_ads', 'share': 35.0, 'aov': 450000.0, 'adRatio': 22.0},
    {'id': 'default_google', 'key': 'google_ads', 'share': 25.0, 'aov': 600000.0, 'adRatio': 18.0},
  ];

  static Future<void> _ensureChannels(Database db) async {
    for (final c in _seedChannels) {
      await db.insert(
        'user_channel_config',
        {
          'channel_config_id': c['id'],
          'user_id': defaultUserId,
          'channel_key': c['key'],
          'effective_from': '2020-01-01',
          'revenue_share_pct': c['share'],
          'user_aov': c['aov'],
          'user_ad_cost_ratio': c['adRatio'],
          'is_active': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    // One-time rebalance for legacy installs where TikTok was the only channel
    // at 100%. Only fires when the share is still exactly 100%, so it never
    // fights a user's later adjustments.
    await db.update(
      'user_channel_config',
      {'revenue_share_pct': 40.0},
      where: "channel_config_id = 'default_config' AND user_id = ? AND revenue_share_pct = 100.0",
      whereArgs: [defaultUserId],
    );
  }

  static Future<void> _ensureGoldPrices(Database db) async {
    final priceCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM gold_price_daily'),
    );
    if (priceCount != null && priceCount > 0) return;

    const base = 88.5;
    for (int i = 0; i < 40; i++) {
      final date = DateTime.now().subtract(Duration(days: 40 - i)).toIso8601String().split('T')[0];
      await db.insert(
        'gold_price_daily',
        {
          'date': date,
          'price_buy': base + (i * 0.1),
          'price_sell': base + (i * 0.1) + 1.0,
          'source': 'SJC',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await FomoService.instance.calculateAndSaveFomoScore('gold');
  }
}
