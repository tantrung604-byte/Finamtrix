import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

const defaultUserId = 'default_user';

class BusinessMetrics {
  final double aov;
  final double grossMarginPct;
  final double fixedOperatingCost;
  final double targetRevenue;

  const BusinessMetrics({
    required this.aov,
    required this.grossMarginPct,
    required this.fixedOperatingCost,
    required this.targetRevenue,
  });

  bool get hasInputData => aov > 0 && grossMarginPct > 0;
}

class BusinessMetricsService {
  static final BusinessMetricsService instance = BusinessMetricsService._init();
  BusinessMetricsService._init();

  Future<BusinessMetrics> loadMetrics({
    String userId = defaultUserId,
    String? referenceDate,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final today = referenceDate ?? DateTime.now().toIso8601String().split('T')[0];
    final yearMonth = today.substring(0, 7);

    final profileRows = await db.rawQuery(
      '''
      SELECT gross_margin_pct, fixed_operating_cost
      FROM business_profile
      WHERE user_id = ? AND effective_from <= ?
      ORDER BY effective_from DESC, id DESC
      LIMIT 1
      ''',
      [userId, today],
    );

    final channelRows = await db.rawQuery(
      '''
      SELECT user_aov
      FROM user_channel_config
      WHERE user_id = ? AND effective_from <= ? AND is_active = 1
      ORDER BY effective_from DESC, rowid DESC
      LIMIT 1
      ''',
      [userId, today],
    );

    final targetRows = await db.query(
      'monthly_target',
      where: 'user_id = ? AND year_month = ?',
      whereArgs: [userId, yearMonth],
      limit: 1,
    );

    return BusinessMetrics(
      aov: channelRows.isNotEmpty ? (channelRows.first['user_aov'] as num).toDouble() : 0,
      grossMarginPct: profileRows.isNotEmpty ? (profileRows.first['gross_margin_pct'] as num).toDouble() : 0,
      fixedOperatingCost: profileRows.isNotEmpty
          ? ((profileRows.first['fixed_operating_cost'] as num?) ?? 0).toDouble()
          : 0,
      targetRevenue: targetRows.isNotEmpty ? (targetRows.first['target_revenue'] as num).toDouble() : 0,
    );
  }

  Future<void> saveMetrics({
    required double aov,
    required double grossMarginPct,
    required double fixedOperatingCost,
    String userId = defaultUserId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final today = DateTime.now().toIso8601String().split('T')[0];

    await db.transaction((txn) async {
      final existingProfile = await txn.query(
        'business_profile',
        where: 'user_id = ? AND effective_from = ?',
        whereArgs: [userId, today],
        // Keep the newest same-day row if legacy data has duplicates.
        orderBy: 'id DESC',
        limit: 1,
      );

      final profileData = {
        'user_id': userId,
        'effective_from': today,
        'gross_margin_pct': grossMarginPct,
        'fixed_operating_cost': fixedOperatingCost,
      };

      if (existingProfile.isNotEmpty) {
        await txn.update(
          'business_profile',
          profileData,
          where: 'id = ?',
          whereArgs: [existingProfile.first['id']],
        );
      } else {
        await txn.insert('business_profile', profileData);
      }

      final latestChannel = await txn.rawQuery(
        '''
        SELECT rowid AS row_id, channel_config_id
        FROM user_channel_config
        WHERE user_id = ? AND is_active = 1
        ORDER BY effective_from DESC, rowid DESC
        LIMIT 1
        ''',
        [userId],
      );

      if (latestChannel.isNotEmpty) {
        await txn.update(
          'user_channel_config',
          {
            'user_aov': aov,
            'effective_from': today,
          },
          where: 'channel_config_id = ?',
          whereArgs: [latestChannel.first['channel_config_id']],
        );
      } else {
        await txn.insert('user_channel_config', {
          'channel_config_id': 'default_config',
          'user_id': userId,
          'channel_key': 'tiktok_ads',
          'effective_from': today,
          'revenue_share_pct': 100.0,
          'user_aov': aov,
          'user_ad_cost_ratio': 25.0,
          'is_active': 1,
        });
      }
    });
  }
}
