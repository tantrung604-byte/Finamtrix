import 'package:sqflite/sqflite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/fomo_gauge.dart';
import '../widgets/line_chart_painter.dart';
import '../models/market_data.dart';
import '../services/database_helper.dart';
import '../services/fomo_service.dart';

class MacroScreen extends StatefulWidget {
  const MacroScreen({Key? key}) : super(key: key);

  @override
  State<MacroScreen> createState() => _MacroScreenState();
}

class _MacroScreenState extends State<MacroScreen> {
  String _selectedAssetId = 'gold';
  String _selectedPeriod = '1W';
  double _dbFomoScore = 0;
  List<double> _dbPrices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // 1. Ensure we have a default user for MVP
      final db = await DatabaseHelper.instance.database;
      final userCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM users'));
      if (userCount == 0) {
        await db.insert('users', {
          'user_id': 'default_user',
          'phone_or_email': 'user@example.com',
          'display_name': 'Tantr',
          'subscription_tier': 'premium',
        });
      }

      // 2. Mock some price data if empty so the gauge isn't 0
      final priceCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM gold_price_daily'));
      if (priceCount == 0) {
        final base = 88.5;
        for (int i = 0; i < 40; i++) {
          final date = DateTime.now().subtract(Duration(days: 40 - i)).toIso8601String().split('T')[0];
          await db.insert('gold_price_daily', {
            'date': date,
            'price_buy': base + (i * 0.1),
            'price_sell': base + (i * 0.1) + 1.0,
            'source': 'SJC',
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await FomoService.instance.calculateAndSaveFomoScore('gold');
      }

      // 3. Fetch data from DB
      final fomoResult = await db.query(
        'fomo_score_daily',
        where: 'asset_type = ?',
        whereArgs: [_selectedAssetId],
        orderBy: 'date DESC',
        limit: 1,
      );
      
      final priceHistory = await db.query(
        'gold_price_daily',
        orderBy: 'date DESC',
        limit: 30,
      );

      if (mounted) {
        setState(() {
          _dbFomoScore = fomoResult.isNotEmpty ? (fomoResult.first['fomo_score'] as num ?? 0).toDouble() : 0;
          _dbPrices = priceHistory.reversed.map((p) => (p['price_sell'] as num).toDouble()).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('MacroScreen Error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.brandCyan)));
    }

    final activeAsset = MarketData.assets.firstWhere((a) => a.id == _selectedAssetId);
    
    // Override with DB data for Gold
    double displayFomoValue = _selectedAssetId == 'gold' ? _dbFomoScore : activeAsset.gaugeValue;
    List<double> chartData = _selectedAssetId == 'gold' && _dbPrices.isNotEmpty ? _dbPrices : activeAsset.weekData;

    // Custom metrics details mapping based on selected asset
    Map<String, List<String>> metricsMap = {
      'gold': ['92.5 tr', '↑ +1.8%', '+3.2%', '+2.87 triệu', '94.1 tr', '12/05/2026', '78.3 tr', '08/11/2025'],
      'bds': ['68.2 tr/m²', '↓ -0.3%', '+0.5%', '+0.34 triệu', '69.5 tr', '18/02/2026', '62.0 tr', '15/09/2025'],
      'stock': ['1,285', '↑ +0.6%', '+1.2%', '+15.4 điểm', '1,310', '02/04/2026', '1,080', '28/10/2025'],
    };
    final metrics = metricsMap[_selectedAssetId] ?? metricsMap['gold']!;

    return Scaffold(
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            // Header Section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'DỰ BÁO XU HƯỚNG',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.brandCyan,
                    letterSpacing: 1.0,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Tài Sản Vĩ Mô',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Dễ hiểu – Dễ nhìn – Dễ quyết định',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tab bar selector
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.glassBorder,
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  _buildTabItem('🥇 Vàng', 'gold'),
                  _buildTabItem('🏠 BDS', 'bds'),
                  _buildTabItem('📈 Chứng khoán', 'stock'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 1. Detailed Gauge
            GlassCard(
              glowColor: activeAsset.color,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        activeAsset.gaugeTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: activeAsset.badgeBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          activeAsset.badgeText,
                          style: TextStyle(
                            color: activeAsset.badgeTextColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FomoGauge(value: displayFomoValue, height: 160),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. Pricing Chart Card
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activeAsset.chartTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Period selectors
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['1W', '1M', '3M', '6M', '1Y'].map((p) {
                      final bool isSelected = _selectedPeriod == p;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _selectedPeriod = p;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white.withOpacity(0.08) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? Colors.white.withOpacity(0.12) : Colors.transparent,
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            p,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? AppTheme.textPrimary : AppTheme.textTertiary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // Chart canvas drawing
                  LineChartWidget(
                    data: chartData,
                    color: activeAsset.color,
                    height: 156,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Key Metrics
            const Text(
              '📊 Chỉ số quan trọng',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 1.6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                _buildMetricCard('Giá hiện tại', metrics[0], metrics[1], activeAsset.color, activeAsset.up ? AppTheme.colorSafe : AppTheme.colorDanger),
                _buildMetricCard('Thay đổi 7 ngày', metrics[2], metrics[3], AppTheme.colorSafe, AppTheme.textSecondary),
                _buildMetricCard('Đỉnh 52 tuần', metrics[4], metrics[5], AppTheme.textPrimary, AppTheme.textSecondary),
                _buildMetricCard('Đáy 52 tuần', metrics[6], metrics[7], AppTheme.textPrimary, AppTheme.textSecondary),
              ],
            ),
            const SizedBox(height: 20),

            // 4. Economic indicators
            const Text(
              '🏛️ Chỉ số kinh tế vĩ mô',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildIndicatorCard('📉', 'Lãi suất tiền gửi', 'TB 12 tháng: 5.2%/năm', '5.2%', AppTheme.brandCyan),
                const SizedBox(height: 8),
                _buildIndicatorCard('📊', 'CPI tháng 6', 'Chỉ số giá tiêu dùng', '+3.8%', AppTheme.colorHot),
                const SizedBox(height: 8),
                _buildIndicatorCard('💵', 'Tỷ giá USD/VND', 'Ngân hàng Nhà nước', '25,480', AppTheme.colorSafe),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(String label, String id) {
    final bool isSelected = _selectedAssetId == id;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _selectedAssetId = id;
            _selectedPeriod = '1W'; // Reset period filter
          });
        },
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, String sub, Color valColor, Color subColor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.glassBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.glassBorder,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              color: AppTheme.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: valColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: TextStyle(
              fontSize: 9.0,
              color: subColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicatorCard(String emoji, String title, String desc, String value, Color valColor) {
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
              color: valColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              emoji,
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
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: valColor,
            ),
          ),
        ],
      ),
    );
  }
}
