import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:finmatrix_flutter/screens/micro_screen.dart';
import 'package:finmatrix_flutter/services/database_helper.dart';
import 'package:finmatrix_flutter/services/forecast_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MicroScreen with margin = 0 (real-device repro)', () {
    late Database db;
    late String ym;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      db = await DatabaseHelper.openForTesting();
      ym = DateTime.now().toIso8601String().substring(0, 7);

      await db.insert('users', {
        'user_id': 'default_user',
        'phone_or_email': 'd@finmatrix.local',
        'display_name': 'Default',
        'business_type': 'Thời trang',
        'subscription_tier': 'premium',
      });
      // gross_margin_pct = 0 -> previously produced Infinity break-even -> crash.
      await db.insert('business_profile', {
        'user_id': 'default_user',
        'effective_from': '2020-01-01',
        'gross_margin_pct': 0.0,
        'fixed_operating_cost': 15000000.0,
      });
      await db.insert('monthly_target', {
        'user_id': 'default_user',
        'year_month': ym,
        'target_revenue': 200000000.0,
      });
      await db.insert('user_channel_config', {
        'channel_config_id': 'def_tiktok',
        'user_id': 'default_user',
        'channel_key': 'tiktok_ads',
        'effective_from': '2020-01-01',
        'revenue_share_pct': 100.0,
        'user_aov': 500000.0,
        'user_ad_cost_ratio': 25.0,
        'is_active': 1,
      });
    });

    test('reverse funnel break-even stays finite when margin is 0', () async {
      final data = await ForecastService.instance
          .calculateReverseFunnel('default_user', ym, referenceDate: '$ym-15');
      final be = (data['break_even_orders'] as num).toDouble();
      expect(be.isFinite, isTrue);
    });

    testWidgets('builds without throwing', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(home: MicroScreen()));
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}

