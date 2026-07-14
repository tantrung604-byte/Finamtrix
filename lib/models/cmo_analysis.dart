import 'tiktok_ad_metrics.dart';

/// Deterministic output of the CMO Rule Engine. Same input metrics always
/// produce the same analysis. This object is what Claude rephrases — Claude
/// never recomputes any of these numbers.
class CmoAnalysis {
  final String periodStart;
  final String periodEnd;

  final int totalImpressions;
  final int totalEngagements;
  final double totalCost;
  final double totalRevenue;
  final double grossMargin;

  /// Engagement rate = total engagements / total impressions (0..1).
  final double engagementRate;

  /// Cost per engagement, in VND.
  final double costPerEngagement;

  /// suggestedAdBudget = safetyFactor (0.70) * grossMargin.
  final double suggestedAdBudget;

  /// How much to change spend vs current cost, in percent (+ = increase).
  final double budgetDeltaPct;

  /// Plain recommendation, e.g. "tăng 18%" / "giảm 12%".
  final String recommendation;

  final TikTokVideoMetrics? bestVideo;
  final TikTokVideoMetrics? worstVideo;

  const CmoAnalysis({
    required this.periodStart,
    required this.periodEnd,
    required this.totalImpressions,
    required this.totalEngagements,
    required this.totalCost,
    required this.totalRevenue,
    required this.grossMargin,
    required this.engagementRate,
    required this.costPerEngagement,
    required this.suggestedAdBudget,
    required this.budgetDeltaPct,
    required this.recommendation,
    required this.bestVideo,
    required this.worstVideo,
  });

  /// Compact JSON used as the structured input to Claude.
  Map<String, dynamic> toJson() => {
        'period_start': periodStart,
        'period_end': periodEnd,
        'total_impressions': totalImpressions,
        'total_engagements': totalEngagements,
        'total_cost': totalCost,
        'total_revenue': totalRevenue,
        'gross_margin': grossMargin,
        'engagement_rate': engagementRate,
        'cost_per_engagement': costPerEngagement,
        'suggested_ad_budget': suggestedAdBudget,
        'budget_delta_pct': budgetDeltaPct,
        'recommendation': recommendation,
        'best_video': bestVideo == null
            ? null
            : {
                'video_id': bestVideo!.videoId,
                'title': bestVideo!.title,
                'engagements': bestVideo!.engagements,
                'cost': bestVideo!.cost,
              },
        'worst_video': worstVideo == null
            ? null
            : {
                'video_id': worstVideo!.videoId,
                'title': worstVideo!.title,
                'engagements': worstVideo!.engagements,
                'cost': worstVideo!.cost,
              },
      };
}

