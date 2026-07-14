@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:finmatrix_flutter/models/cmo_analysis.dart';
import 'package:finmatrix_flutter/services/cmo_advisor_service.dart';

/// LIVE smoke test — hits the real Anthropic API. Excluded from the default
/// suite via the `live` tag (see dart_test.yaml). Run it explicitly with a key:
///
///   flutter test test/live_cmo_smoke_test.dart --tags live \
///     --dart-define=ANTHROPIC_API_KEY=sk-ant-...
///
/// It builds a deterministic [CmoAnalysis] (the same shape the Rule Engine
/// produces) and confirms the CMO flow returns a real Claude response
/// (`source == 'claude'`) rather than the mock fallback.
// True only when a key was supplied at compile time via --dart-define.
// Lets the test self-skip during the normal (offline) `flutter test` run.
const bool _hasKey = bool.hasEnvironment('ANTHROPIC_API_KEY');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const analysis = CmoAnalysis(
    periodStart: '2026-06-24',
    periodEnd: '2026-06-30',
    totalImpressions: 120000,
    totalEngagements: 5400,
    totalCost: 8000000,
    totalRevenue: 21000000,
    grossMargin: 13000000,
    engagementRate: 0.045,
    costPerEngagement: 1481.48,
    suggestedAdBudget: 9100000,
    budgetDeltaPct: 13.75,
    recommendation: 'tăng 14%',
    bestVideo: null,
    worstVideo: null,
  );

  test('CMO advisory returns a live Claude response', () async {
    // flutter_test's binding stubs all HTTP requests to return 400. Disable
    // that override so this test can reach the real Anthropic endpoint.
    HttpOverrides.global = null;

    final result =
        await CmoAdvisorService.instance.getCMOAdviceFromClaude(analysis);

    // ignore: avoid_print
    print('advice.source = ${result.source}');
    // ignore: avoid_print
    print('advice.text   = ${result.advice}');

    expect(result.source, 'claude',
        reason:
            'Expected a live Claude reply. Ensure --dart-define=ANTHROPIC_API_KEY '
            'is passed and the key is valid.');
    expect(result.advice.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)),
      skip: _hasKey ? false : 'no ANTHROPIC_API_KEY supplied via --dart-define');
}

