import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:finmatrix_flutter/services/database_helper.dart';
import 'package:finmatrix_flutter/services/fomo_service.dart';
import 'package:finmatrix_flutter/services/forecast_service.dart';
import 'package:finmatrix_flutter/services/ai_cmo_engine.dart';
import 'helpers/backend_seed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final yearMonth = DateTime.now().toIso8601String().substring(0, 7);

  setUp(() async {
    await DatabaseHelper.openForTesting();
  });

  tearDown(() async {
    await DatabaseHelper.closeDatabase();
  });

  group('Database schema', () {
    test('creates all tables and seeds default sales channels', () async {
      final db = await DatabaseHelper.instance.database;

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      final tableNames = tables.map((r) => r['name'] as String).toList();

      expect(tableNames, containsAll([
        'users',
        'gold_price_daily',
        'fomo_score_daily',
        'business_profile',
        'monthly_target',
        'sales_channel',
        'user_channel_config',
        'channel_actual_performance',
        'cmo_suggestion_log',
        'capital_intent',
        'tiktok_shop_connection',
      ]));

      final channelCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM sales_channel'),
      );
      expect(channelCount, 5);
    });
  });

  group('FomoService', () {
    test('calculates and saves FOMO score from price history', () async {
      final db = await DatabaseHelper.instance.database;
      await seedGoldPrices(db, days: 40);

      await FomoService.instance.calculateAndSaveFomoScore('gold');

      final result = await db.query(
        'fomo_score_daily',
        where: 'asset_type = ?',
        whereArgs: ['gold'],
        orderBy: 'date DESC',
        limit: 1,
      );

      expect(result, isNotEmpty);
      final row = result.first;
      expect(row['fomo_score'], isNotNull);
      expect((row['fomo_score'] as num).toDouble(), inInclusiveRange(0, 100));
      expect(row['calculation_mode'], 'zscore');
      expect(row['zone'], isNotNull);
      expect(row['days_of_data'], 40);
    });

    test('uses simple mode when fewer than 30 days of data', () async {
      final db = await DatabaseHelper.instance.database;
      await seedGoldPrices(db, days: 14);

      await FomoService.instance.calculateAndSaveFomoScore('gold');

      final result = await db.query(
        'fomo_score_daily',
        where: 'asset_type = ?',
        whereArgs: ['gold'],
        limit: 1,
      );

      expect(result.first['calculation_mode'], 'simple');
    });
  });

  group('ForecastService', () {
    test('calculates reverse funnel with expected business metrics', () async {
      final db = await DatabaseHelper.instance.database;
      await seedTestUser(db, yearMonth: yearMonth);
      final today = DateTime.now().toIso8601String().split('T')[0];

      final forecast = await ForecastService.instance.calculateReverseFunnel(
        testUserId,
        yearMonth,
        referenceDate: today,
      );

      expect(forecast, isNotEmpty);
      expect(forecast['target_revenue'], 200000000.0);
      expect(forecast['total_orders'], 400.0); // 200M / 500k AOV
      expect(forecast['total_ad_budget'], 50000000.0); // 25% of revenue
      expect(forecast['gross_margin_pct'], 45.0);

      final channels = forecast['channels'] as List;
      expect(channels, hasLength(1));
      expect(channels.first['channel_key'], 'tiktok_ads');
      expect(channels.first['orders'], 400.0);
    });

    test('deduplicates historical rows by channel_key and keeps the latest one', () async {
      final db = await DatabaseHelper.instance.database;
      final today = DateTime.now().toIso8601String().split('T')[0];

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
        'channel_config_id': 'tiktok_old',
        'user_id': testUserId,
        'channel_key': 'tiktok_ads',
        'custom_label': 'TikTok Cũ',
        'effective_from': '2020-01-01',
        'revenue_share_pct': 100.0,
        'user_aov': 400000.0,
        'user_ad_cost_ratio': 25.0,
        'is_active': 1,
      });
      await db.insert('user_channel_config', {
        'channel_config_id': 'tiktok_new',
        'user_id': testUserId,
        'channel_key': 'tiktok_ads',
        'custom_label': 'TikTok Mới',
        'effective_from': today,
        'revenue_share_pct': 100.0,
        'user_aov': 700000.0,
        'user_ad_cost_ratio': 25.0,
        'is_active': 1,
      });

      final forecast = await ForecastService.instance.calculateReverseFunnel(
        testUserId,
        yearMonth,
        referenceDate: today,
      );

      final channels = forecast['channels'] as List;
      expect(channels, hasLength(1));
      expect(channels.first['channel_key'], 'tiktok_ads');
      expect(channels.first['orders'], closeTo(285.7142857, 0.0001));
      expect(forecast['total_ad_budget'], 50000000.0);
    });

    test('returns empty map when user has no monthly target', () async {
      final today = DateTime.now().toIso8601String().split('T')[0];

      final forecast = await ForecastService.instance.calculateReverseFunnel(
        'missing_user',
        yearMonth,
        referenceDate: today,
      );

      expect(forecast, isEmpty);
    });
  });

  group('AiCmoEngine', () {
    test('R1 fires when channel underperforms expected pace', () async {
      final db = await DatabaseHelper.instance.database;
      await seedTestUser(db, yearMonth: yearMonth);
      await seedUnderperformingChannel(db, yearMonth);

      final suggestions = await AiCmoEngine.instance.runRuleEngine(testUserId);

      expect(
        suggestions.any((s) => s['rule_id'] == 'R1_underperform'),
        isTrue,
        reason: 'Expected R1 underperform rule with low actual orders',
      );

      final r1 = suggestions.firstWhere((s) => s['rule_id'] == 'R1_underperform');
      expect(r1['data']['channel'], 'TikTok Ads');
      expect(r1['content'], isNotEmpty);

      final logCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM cmo_suggestion_log WHERE user_id = ?', [testUserId]),
      );
      expect(logCount, greaterThan(0));
    });

    test('R4 fires when FOMO is high and user plans to buy gold', () async {
      final db = await DatabaseHelper.instance.database;
      await seedTestUser(db, yearMonth: yearMonth);
      await seedFomoAlertData(db);

      final suggestions = await AiCmoEngine.instance.runRuleEngine(testUserId);

      expect(
        suggestions.any((s) => s['rule_id'] == 'R4_fomo_alert'),
        isTrue,
        reason: 'Expected R4 FOMO alert with score > 80 and buy intent',
      );

      final r4 = suggestions.firstWhere((s) => s['rule_id'] == 'R4_fomo_alert');
      expect(r4['data']['asset'], 'Vàng');
      expect(r4['priority'], 'extreme');
    });
  });
}
