import 'dart:convert';

import '../models/cmo_analysis.dart';
import '../models/tiktok_ad_metrics.dart';
import '../services/ai_mock_service.dart';
import '../services/cmo_rule_engine.dart';
import '../services/fastmoss_service.dart';
import '../services/llm_service.dart';
import '../services/tiktok_api_service.dart';

/// Result of the full CMO recommendation workflow.
class CmoRecommendation {
  final CmoAnalysis analysis;
  final String advice;
  final DateTime timestamp;

  /// Where the input metrics came from: `'live'` (real TikTok API) or `'demo'`.
  final String dataSource;

  /// Where the wording came from: `'claude'` (real LLM) or `'mock'` (fallback).
  final String adviceSource;

  const CmoRecommendation({
    required this.analysis,
    required this.advice,
    required this.timestamp,
    this.dataSource = 'demo',
    this.adviceSource = 'mock',
  });

  /// True only when BOTH the metrics and the wording are from real sources.
  bool get isFullyLive =>
      (dataSource == 'fastmoss' || dataSource == 'live') &&
      adviceSource == 'claude';

  Map<String, dynamic> toJson() => {
        'analysis': analysis.toJson(),
        'advice': advice,
        'timestamp': timestamp.toIso8601String(),
        'data_source': dataSource,
        'advice_source': adviceSource,
      };
}

/// Orchestrates the TikTok CMO advisory pipeline:
///
/// User TikTok Data → Fetch API → Rule Engine → Claude Sonnet → Response
class CmoAdvisorService {
  static final CmoAdvisorService instance = CmoAdvisorService._init();
  CmoAdvisorService._init();

  static const String _systemPrompt = '''
Bạn là AI CMO - trợ lý tăng trưởng. Bạn nhận một đối tượng JSON đã được TÍNH TOÁN SẴN
từ Rule Engine (engagement rate, cost per engagement, video tốt/kém nhất, ngân sách
quảng cáo đề xuất, % thay đổi chi phí).

NHIỆM VỤ: Diễn đạt lại dữ liệu thành lời tư vấn tiếng Việt ngắn gọn, sắc bén, dễ hành động.

QUY TẮC:
1. TUYỆT ĐỐI KHÔNG tự tính toán hay tạo ra số liệu mới ngoài JSON được cung cấp.
2. Bám sát "recommendation" và "suggested_ad_budget" trong dữ liệu.
3. Nêu rõ video tốt nhất nên nhân bản và video kém nhất nên cắt giảm.
4. Ngôn ngữ: Tiếng Việt, quyết đoán, chuyên nghiệp. Tối đa 4 câu.
''';

  /// 3️⃣ Claude API — only rephrases the structured analysis into Vietnamese.
  /// Does NOT call TikTok again and does NOT recompute any logic.
  ///
  /// Returns the advice text plus its [source]: `'claude'` when the real LLM
  /// answered, `'mock'` when it fell back to [AiMockService].
  Future<({String advice, String source})> getCMOAdviceFromClaude(
      CmoAnalysis analysis) async {
    final userMessage = jsonEncode(analysis.toJson());

    final response = await LlmService.instance.generateCloudChatResponse(
      _systemPrompt,
      userMessage,
      model: LlmService.modelSonnetCmo,
    );

    if (response != null) {
      return (advice: response, source: 'claude');
    }
    // Mock fallback (no API key / Web / offline) keeps the flow usable in demos.
    return (
      advice: AiMockService.instance.marketingPlan(userMessage),
      source: 'mock',
    );
  }

  /// 4️⃣ Main Workflow — Fetch → Analyze → Advise.
  ///
  /// Metrics priority:
  ///   1. **FastMoss** Top Selling market data (real, VN) → `dataSource='fastmoss'`
  ///   2. TikTok Shop live API when an [accessToken] is set → `'live'`
  ///   3. Built-in demo data → `'demo'`
  Future<CmoRecommendation> generateAICMORecommendations({
    required String shopId,
    String? accessToken,
    String region = 'VN',
    int? categoryId,
    int periodDays = 7,
  }) async {
    TikTokAdMetrics? metrics;
    String dataSource;

    // 1) Prefer real FastMoss fully-managed data.
    metrics = await FastmossService.instance.fetchCmoMetrics(
      region: region,
      categoryId: categoryId,
      periodDays: periodDays,
    );

    if (metrics != null && metrics.videos.isNotEmpty) {
      dataSource = 'fastmoss';
    } else {
      // 2/3) Fall back to TikTok live (if token) or demo.
      metrics = await TikTokApiService.instance.fetchTikTokAdMetrics(
        shopId: shopId,
        accessToken: accessToken,
      );
      dataSource = TikTokApiService.instance.lastMetricsSource; // 'live' | 'demo'
    }

    // Analyze (deterministic)
    final analysis = CmoRuleEngine.instance.runCMORuleEngine(metrics);

    // Advise (LLM rephrase only)
    final result = await getCMOAdviceFromClaude(analysis);

    return CmoRecommendation(
      analysis: analysis,
      advice: result.advice,
      timestamp: DateTime.now(),
      dataSource: dataSource,
      adviceSource: result.source,
    );
  }
}

