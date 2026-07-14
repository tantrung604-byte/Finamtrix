import 'dart:convert';

import 'ai/ai_provider.dart';
import 'ai/anthropic_provider.dart';

/// Facade over the pluggable [AiProvider] registry.
///
/// Routing (Opus vs Sonnet, decision vs synthesis) still lives in
/// `AiGatewayService`; this class owns provider selection, credential handling
/// (via `SecureConfigService` inside each provider) and prompt construction.
class LlmService {
  LlmService._init();
  static final LlmService instance = LlmService._init();

  /// Test seam: allows overriding the default provider registry.
  factory LlmService.withProviders(
    Map<String, AiProvider> providers, {
    String defaultProviderId = 'anthropic',
  }) {
    final svc = LlmService._init();
    svc._providers
      ..clear()
      ..addAll(providers);
    svc._defaultProviderId = defaultProviderId;
    return svc;
  }

  /// High-capability model for strategic DECISIONS (đưa ra quyết định).
  static const String modelOpus = 'claude-3-opus-latest';

  /// Faster model for routine data synthesis & planning (tổng hợp số liệu, lên plan).
  static const String modelSonnet = 'claude-3-5-sonnet-latest';

  /// Sonnet model used by the TikTok CMO advisory flow (fast + cheap).
  /// Updated to use valid Anthropic model IDs. Previous placeholders like
  /// 'claude-sonnet-4-5' returned 404, forcing mocks.
  static const String modelSonnetCmo = 'claude-3-5-sonnet-latest';

  /// Registry of available model vendors. New providers plug in here.
  final Map<String, AiProvider> _providers = {
    'anthropic': AnthropicProvider(),
  };
  String _defaultProviderId = 'anthropic';

  AiProvider get _provider => _providers[_defaultProviderId]!;

  /// Exposed for UI/diagnostics.
  String get activeProviderName => _provider.displayName;

  /// Lightweight credential/connectivity check for the active provider.
  Future<({bool ok, String message})> testConnection({
    String? apiKeyOverride,
    String model = modelSonnet,
  }) async {
    final health =
        await _provider.ping(model: model, apiKeyOverride: apiKeyOverride);
    return (ok: health.ok, message: health.message);
  }

  /// Internal method used by AiGatewayService to access Cloud AI.
  Future<String?> generateCloudChatResponse(
    String systemPrompt,
    String userMessage, {
    String model = modelSonnet,
  }) async {
    return _complete(systemPrompt, userMessage, model: model);
  }

  /// Cloud AI is reserved for critical business suggestions, triggered via Gateway.
  /// [model] lets the gateway pick Opus (decisions) vs Sonnet (synthesis/plan).
  Future<String?> generateSuggestion(
    String ruleId,
    Map<String, dynamic> data, {
    String model = modelSonnet,
  }) async {
    final systemPrompt = _getSystemPrompt(ruleId);
    final userMessage = jsonEncode(data);
    return _complete(systemPrompt, userMessage, model: model);
  }

  Future<String?> _complete(
    String systemPrompt,
    String userMessage, {
    required String model,
  }) async {
    final result = await _provider.complete(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
      model: model,
    );
    // Null on any failure → callers fall back to AiMockService.
    return result.ok ? result.text : null;
  }

  String _getSystemPrompt(String ruleId) {
    String ruleDescription = '';
    switch (ruleId) {
      case 'R1_underperform':
        ruleDescription = 'Kênh bán hàng đang có hiệu suất đơn hàng thấp hơn mục tiêu dự kiến.';
        break;
      case 'R4_fomo_alert':
        ruleDescription = 'Cảnh báo chỉ số FOMO thị trường vàng đang quá cao trong khi người dùng có ý định mua.';
        break;
      case 'R5_data_reminder':
        ruleDescription = 'Nhắc nhở người dùng cập nhật số liệu thực tế vì đã lâu không nhập liệu.';
        break;
      case 'R7_competitor_plan':
        ruleDescription = 'Phân tích chiến dịch quảng cáo của đối thủ và đề xuất một Plan Tấn Công hoặc Phòng Thủ cụ thể.';
        break;
      default:
        ruleDescription = 'Phân tích dữ liệu kinh doanh và đưa ra gợi ý.';
    }

    return '''
Bạn là AI CMO - Trợ lý ảo tăng trưởng chuyên nghiệp và là Nhà Chiến Lược Kinh Doanh tài ba.
NHIỆM VỤ: Diễn đạt lại dữ liệu từ Rule Engine thành một câu gợi ý hoặc một "Plan Tấn Công" ngắn gọn, sắc bén và có tính thực thi cao.
QUY TẮC:
1. Đối với dữ liệu đối thủ (R7), hãy tập trung vào việc tìm ra điểm yếu của họ hoặc cách bạn có thể làm tốt hơn (Plan Tấn Công).
2. KHÔNG tự đưa ra số liệu mới ngoài dữ liệu được cung cấp.
3. Ngôn ngữ: Tiếng Việt, quyết đoán, chuyên nghiệp.
4. Độ dài: Tối đa 3 câu.
5. Bối cảnh: $ruleDescription
Dữ liệu đầu vào là JSON. Hãy biến nó thành một hành động chiến lược.
''';
  }
}
