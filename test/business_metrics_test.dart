import 'package:flutter_test/flutter_test.dart';
import 'package:finmatrix_flutter/services/business_metrics_service.dart';
import 'package:finmatrix_flutter/services/database_helper.dart';
import 'package:finmatrix_flutter/services/database_seed_service.dart';

const _testUserId = 'default_user';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await DatabaseHelper.openForTesting();
    await DatabaseSeedService.ensureMvpData();
  });

  tearDown(() async {
    await DatabaseHelper.closeDatabase();
  });

  test('saveMetrics updates values and loadMetrics returns latest', () async {
    await BusinessMetricsService.instance.saveMetrics(
      aov: 650000,
      grossMarginPct: 55,
      fixedOperatingCost: 20000000,
    );

    final metrics = await BusinessMetricsService.instance.loadMetrics();

    expect(metrics.aov, 650000);
    expect(metrics.grossMarginPct, 55);
    expect(metrics.fixedOperatingCost, 20000000);
    expect(metrics.hasInputData, isTrue);
  });

  test('saveMetrics updates the newest same-day profile row when legacy duplicates exist', () async {
    final db = await DatabaseHelper.instance.database;
    final today = DateTime.now().toIso8601String().split('T')[0];

    await db.insert('business_profile', {
      'user_id': _testUserId,
      'effective_from': today,
      'gross_margin_pct': 30.0,
      'fixed_operating_cost': 9000000.0,
    });

    await db.insert('business_profile', {
      'user_id': _testUserId,
      'effective_from': today,
      'gross_margin_pct': 35.0,
      'fixed_operating_cost': 12000000.0,
    });

    await BusinessMetricsService.instance.saveMetrics(
      aov: 700000,
      grossMarginPct: 60,
      fixedOperatingCost: 22000000,
    );

    final metrics = await BusinessMetricsService.instance.loadMetrics();
    final latestProfile = await db.query(
      'business_profile',
      where: 'user_id = ? AND effective_from = ?',
      whereArgs: [_testUserId, today],
      orderBy: 'id DESC',
      limit: 1,
    );

    expect(metrics.fixedOperatingCost, 22000000);
    expect((latestProfile.first['fixed_operating_cost'] as num).toDouble(), 22000000);
  });

  test('saveMetrics overwrites same-day profile instead of duplicating', () async {
    await BusinessMetricsService.instance.saveMetrics(
      aov: 400000,
      grossMarginPct: 40,
      fixedOperatingCost: 10000000,
    );
    await BusinessMetricsService.instance.saveMetrics(
      aov: 750000,
      grossMarginPct: 60,
      fixedOperatingCost: 18000000,
    );

    final metrics = await BusinessMetricsService.instance.loadMetrics();

    expect(metrics.aov, 750000);
    expect(metrics.grossMarginPct, 60);
    expect(metrics.fixedOperatingCost, 18000000);
  });
}
