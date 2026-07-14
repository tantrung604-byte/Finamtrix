import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:finmatrix_flutter/services/database_helper.dart';
import 'package:finmatrix_flutter/services/forecast_service.dart';

/// Verifies the contribution-margin break-even model:
///   breakEven = fixedCost / (grossProfit/order - adCost/order)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  const ym = '2026-06';

  Future<void> seed({required double marginPct}) async {
    await db.delete('business_profile');
    await db.insert('users', {
      'user_id': 'default_user',
      'phone_or_email': 'd@finmatrix.local',
      'display_name': 'Default',
      'subscription_tier': 'premium',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('business_profile', {
      'user_id': 'default_user',
      'effective_from': '2020-01-01',
      'gross_margin_pct': marginPct,
      'fixed_operating_cost': 15000000.0,
    });
    await db.insert('monthly_target', {
      'user_id': 'default_user',
      'year_month': ym,
      'target_revenue': 200000000.0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('user_channel_config', {
      'channel_config_id': 'def_tiktok',
      'user_id': 'default_user',
      'channel_key': 'tiktok_ads',
      'effective_from': '2020-01-01',
      'revenue_share_pct': 100.0,
      'user_aov': 500000.0,
      'user_ad_cost_ratio': 25.0,
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  setUp(() async {
    db = await DatabaseHelper.openForTesting();
  });

  test('healthy margin -> correct contribution-margin break-even (150 orders)', () async {
    // AOV 500k, margin 45%, ad ratio 25%, fixed 15M, target 200M -> 400 orders.
    // grossProfit/order = 225k; adCost/order = 125k; contribution = 100k.
    // breakEven = 15M / 100k = 150 orders.
    await seed(marginPct: 45.0);
    final data = await ForecastService.instance
        .calculateReverseFunnel('default_user', ym, referenceDate: '$ym-15');

    expect(data['break_even_possible'], isTrue);
    expect((data['contribution_per_order'] as num).toDouble(), closeTo(100000, 1));
    expect((data['break_even_orders'] as num).toDouble().round(), 150);
  });

  test('ad cost exceeds gross margin -> cannot break even', () async {
    // margin 5% -> grossProfit/order = 25k, adCost/order = 125k -> negative contribution.
    await seed(marginPct: 5.0);
    final data = await ForecastService.instance
        .calculateReverseFunnel('default_user', ym, referenceDate: '$ym-15');

    expect(data['break_even_possible'], isFalse);
    expect((data['contribution_per_order'] as num).toDouble(), lessThan(0));
    // Sentinel 0 (not a misleading positive number) and always finite.
    expect((data['break_even_orders'] as num).toDouble(), 0);
  });
}

