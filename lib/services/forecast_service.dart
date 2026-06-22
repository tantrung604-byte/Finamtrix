import 'database_helper.dart';

class ForecastService {
  static final ForecastService instance = ForecastService._init();
  ForecastService._init();

  /// Calculates the reverse funnel for a given user and target month.
  /// [yearMonth] is YYYY-MM (for target revenue)
  /// [referenceDate] is YYYY-MM-DD (for point-in-time configuration)
  Future<Map<String, dynamic>> calculateReverseFunnel(String userId, String yearMonth, {String? referenceDate}) async {
    final db = await DatabaseHelper.instance.database;
    final configDate = referenceDate ?? DateTime.now().toIso8601String().split('T')[0];

    // 1. Get target revenue
    final targetResult = await db.query(
      'monthly_target',
      where: 'user_id = ? AND year_month = ?',
      whereArgs: [userId, yearMonth],
    );
    if (targetResult.isEmpty) return {};
    final targetRevenue = (targetResult.first['target_revenue'] as num).toDouble();

    // 2. Get business profile (effective gross margin)
    final profile = await _getEffectiveProfile(userId, configDate);
    if (profile == null) return {};
    final grossMarginPct = (profile['gross_margin_pct'] as num).toDouble();
    final fixedCost = (profile['fixed_operating_cost'] as num ?? 0).toDouble();

    // 3. Get active channel configurations
    final channels = await _getEffectiveChannelConfigs(userId, configDate);
    
    // 4. Calculate metrics per channel
    List<Map<String, dynamic>> channelCalculations = [];
    double totalOrders = 0;
    double totalAdBudget = 0;

    for (var channel in channels) {
      final revShare = (channel['revenue_share_pct'] as num).toDouble();
      final aov = (channel['user_aov'] as num).toDouble();
      final adCostRatio = (channel['user_ad_cost_ratio'] as num ?? 0).toDouble();
      
      final channelTargetRevenue = targetRevenue * (revShare / 100);
      final orders = channelTargetRevenue / aov;
      
      double adBudget = 0;
      if (channel['custom_channel_type'] == 'paid_channel' || 
          (channel['channel_type'] == 'paid_channel' && channel['custom_channel_type'] == null)) {
        // Budget = Channel Target Revenue * adCostRatio
        adBudget = channelTargetRevenue * (adCostRatio / 100);
      }

      channelCalculations.add({
        'channel_key': channel['channel_key'],
        'label': channel['custom_label'] ?? channel['display_name'],
        'orders': orders,
        'ad_budget': adBudget,
      });

      totalOrders += orders;
      totalAdBudget += adBudget;
    }

    // 5. Calculate Break-even (Method B: Margin-based)
    // Orders to cover: Fixed Cost / (AOV * Gross Margin %)
    // Since we have multiple channels with different AOVs, we use weighted average AOV
    double averageAov = totalOrders > 0 ? targetRevenue / totalOrders : 0;
    double breakEvenOrders = averageAov > 0 
        ? (fixedCost + totalAdBudget) / (averageAov * (grossMarginPct / 100)) 
        : 0;

    return {
      'target_revenue': targetRevenue,
      'total_orders': totalOrders,
      'total_ad_budget': totalAdBudget,
      'break_even_orders': breakEvenOrders,
      'channels': channelCalculations,
      'gross_margin_pct': grossMarginPct,
    };
  }

  Future<Map<String, dynamic>?> _getEffectiveProfile(String userId, String date) async {
    final db = await DatabaseHelper.instance.database;
    final results = await db.query(
      'business_profile',
      where: 'user_id = ? AND effective_from <= ?',
      whereArgs: [userId, date],
      orderBy: 'effective_from DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> _getEffectiveChannelConfigs(String userId, String date) async {
    final db = await DatabaseHelper.instance.database;
    
    // This is a bit complex in SQL to get "latest effective config per channel_logical_id"
    // For MVP, we'll fetch all and filter in Dart for simplicity
    final results = await db.rawQuery('''
      SELECT c.*, s.display_name, s.channel_type
      FROM user_channel_config c
      JOIN sales_channel s ON c.channel_key = s.channel_key
      WHERE c.user_id = ? AND c.effective_from <= ? AND c.is_active = 1
      ORDER BY c.effective_from DESC
    ''', [userId, date]);

    // Group by channel_key (or logical_id if we had one) and take the first (latest)
    Map<String, Map<String, dynamic>> latestConfigs = {};
    for (var row in results) {
      final key = row['channel_key'] as String;
      final label = row['custom_label'] as String?;
      final uniqueKey = '$key-$label'; // Simplified grouping
      if (!latestConfigs.containsKey(uniqueKey)) {
        latestConfigs[uniqueKey] = row;
      }
    }

    return latestConfigs.values.toList();
  }
}
