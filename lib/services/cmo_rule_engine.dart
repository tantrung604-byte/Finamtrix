import '../models/cmo_analysis.dart';
import '../models/tiktok_ad_metrics.dart';

/// 2️⃣ Rule Engine — DETERMINISTIC.
///
/// Given the same [TikTokAdMetrics] it always returns the same [CmoAnalysis].
/// It performs ALL math here (engagement rate, cost per engagement, best/worst
/// video, suggested budget) so that the LLM layer never has to calculate.
class CmoRuleEngine {
  static final CmoRuleEngine instance = CmoRuleEngine._init();
  CmoRuleEngine._init();

  /// Safety factor applied to gross margin to derive the ad budget.
  /// suggestedAdBudget = safetyFactor * grossMargin.
  static const double safetyFactor = 0.70;

  CmoAnalysis runCMORuleEngine(TikTokAdMetrics metrics) {
    final totalImpressions = metrics.totalImpressions;
    final totalEngagements = metrics.totalEngagements;
    final totalCost = metrics.totalCost;
    final grossMargin = metrics.grossMargin;

    final engagementRate =
        totalImpressions == 0 ? 0.0 : totalEngagements / totalImpressions;
    final costPerEngagement =
        totalEngagements == 0 ? 0.0 : totalCost / totalEngagements;

    // Core rule: budget the business can safely spend on ads.
    final suggestedAdBudget = safetyFactor * grossMargin;

    // How much to change current spend to reach the suggested budget.
    final budgetDeltaPct = totalCost == 0
        ? 0.0
        : ((suggestedAdBudget - totalCost) / totalCost) * 100;

    final recommendation = _buildRecommendation(budgetDeltaPct);

    // Best / worst videos ranked by engagements (deterministic tie-break by id).
    TikTokVideoMetrics? bestVideo;
    TikTokVideoMetrics? worstVideo;
    if (metrics.videos.isNotEmpty) {
      final sorted = [...metrics.videos]..sort((a, b) {
          final cmp = b.engagements.compareTo(a.engagements);
          return cmp != 0 ? cmp : a.videoId.compareTo(b.videoId);
        });
      bestVideo = sorted.first;
      worstVideo = sorted.last;
    }

    return CmoAnalysis(
      periodStart: metrics.periodStart,
      periodEnd: metrics.periodEnd,
      totalImpressions: totalImpressions,
      totalEngagements: totalEngagements,
      totalCost: totalCost,
      totalRevenue: metrics.totalRevenue,
      grossMargin: grossMargin,
      engagementRate: engagementRate,
      costPerEngagement: costPerEngagement,
      suggestedAdBudget: suggestedAdBudget,
      budgetDeltaPct: budgetDeltaPct,
      recommendation: recommendation,
      bestVideo: bestVideo,
      worstVideo: worstVideo,
    );
  }

  String _buildRecommendation(double budgetDeltaPct) {
    final rounded = budgetDeltaPct.abs().round();
    if (rounded < 5) {
      return 'Giữ nguyên ngân sách quảng cáo hiện tại.';
    }
    if (budgetDeltaPct > 0) {
      return 'Tăng ngân sách quảng cáo khoảng $rounded%.';
    }
    return 'Giảm ngân sách quảng cáo khoảng $rounded%.';
  }
}

