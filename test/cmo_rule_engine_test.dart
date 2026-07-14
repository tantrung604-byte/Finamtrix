import 'package:flutter_test/flutter_test.dart';
import 'package:finmatrix_flutter/models/tiktok_ad_metrics.dart';
import 'package:finmatrix_flutter/services/cmo_rule_engine.dart';

void main() {
  final engine = CmoRuleEngine.instance;

  TikTokAdMetrics buildMetrics() => TikTokAdMetrics.fromJson({
        'shop_id': 'shop_1',
        'period_start': '2026-06-21',
        'period_end': '2026-06-28',
        'cogs_ratio': 0.5,
        'videos': [
          {
            'video_id': 'v_a',
            'title': 'A',
            'impressions': 1000,
            'likes': 80,
            'comments': 10,
            'shares': 10, // engagements = 100
            'clicks': 50,
            'conversions': 5,
            'cost': 1000000,
            'revenue': 8000000,
          },
          {
            'video_id': 'v_b',
            'title': 'B',
            'impressions': 1000,
            'likes': 10,
            'comments': 5,
            'shares': 5, // engagements = 20
            'clicks': 10,
            'conversions': 1,
            'cost': 1000000,
            'revenue': 2000000,
          },
        ],
      });

  test('engine is deterministic for identical input', () {
    final a = engine.runCMORuleEngine(buildMetrics());
    final b = engine.runCMORuleEngine(buildMetrics());

    expect(a.engagementRate, b.engagementRate);
    expect(a.costPerEngagement, b.costPerEngagement);
    expect(a.suggestedAdBudget, b.suggestedAdBudget);
    expect(a.budgetDeltaPct, b.budgetDeltaPct);
    expect(a.bestVideo?.videoId, b.bestVideo?.videoId);
    expect(a.worstVideo?.videoId, b.worstVideo?.videoId);
  });

  test('suggestedAdBudget = 0.70 * gross_margin', () {
    final analysis = engine.runCMORuleEngine(buildMetrics());

    // revenue = 10,000,000 ; cogsRatio = 0.5 -> grossMargin = 5,000,000
    expect(analysis.grossMargin, 5000000);
    expect(analysis.suggestedAdBudget, 0.70 * 5000000);
  });

  test('computes engagement rate and cost per engagement', () {
    final analysis = engine.runCMORuleEngine(buildMetrics());

    // engagements = 120, impressions = 2000 -> 0.06
    expect(analysis.engagementRate, closeTo(0.06, 1e-9));
    // cost = 2,000,000 / 120 engagements
    expect(analysis.costPerEngagement, closeTo(2000000 / 120, 1e-6));
  });

  test('identifies best and worst videos by engagement', () {
    final analysis = engine.runCMORuleEngine(buildMetrics());
    expect(analysis.bestVideo?.videoId, 'v_a');
    expect(analysis.worstVideo?.videoId, 'v_b');
  });

  test('recommendation reflects budget delta direction', () {
    final analysis = engine.runCMORuleEngine(buildMetrics());
    // suggested 3,500,000 < cost 2,000,000? No: 3.5M > 2M -> increase
    expect(analysis.budgetDeltaPct, greaterThan(0));
    expect(analysis.recommendation, contains('Tăng'));
  });
}

