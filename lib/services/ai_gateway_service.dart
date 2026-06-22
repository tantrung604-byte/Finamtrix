import 'dart:convert';
import 'llm_service.dart';
import 'ollama_service.dart';

/// This service acts as a simulated Backend AI Gateway.
/// In a production environment, this logic would reside on a server (e.g., Node.js, Python, or Dart Shelf).
class AiGatewayService {
  static final AiGatewayService instance = AiGatewayService._init();
  AiGatewayService._init();

  /// The entry point for all AI requests. 
  /// The backend (simulated here) decides which model to use.
  Future<String> processAiRequest({
    required String prompt,
    required String taskType, // 'chat', 'marketing_plan', 'rephrase'
    Map<String, dynamic>? context,
  }) async {
    print('--- AI Gateway: Analyzing Task [$taskType] ---');

    // 1. Backend-defined routing logic
    if (taskType == 'marketing_plan' || taskType == 'strategic_analysis') {
      print('Decision: HIGH COMPLEXITY -> Routing to Cloud (Opus 4.8)');
      // In production, the backend makes the HTTP call to Anthropic using its own API keys.
      // Here we simulate this by calling our internal LlmService.
      final response = await LlmService.instance.generateCloudChatResponse(
        'Bạn là Chuyên gia Marketing cao cấp. Hãy lập kế hoạch chi tiết.',
        prompt,
      );
      return response ?? 'Lỗi: Không thể kết nối Cloud AI cho chiến lược.';
    } 
    
    else if (taskType == 'rephrase') {
      print('Decision: BUSINESS LOGIC -> Routing to Cloud (Opus 4.8)');
      // Precise rephrasing of business data requires high reasoning
      final ruleId = context?['rule_id'] ?? 'default';
      final response = await LlmService.instance.generateSuggestion(ruleId, context ?? {});
      return response ?? 'Dữ liệu kinh doanh: ${jsonEncode(context)}';
    } 
    
    else {
      // Default: Simple Chat or General Q&A
      print('Decision: ROUTINE TASK -> Routing to Local AI (Ollama)');
      // The backend instructs the client to use its local model to save $
      final response = await OllamaService.instance.generateLocalResponse(prompt);
      return response ?? 'Hệ thống Local AI đang bận. Bạn có muốn thử lại sau?';
    }
  }
}
