import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ollama_service.dart';

class LlmService {
  static final LlmService instance = LlmService._init();
  LlmService._init();

  static const String _model = 'claude-opus-4-8';
  static const String _anthropicVersion = '2023-06-01';

  /// Internal method used by AiGatewayService to access Cloud AI.
  /// In production, this would be a real server-to-server call.
  Future<String?> generateCloudChatResponse(String systemPrompt, String userMessage) async {
    return await _generateCloudResponse(systemPrompt, userMessage);
  }

  /// Cloud AI (Opus) is reserved for critical business suggestions, triggered via Gateway
  Future<String?> generateSuggestion(String ruleId, Map<String, dynamic> data) async {
    final systemPrompt = _getSystemPrompt(ruleId);
    final userMessage = jsonEncode(data);
    return await _generateCloudResponse(systemPrompt, userMessage);
  }

  Future<String?> _generateCloudResponse(String systemPrompt, String userMessage) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('anthropic_api_key');

    if (apiKey == null || apiKey.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': _anthropicVersion,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'max_tokens': 1024,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': userMessage}
          ],
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['content'][0]['text'] as String;
      } else {
        print('LLM Error: ${response.body}');
        return null;
      }
    } catch (e) {
      print('LLM Exception: $e');
      return null;
    }
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
