
import 'ai_mock_service.dart';
import 'llm_service.dart';

/// Simulated Backend AI Gateway with mock fallback for Web / offline use.
class AiGatewayService {
  static final AiGatewayService instance = AiGatewayService._init();
  AiGatewayService._init();

  /// Rules that represent a high-stakes strategic DECISION (đưa ra quyết định)
  /// → routed to Opus 4.8. Everything else (data synthesis / planning) uses
  /// Sonnet 4.5.
  static const Set<String> _decisionRuleIds = {
    'R4_fomo_alert', // quyết định dòng vốn theo FOMO vàng
    'R7_competitor_plan', // quyết định tấn công / phòng thủ đối thủ
    'R8_macro_purchasing_power', // quyết định nhập hàng / giữ vốn theo vĩ mô
  };

  /// Picks the cloud model: Opus 4.8 for decisions, Sonnet 4.5 for synthesis/plan.
  String _selectModel({required String taskType, String? ruleId}) {
    final bool isDecision = taskType == 'strategic_decision' ||
        (taskType == 'rephrase' && ruleId != null && _decisionRuleIds.contains(ruleId));
    return isDecision ? LlmService.modelOpus : LlmService.modelSonnet;
  }

  /// Exposed for transparency/testing: the cloud model a task routes to.
  String modelForTask({required String taskType, String? ruleId}) =>
      _selectModel(taskType: taskType, ruleId: ruleId);

  Future<String> processAiRequest({
    required String prompt,
    required String taskType,
    Map<String, dynamic>? context,
  }) async {
    print('--- AI Gateway: Analyzing Task [$taskType] ---');

    // Strategic DECISION → Opus 4.8 (highest reasoning).
    if (taskType == 'strategic_decision') {
      print('Decision: STRATEGIC DECISION -> Cloud (Opus 4.8) with mock fallback');
      final response = await LlmService.instance.generateCloudChatResponse(
        'Bạn là AI CMO. Hãy phân tích và ĐƯA RA QUYẾT ĐỊNH dứt khoát kèm lý do ngắn gọn.',
        prompt,
        model: LlmService.modelOpus,
      );
      return response ?? AiMockService.instance.marketingPlan(prompt);
    }

    // Data synthesis + planning → Sonnet 4.5 (fast, structured).
    if (taskType == 'marketing_plan' || taskType == 'strategic_analysis') {
      print('Decision: SYNTHESIS/PLAN -> Cloud (Sonnet 4.5) with mock fallback');
      final response = await LlmService.instance.generateCloudChatResponse(
        'Bạn là Chuyên gia Marketing cao cấp. Hãy tổng hợp số liệu và lập kế hoạch xử lý chi tiết.',
        prompt,
        model: LlmService.modelSonnet,
      );
      return response ?? AiMockService.instance.marketingPlan(prompt);
    }

    if (taskType == 'rephrase') {
      final ruleId = context?['rule_id']?.toString() ?? 'default';
      final model = _selectModel(taskType: taskType, ruleId: ruleId);
      final tier = model == LlmService.modelOpus ? 'Opus 4.8 (Decision)' : 'Sonnet 4.5 (Synthesis)';
      print('Decision: BUSINESS RULE [$ruleId] -> Cloud ($tier) with mock fallback');
      final response = await LlmService.instance.generateSuggestion(ruleId, context ?? {}, model: model);
      return response ?? AiMockService.instance.rephrase(ruleId, context ?? {});
    }

    // Chat / Q&A thường → Sonnet 4.5 (trước đây dùng Ollama local / Mock).
    print('Decision: ROUTINE TASK -> Cloud (Sonnet 4.5) with mock fallback');
    final response = await LlmService.instance.generateCloudChatResponse(
      'Bạn là AI CMO — trợ lý tăng trưởng. Trả lời ngắn gọn, hữu ích, bằng tiếng Việt.',
      prompt,
      model: LlmService.modelSonnet,
    );
    return response ?? AiMockService.instance.chat(prompt);
  }
}
