import 'package:flutter_test/flutter_test.dart';
import 'package:finmatrix_flutter/services/ai_mock_service.dart';

void main() {
  final mock = AiMockService.instance;

  test('chat returns chip response for content suggestion', () {
    final reply = mock.chat('💡 Gợi ý content');
    expect(reply, contains('TikTok'));
    expect(reply, contains('video'));
  });

  test('chat returns strategic plan for marketing keywords', () {
    final reply = mock.chat('Lập kế hoạch marketing tháng này');
    expect(reply, contains('Chiến lược'));
  });

  test('rephrase formats R1 underperform rule', () {
    final reply = mock.rephrase('R1_underperform', {
      'channel': 'TikTok Ads',
      'deviation': 22,
    });
    expect(reply, contains('TikTok Ads'));
    expect(reply, contains('22%'));
  });

  test('strategic analysis extracts category from prompt', () {
    final reply = mock.strategicAnalysis('''
Dựa trên dữ liệu:
- Ngành hàng: Thời trang
- Tổng đơn hàng cần: 400 đơn
- Ngân sách Ads dự kiến: 50.000.000 VNĐ
''');
    expect(reply, contains('Thời trang'));
    expect(reply, contains('400'));
  });
}
