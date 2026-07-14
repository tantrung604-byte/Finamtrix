import '../models/chat_message.dart';

/// Offline mock responses when Ollama / Cloud AI is unavailable (especially Web).
class AiMockService {
  static final AiMockService instance = AiMockService._init();
  AiMockService._init();

  String chat(String prompt) {
    final normalized = _stripEmoji(prompt).trim();

    for (final entry in AiChatHelper.aiResponses.entries) {
      if (normalized.contains(entry.key) ||
          prompt.contains(entry.key)) {
        return entry.value;
      }
    }

    final lower = normalized.toLowerCase();

    if (lower.contains('tiktok') || lower.contains('content') || lower.contains('video')) {
      return AiChatHelper.aiResponses['Gợi ý content']!;
    }
    if (lower.contains('đối thủ') || lower.contains('competitor')) {
      return AiChatHelper.aiResponses['Phân tích đối thủ']!;
    }
    if (lower.contains('ads') || lower.contains('quảng cáo') || lower.contains('tối ưu')) {
      return AiChatHelper.aiResponses['Tối ưu ads']!;
    }
    if (lower.contains('báo cáo') || lower.contains('tuần') || lower.contains('report')) {
      return AiChatHelper.aiResponses['Báo cáo tuần']!;
    }
    if (lower.contains('plan') || lower.contains('kế hoạch') || lower.contains('marketing')) {
      return strategicAnalysis(prompt);
    }
    if (lower.contains('xin chào') || lower.contains('chào') || lower.contains('hello')) {
      return 'Chào bạn! 👋 Tôi là **AI CMO** — sẵn sàng hỗ trợ tăng trưởng. Bạn muốn tôi gợi ý content, phân tích ads hay lập kế hoạch marketing tuần này?';
    }

    final index = prompt.hashCode.abs() % AiChatHelper.defaultResponses.length;
    return AiChatHelper.defaultResponses[index];
  }

  String rephrase(String ruleId, Map<String, dynamic> data) {
    switch (ruleId) {
      case 'R1_underperform':
        final channel = data['channel'] ?? 'kênh bán hàng';
        final deviation = (data['deviation'] as num?)?.round() ?? 0;
        return '📊 **$channel** đang chậm **$deviation%** so với nhịp cần đạt. Ưu tiên: rà lại creative + tăng retargeting trong 48h tới.';
      case 'R4_fomo_alert':
        final score = (data['score'] as num?)?.round() ?? 0;
        return '⚠️ FOMO vàng ở **$score điểm** — thị trường đang nóng. Nếu bạn định mua, hãy chia nhỏ lệnh và tránh FOMO.';
      case 'R5_data_reminder':
        return '⏰ Đã lâu bạn chưa cập nhật số liệu thực tế. Nhập đơn hàng & chi phí ads để AI CMO tư vấn chính xác hơn.';
      case 'R7_competitor_plan':
        final competitors = data['competitors'] ?? 'đối thủ chính';
        return '⚔️ **$competitors** vừa tăng chiến dịch. Đề xuất: chạy A/B test UGC review + giữ ngân sách phòng thủ 20% cho retargeting.';
      case 'R8_macro_purchasing_power':
        final drop = (data['drop_pct'] as num?)?.round() ?? 0;
        return '🔗 **Vĩ mô → Vi mô:** Vàng đang nóng, sức mua B2C dự kiến giảm **~$drop%**. Đề xuất: giảm nhập hàng tồn, đẩy khuyến mãi giữ chân khách & ưu tiên retargeting khách cũ.';
      default:
        return '💡 Dữ liệu mới cần xem xét — hãy mở chi tiết kênh và cập nhật chỉ số tuần này.';
    }
  }

  String strategicAnalysis(String prompt) {
    String category = 'B2C';
    for (final name in ['Thời trang', 'Du lịch', 'Ăn uống', 'Tiêu dùng', 'Điện tử']) {
      if (prompt.contains(name)) {
        category = name;
        break;
      }
    }

    final ordersMatch = RegExp(r'Tổng đơn hàng cần:\s*(\d+)').firstMatch(prompt);
    final budgetMatch = RegExp(r'Ngân sách Ads dự kiến:\s*([\d.,]+)').firstMatch(prompt);
    final orders = ordersMatch?.group(1) ?? '—';
    final budget = budgetMatch?.group(1) ?? '—';

    return '''🎯 **Chiến lược $category** (chế độ demo)

Với **$orders đơn** và ngân sách ads **$budget VNĐ**, tôi khuyên:

1. **60% budget** vào TikTok Spark Ads + video UGC 15–30s
2. **30%** retargeting khách đã xem > 50% video
3. **10%** thử nghiệm offer giới hạn 48h để kéo CR

📈 Mục tiêu: ROAS ≥ 4x trong 2 tuần đầu. Bạn muốn tôi chi tiết kịch bản content không?''';
  }

  String marketingPlan(String prompt) => strategicAnalysis(prompt);

  String _stripEmoji(String text) {
    return text.replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true), '').trim();
  }
}
