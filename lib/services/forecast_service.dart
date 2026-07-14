import 'database_helper.dart';

/// Assumptions for one stress-test scenario.
/// [demandFactor] scales achievable orders (conversion up/down).
/// [aovFactor] scales average order value (price pressure).
/// [adCostFactor] scales required ad budget (channel efficiency).
/// [monthlyGrowth] is the month-over-month revenue growth used for the 6-month projection.
class ScenarioAssumption {
  final String key;
  final String name;
  final String sub;
  final double demandFactor;
  final double aovFactor;
  final double adCostFactor;
  final double monthlyGrowth;

  const ScenarioAssumption({
    required this.key,
    required this.name,
    required this.sub,
    required this.demandFactor,
    required this.aovFactor,
    required this.adCostFactor,
    required this.monthlyGrowth,
  });
}

/// Computed result for one stress-test scenario.
class ScenarioResult {
  final String key;
  final String name;
  final String sub;
  final double revenue;
  final double orders;
  final double netProfit;
  final double breakEvenGap; // orders above (+) / below (-) break-even
  final double deltaPct; // net-profit change vs base case
  final List<double> projection; // 6-month revenue path (raw VND)

  const ScenarioResult({
    required this.key,
    required this.name,
    required this.sub,
    required this.revenue,
    required this.orders,
    required this.netProfit,
    required this.breakEvenGap,
    required this.deltaPct,
    required this.projection,
  });
}

class ForecastService {
  static final ForecastService instance = ForecastService._init();
  ForecastService._init();

  /// Default stress-test assumptions (MVP). Tune these to change scenario behaviour.
  static const List<ScenarioAssumption> defaultScenarios = [
    ScenarioAssumption(
      key: 'optimistic',
      name: 'Tươi sáng',
      sub: 'Lạc quan',
      demandFactor: 1.35,
      aovFactor: 1.08,
      adCostFactor: 0.90,
      monthlyGrowth: 0.08,
    ),
    ScenarioAssumption(
      key: 'realistic',
      name: 'Thực tế',
      sub: 'Khả thi',
      demandFactor: 1.0,
      aovFactor: 1.0,
      adCostFactor: 1.0,
      monthlyGrowth: 0.03,
    ),
    ScenarioAssumption(
      key: 'pessimistic',
      name: 'Thủng phễu',
      sub: 'Rủi ro',
      demandFactor: 0.65,
      aovFactor: 0.95,
      adCostFactor: 1.20,
      monthlyGrowth: -0.05,
    ),
  ];

  /// Runs a real stress-test by applying each scenario's assumptions to the
  /// user's actual reverse-funnel base case.
  ///
  /// [baseForecast] is the result of [calculateReverseFunnel].
  /// [grossMarginPct] / [fixedCost] come from the business profile.
  /// [demandMultiplier] lets an external factor (e.g. macro purchasing power)
  /// dampen or boost demand across all scenarios.
  List<ScenarioResult> calculateScenarios({
    required Map<String, dynamic> baseForecast,
    required double grossMarginPct,
    required double fixedCost,
    double demandMultiplier = 1.0,
    List<ScenarioAssumption> assumptions = defaultScenarios,
  }) {
    final double targetRevenue = (baseForecast['target_revenue'] as num?)?.toDouble() ?? 0;
    final double baseOrders = (baseForecast['total_orders'] as num?)?.toDouble() ?? 0;
    final double baseAdBudget = (baseForecast['total_ad_budget'] as num?)?.toDouble() ?? 0;
    final double breakEvenOrders = (baseForecast['break_even_orders'] as num?)?.toDouble() ?? 0;
    final double marginRatio = grossMarginPct / 100.0;
    final double aov = baseOrders > 0 ? targetRevenue / baseOrders : 0;

    if (targetRevenue <= 0 || baseOrders <= 0 || aov <= 0) {
      return const [];
    }

    // Base-case net profit (no scenario adjustment) for delta comparison.
    final double baseNetProfit = (targetRevenue * marginRatio) - fixedCost - baseAdBudget;

    return assumptions.map((a) {
      final double orders = baseOrders * a.demandFactor * demandMultiplier;
      final double scenarioAov = aov * a.aovFactor;
      final double revenue = orders * scenarioAov;
      final double adBudget = baseAdBudget * a.adCostFactor;
      final double netProfit = (revenue * marginRatio) - fixedCost - adBudget;
      final double deltaPct =
          baseNetProfit != 0 ? ((netProfit - baseNetProfit) / baseNetProfit.abs()) * 100 : 0;

      // 6-month projection compounding from current target revenue.
      final List<double> projection = List.generate(6, (i) {
        return revenue * _pow(1 + a.monthlyGrowth, i);
      });

      return ScenarioResult(
        key: a.key,
        name: a.name,
        sub: a.sub,
        revenue: revenue,
        orders: orders,
        netProfit: netProfit,
        breakEvenGap: orders - breakEvenOrders,
        deltaPct: deltaPct,
        projection: projection,
      );
    }).toList();
  }

  double _pow(double base, int exp) {
    double result = 1.0;
    for (int i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }

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

    // 5. Calculate Break-even using the contribution-margin model.
    //
    // Each order contributes: gross profit (AOV * margin%) MINUS its share of the
    // variable ad spend. Ads scale with sales volume, so they are a *variable*
    // cost, not a fixed one. Only `fixedOperatingCost` is truly fixed.
    //
    //   contributionPerOrder = (targetRevenue * margin% - totalAdBudget) / totalOrders
    //   breakEvenOrders      = fixedCost / contributionPerOrder
    //
    // If contributionPerOrder <= 0 the business loses money on every order and can
    // NEVER break even — we flag this instead of returning a misleading number.
    final double averageAov = totalOrders > 0 ? targetRevenue / totalOrders : 0;
    final double grossProfitAtTarget = targetRevenue * (grossMarginPct / 100);
    final double contributionAtTarget = grossProfitAtTarget - totalAdBudget;
    final double contributionPerOrder =
        totalOrders > 0 ? contributionAtTarget / totalOrders : 0;

    final bool breakEvenPossible = contributionPerOrder > 0;
    final double breakEvenOrders =
        breakEvenPossible ? fixedCost / contributionPerOrder : 0;
    final double breakEvenRevenue = breakEvenOrders * averageAov;

    // Calculate total theoretical orders if AOV was uniform across all revenue
    final double totalRequiredOrders = targetRevenue / (averageAov > 0 ? averageAov : 1.0);
    final double organicOrders = (totalRequiredOrders - totalOrders).clamp(0.0, totalRequiredOrders);

    return {
      'target_revenue': targetRevenue,
      'total_orders': totalOrders, // These are ad-driven/channel-configured orders
      'total_required_orders': totalRequiredOrders, // Total orders to reach revenue
      'organic_orders': organicOrders, // Non-ad driven orders
      'total_ad_budget': totalAdBudget,
      'break_even_orders': breakEvenOrders,
      'break_even_possible': breakEvenPossible,
      'break_even_revenue': breakEvenRevenue,
      'contribution_per_order': contributionPerOrder,
      'average_aov': averageAov,
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
      orderBy: 'effective_from DESC, id DESC',
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
      ORDER BY c.effective_from DESC, c.rowid DESC
    ''', [userId, date]);

    // Group by channel_key so each logical channel contributes once, using the latest row.
    Map<String, Map<String, dynamic>> latestConfigs = {};
    for (var row in results) {
      final key = row['channel_key'] as String;
      if (!latestConfigs.containsKey(key)) {
        latestConfigs[key] = row;
      }
    }

    return latestConfigs.values.toList();
  }
}
