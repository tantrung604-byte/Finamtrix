class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
  });
}

class AiChatHelper {
  static const Map<String, String> aiResponses = {
    'Gợi ý content': 'Dựa trên phân tích xu hướng TikTok tuần này, bạn nên tạo:\n\n📱 **3 video ngắn 15-30s** về review sản phẩm thật, không dàn dựng\n🎯 **Hashtag trending**: #reviewthật #muasắmthôngminh #tiktokmademebuyit\n⏰ **Đăng lúc**: 11h30-13h và 19h-21h\n\nTỉ lệ engagement dự kiến tăng **25-35%** 📈',
    'Phân tích đối thủ': 'Tôi đã scan **5 đối thủ chính** trong ngành của bạn:\n\n🏆 **Đối thủ A**: Tăng 15% reach nhờ video UGC\n📊 **Đối thủ B**: Giảm 10% do quảng cáo quá nhiều\n💡 **Cơ hội**: Chưa ai khai thác review từ khách hàng thật\n\n**Đề xuất**: Tạo series "Khách hàng nói gì?" — chi phí thấp, tin cậy cao 🎯',
    'Tối ưu ads': 'Phân tích hiệu suất ads 7 ngày qua:\n\n📘 **Facebook**: CPC ↓12%, nhưng CR thấp → Giảm 20% budget\n🎵 **TikTok**: ROAS 4.2x — **Đang hiệu quả nhất!** → Tăng 15% budget\n🔍 **Google**: CPC cao → Chỉ giữ brand keywords\n\n💰 **Tiết kiệm ước tính**: 8.5 triệu/tháng nếu reallocate ngay hôm nay',
    'Báo cáo tuần': '📊 **Báo cáo tuần 16-22/06/2026**\n\n✅ Doanh thu: 156tr (+12% vs tuần trước)\n✅ Đơn hàng: 312 đơn (78% target)\n✅ Chi phí ads: 28tr (giảm 5%)\n\n📈 **ROAS tổng**: 5.6x — Rất tốt!\n⚠️ **Lưu ý**: Tỉ lệ hoàn hàng tăng 3% — kiểm tra đóng gói\n\n🎯 Dự phóng tuần tới: 170-180tr nếu duy trì chiến lược hiện tại'
  };

  static const List<String> defaultResponses = [
    'Tôi hiểu câu hỏi của bạn! Để phân tích chính xác, tôi cần thêm dữ liệu về **ngành hàng** và **ngân sách** hiện tại của bạn. Bạn có thể chia sẻ thêm được không? 📊',
    'Câu hỏi hay! Dựa trên dữ liệu thị trường hiện tại, tôi khuyên bạn nên **tập trung vào retention** thay vì acquisition. Chi phí giữ chân khách hàng cũ chỉ bằng **1/5** chi phí tìm khách mới. 💡',
    'Tôi đang phân tích dữ liệu... 🔍 Theo benchmark ngành, bạn đang ở **top 30%** về hiệu suất marketing. Để lên top 10%, cần tối ưu **landing page** và **retargeting ads**. Bạn muốn tôi đi sâu vào phần nào?'
  ];
}
