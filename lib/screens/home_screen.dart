import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/fomo_gauge.dart';
import '../widgets/sparkline_chart.dart';
import '../models/market_data.dart';

class HomeScreen extends StatelessWidget {
  final Function(int) onNavigateToTab;

  const HomeScreen({
    Key? key,
    required this.onNavigateToTab,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final goldAsset = MarketData.assets.firstWhere((a) => a.id == 'gold');
    final bdsAsset = MarketData.assets.firstWhere((a) => a.id == 'bds');
    final stockAsset = MarketData.assets.firstWhere((a) => a.id == 'stock');
    final usdHistory = [25200.0, 25300.0, 25280.0, 25350.0, 25400.0, 25420.0, 25480.0];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'F',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'FinMatrix',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.textPrimary),
            ),
          ],
        ),
        actions: [
          // Notification Bell
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none, color: AppTheme.textPrimary),
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: AppTheme.colorDanger,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    child: const Text(
                      '3',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Hệ thống đang hoạt động ổn định!'),
                  backgroundColor: AppTheme.bgSecondary,
                ),
              );
            },
          ),
          const SizedBox(width: 4),
          // User Avatar Button
          GestureDetector(
            onTap: () => onNavigateToTab(4), // Go to Profile
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              alignment: Alignment.center,
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                gradient: AppTheme.premiumGradient,
                shape: BoxShape.circle,
              ),
              child: const Text(
                'T',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. FOMO Gauge Hero Card
            GlassCard(
              glowColor: AppTheme.brandCyan,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'THANG ĐO NHIỆT ĐỘ',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.brandCyan,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'FOMO Index',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.colorWarm.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '⚡ ẤM',
                          style: TextStyle(
                            color: AppTheme.colorWarm,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const FomoGauge(value: 42),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildLegendItem('An toàn', AppTheme.colorSafe),
                      _buildLegendItem('Ấm', AppTheme.colorWarm),
                      _buildLegendItem('Đột biến', AppTheme.colorHot),
                      _buildLegendItem('Nguy hiểm', AppTheme.colorDanger),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. Quick Stats Grid
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context: context,
                    icon: '🛡️',
                    value: 'An toàn',
                    label: 'Bảo vệ tiền',
                    color: AppTheme.colorSafe,
                    onTap: () => onNavigateToTab(1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    context: context,
                    icon: '💰',
                    value: 'Tăng 12%',
                    label: 'Tạo ra tiền',
                    color: AppTheme.colorWarm,
                    onTap: () => onNavigateToTab(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    context: context,
                    icon: '🤖',
                    value: '5 gợi ý',
                    label: 'AI đồng hành',
                    color: AppTheme.brandCyan,
                    onTap: () => onNavigateToTab(3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 3. Market Ticker
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📊 Thị trường hôm nay',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                GestureDetector(
                  onTap: () => onNavigateToTab(1),
                  child: const Text(
                    'Xem tất cả →',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.brandCyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 76,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildTickerCard(
                    name: '🥇 Vàng SJC',
                    price: '92.5 tr',
                    unit: ' tr/lượng',
                    change: '↑ +1.8%',
                    up: true,
                    color: goldAsset.color,
                    history: goldAsset.weekData,
                  ),
                  const SizedBox(width: 10),
                  _buildTickerCard(
                    name: '🏠 BDS Hà Nội',
                    price: '68.2 tr',
                    unit: ' tr/m²',
                    change: '↓ -0.3%',
                    up: false,
                    color: bdsAsset.color,
                    history: bdsAsset.weekData,
                  ),
                  const SizedBox(width: 10),
                  _buildTickerCard(
                    name: '📈 VN-Index',
                    price: '1,285',
                    unit: ' điểm',
                    change: '↑ +0.6%',
                    up: true,
                    color: stockAsset.color,
                    history: stockAsset.weekData,
                  ),
                  const SizedBox(width: 10),
                  _buildTickerCard(
                    name: '💵 USD/VND',
                    price: '25,480',
                    unit: ' đ',
                    change: '↑ +0.2%',
                    up: true,
                    color: AppTheme.brandCyan,
                    history: usdHistory,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 4. AI CMO Tip Card
            const Text(
              '🤖 AI CMO gợi ý cho bạn',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              glowColor: AppTheme.brandPurple,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.brandPurple.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '🤖',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gợi ý hôm nay',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tối ưu tiêu đề video TikTok — tăng tỉ lệ giữ chân viewer lên 35%. Nên đăng vào khung giờ 11h30 – 13h hôm nay.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 5. Recent Alerts
            const Text(
              '🔔 Cảnh báo gần đây',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildAlertCard(
                  icon: '⚠️',
                  title: 'Giá vàng tăng mạnh',
                  desc: 'SJC vượt mốc 92 triệu, cần cân nhắc',
                  time: '2h trước',
                  color: AppTheme.colorWarm,
                ),
                const SizedBox(height: 8),
                _buildAlertCard(
                  icon: '✅',
                  title: 'Break-even đạt 78%',
                  desc: 'Doanh thu tuần này vượt kỳ vọng',
                  time: '5h trước',
                  color: AppTheme.colorSafe,
                ),
                const SizedBox(height: 8),
                _buildAlertCard(
                  icon: '🔴',
                  title: 'BDS giảm nhẹ',
                  desc: 'Phân khúc chung cư HN giảm 0.3%',
                  time: '1 ngày',
                  color: AppTheme.colorDanger,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String name, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          name,
          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required BuildContext context,
    required String icon,
    required String value,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                icon,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTickerCard({
    required String name,
    required String price,
    required String unit,
    required String change,
    required bool up,
    required Color color,
    required List<double> history,
  }) {
    return Container(
      width: 148,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.glassBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.glassBorder,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    text: price,
                    style: TextStyle(
                      fontSize: 13.0,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                    children: [
                      TextSpan(
                        text: unit,
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  change,
                  style: TextStyle(
                    fontSize: 9.0,
                    fontWeight: FontWeight.bold,
                    color: up ? AppTheme.colorSafe : AppTheme.colorDanger,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          SparklineChart(
            data: history,
            color: color,
            width: 42,
            height: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard({
    required String icon,
    required String title,
    required String desc,
    required String time,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.glassBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.glassBorder,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              icon,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
