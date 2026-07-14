import 'package:flutter_test/flutter_test.dart';

import 'package:finmatrix_flutter/services/cmo_advisor_service.dart';
import 'package:finmatrix_flutter/services/tiktok_api_service.dart';

/// Verifies the CMO pipeline is transparent about whether it used real data.
/// With no TikTok token and no Anthropic key configured, it MUST report
/// demo metrics + mock advice (never silently pretend to be live).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no token → demo metrics; no key → mock advice; not fully live', () async {
    final rec = await CmoAdvisorService.instance.generateAICMORecommendations(
      shopId: 'test_shop',
      accessToken: null,
    );

    expect(rec.dataSource, 'demo');
    expect(rec.adviceSource, 'mock');
    expect(rec.isFullyLive, isFalse);
    expect(rec.advice, isNotEmpty);
    expect(TikTokApiService.instance.lastMetricsSource, 'demo');
  });

  test('recommendation JSON exposes both sources for the UI', () async {
    final rec = await CmoAdvisorService.instance.generateAICMORecommendations(
      shopId: 'test_shop',
    );
    final json = rec.toJson();
    expect(json['data_source'], 'demo');
    expect(json['advice_source'], 'mock');
  });
}

