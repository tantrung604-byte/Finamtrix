import 'package:flutter/material.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/glass_card.dart';
import '../widgets/fomo_gauge.dart';
import '../widgets/sparkline_chart.dart';
import '../models/gold_price_point.dart';
import '../models/usd_rate_point.dart';
import '../models/cpi_point.dart';
import '../models/index_price_point.dart';
import '../models/deposit_rate_point.dart';
import '../services/macro_micro_link_service.dart';
import '../services/gold_price_service.dart';
import '../services/business_metrics_service.dart';
import '../services/stock_index_service.dart';
import '../services/exchange_rate_service.dart';
import '../services/deposit_rate_service.dart';
import '../services/cpi_service.dart';
import '../services/database_helper.dart';

class HomeScreen extends StatefulWidget {
  final Function(int) onNavigateToTab;

  const HomeScreen({
    super.key,
    required this.onNavigateToTab,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Market Data State
  List<GoldPricePoint> _goldHistory = [];
  List<IndexPricePoint> _stockHistory = [];
  final List<double> _usdHistory = [25200.0, 25300.0, 25280.0, 25350.0, 25400.0, 25420.0, 25480.0];
  List<double> _rateHistory = [];
  
  UsdRatePoint? _latestUsd;
  double? _latestRate;
  BankGroupRate? _topBankGroup;
  CpiPoint? _latestCpi;
  double _fomoScore = 42.0;
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Live refresh every 2 minutes while the home screen is open.
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (_) => _loadData(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);

    try {
      final db = await DatabaseHelper.instance.database;

      // Best-effort real-time refresh of commercial-bank rates from WIFEED.
      await DepositRateService.instance.syncDepositRates().catchError((e) {
        print('Home deposit rate sync failed (using cached): $e');
        return 0;
      });

      // 1. Fetch Gold History (Domestic)
      final goldHistory = await GoldPriceService.instance.getStoredHistory(GoldRange.week);
      
      // 2. Fetch Stock History (VN-Index)
      final stockHistory = await StockIndexService.instance.getStoredHistory(IndexRange.week);
      
      // 3. Fetch USD Latest
      final latestUsd = await ExchangeRateService.instance.getLatestStored();
      
      // 4. Fetch Deposit Rate Latest
      final latestRate = await DepositRateService.instance.getAverageRate(durationMonths: 12);

      // 4b. Top commercial-bank (NHTM) group by 12-month rate.
      final bankGroups = await DepositRateService.instance.getBankGroupRates(durationMonths: 12);
      final topBankGroup = bankGroups.isNotEmpty ? bankGroups.first : null;

      // 5. Fetch Latest CPI
      final latestCpi = await CpiService.instance.getLatestCpi();

      // 6. Fetch Global FOMO (using stock as proxy or average)
      final fomoResult = await db.query(
        'fomo_score_daily',
        where: 'asset_type = ?',
        whereArgs: ['stock'], // Use stock FOMO as the primary home gauge
        orderBy: 'date DESC',
        limit: 1,
      );

      // 7. Fetch Rate history for sparkline (12 or 13-month rates over the last week)
      final rateRows = await db.rawQuery(
        'SELECT AVG(value) as avg_value FROM deposit_interest_rate '
        'WHERE (duration_months = 12 OR duration_months = 13) '
        'GROUP BY effective_date ORDER BY effective_date DESC LIMIT 7'
      );
      final rateHistory = rateRows.map((r) => (r['avg_value'] as num).toDouble()).toList().reversed.toList();

      if (mounted) {
        setState(() {
          _goldHistory = goldHistory;
          _stockHistory = stockHistory;
          _latestUsd = latestUsd;
          _latestRate = latestRate;
          _topBankGroup = topBankGroup ?? _topBankGroup;
          _latestCpi = latestCpi;
          _rateHistory = rateHistory;
          if (fomoResult.isNotEmpty) {
            _fomoScore = (fomoResult.first['fomo_score'] as num? ?? 42.0).toDouble();
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      print('HomeScreen load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.brandCyan)));
    }

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(context.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMarketOverview(),
                  const SizedBox(height: 20),
                  _buildQuickStats(),
                  const SizedBox(height: 24),
                  _buildMarketTicker(),
                  const SizedBox(height: 24),
                  _buildBusinessForecastSummary(),
                  const SizedBox(height: 24),
                  _buildAiCmoHighlights(),
                  const SizedBox(height: 24),
                  _buildRecentAlerts(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      floating: true,
      backgroundColor: AppTheme.bgPrimary.withOpacity(0.8),
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
          const SizedBox(width: 10),
          const Text(
            'FINMATRIX',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.textPrimary, letterSpacing: 1),
          ),
        ],
      ),
      actions: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none, color: AppTheme.textPrimary),
              onPressed: () {},
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppTheme.brandRed,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: const Text(
                  '3',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: () => widget.onNavigateToTab(4),
          child: Container(
            margin: const EdgeInsets.only(right: 16, left: 8),
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              gradient: AppTheme.premiumGradient,
              shape: BoxShape.circle,
            ),
            child: const Center(child: Text('T', style: TextStyle(fontWeight: FontWeight.bold))),
          ),
        ),
      ],
    );
  }

  Widget _buildMarketOverview() {
    String fomoLabel = 'ẤM';
    Color fomoColor = AppTheme.brandGold;
    if (_fomoScore < 30) {
      fomoLabel = 'AN TOÀN';
      fomoColor = AppTheme.brandGreen;
    } else if (_fomoScore > 70) {
      fomoLabel = 'NGUY HIỂM';
      fomoColor = Colors.red;
    } else if (_fomoScore > 50) {
      fomoLabel = 'ĐỘT BIẾN';
      fomoColor = Colors.orange;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('THANG ĐO NHIỆT ĐỘ FOMO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.brandCyan, letterSpacing: 1)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: fomoColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Text('⚡ $fomoLabel', style: TextStyle(color: fomoColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            children: [
              FomoGauge(value: _fomoScore, height: 140),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _LegendItem(label: 'An toàn', color: AppTheme.brandGreen),
                  _LegendItem(label: 'Ấm', color: AppTheme.brandGold),
                  _LegendItem(label: 'Đột biến', color: Colors.orange),
                  _LegendItem(label: 'Nguy hiểm', color: Colors.red),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
          child: _QuickStatCard(
            label: 'Fomo: ${_fomoScore.round()}',
            value: 'Vĩ mô',
            color: AppTheme.brandGreen,
            onTap: () => widget.onNavigateToTab(1),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickStatCard(
            label: 'Tăng 12%',
            value: 'DT',
            color: AppTheme.brandCyan,
            onTap: () => widget.onNavigateToTab(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickStatCard(
            label: '5 gợi ý',
            value: 'AI',
            color: AppTheme.brandPurple,
            onTap: () => widget.onNavigateToTab(3),
          ),
        ),
      ],
    );
  }

  Widget _buildMarketTicker() {
    // 1. Gold Ticker Data
    double goldPrice = 0;
    double goldChange = 0;
    if (_goldHistory.isNotEmpty) {
      goldPrice = _goldHistory.last.sell;
      if (_goldHistory.length >= 2) {
        double prev = _goldHistory[_goldHistory.length - 2].sell;
        if (prev > 0) goldChange = ((goldPrice - prev) / prev) * 100;
      }
    }

    // 2. Stock Ticker Data
    double stockPrice = 0;
    double stockChange = 0;
    if (_stockHistory.isNotEmpty) {
      stockPrice = _stockHistory.last.close;
      if (_stockHistory.length >= 2) {
        double prev = _stockHistory[_stockHistory.length - 2].close;
        if (prev > 0) stockChange = ((stockPrice - prev) / prev) * 100;
      }
    }

    // 3. USD Data
    double usdPrice = _latestUsd?.sell ?? 25480;
    
    // 4. Rate Data
    double rateValue = _latestRate ?? 5.2;
    final topGroup = _topBankGroup;
    final String rateName = topGroup != null ? 'LS gửi · ${topGroup.name}' : 'Lãi suất gửi';
    final String rateValueStr = topGroup != null
        ? '${topGroup.ratePct.toStringAsFixed(2)}%'
        : '${rateValue.toStringAsFixed(1)}%';
    final String rateChange = topGroup != null
        ? '${topGroup.durationMonths} tháng · cao nhất'
        : 'TB 12 tháng';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('THỊ TRƯỜNG HÔM NAY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.brandCyan, letterSpacing: 1)),
        const SizedBox(height: 12),
        SizedBox(
          height: 132,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _MarketTickerCard(
                name: 'Vàng SJC',
                price: goldPrice > 0 ? '${(goldPrice / 1e6).toStringAsFixed(1)} tr' : '92.5 tr',
                change: '${goldChange >= 0 ? '+' : ''}${goldChange.toStringAsFixed(1)}%',
                up: goldChange >= 0,
                color: const Color(0xFFFFD54F),
                history: _goldHistory.map((e) => e.sell).toList(),
                onTap: () => widget.onNavigateToTab(1),
              ),
              _MarketTickerCard(
                name: 'VN-Index',
                price: stockPrice > 0 ? _formatFullCurrency(stockPrice) : '1.285',
                change: '${stockChange >= 0 ? '+' : ''}${stockChange.toStringAsFixed(1)}%',
                up: stockChange >= 0,
                color: const Color(0xFF7C4DFF),
                history: _stockHistory.map((e) => e.close).toList(),
                onTap: () => widget.onNavigateToTab(1),
              ),
              _MarketTickerCard(
                name: rateName,
                price: rateValueStr,
                change: rateChange,
                up: true,
                color: const Color(0xFF00B0FF),
                history: _rateHistory,
                onTap: () => widget.onNavigateToTab(1),
              ),
              _MarketTickerCard(
                name: 'USD/VND',
                price: _latestUsd != null ? '${_formatFullCurrency(_latestUsd!.transfer)} - ${_formatFullCurrency(_latestUsd!.sell)} đ' : '${_formatFullCurrency(usdPrice)} đ',
                change: 'Vietcombank',
                up: true,
                color: AppTheme.brandGreen,
                history: _usdHistory,
                onTap: () => widget.onNavigateToTab(1),
              ),
              if (_latestCpi != null)
                _MarketTickerCard(
                  name: 'CPI YoY',
                  price: '${_latestCpi!.cpiYoY?.toStringAsFixed(1)}%',
                  change: 'Tháng ${_latestCpi!.date.split('-')[1]}',
                  up: (_latestCpi!.cpiYoY ?? 0) < 4,
                  color: AppTheme.colorHot,
                  history: const [3.2, 3.4, 3.1, 3.5, 3.8, 3.7, 3.8], // Simple trend line
                  onTap: () => widget.onNavigateToTab(1),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessForecastSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('VI MÔ — DỰ PHÓNG KINH DOANH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.brandCyan, letterSpacing: 1)),
        const SizedBox(height: 12),
        FutureBuilder<BusinessMetrics>(
          future: BusinessMetricsService.instance.loadMetrics(),
          builder: (context, snapshot) {
            final double revenue = snapshot.data?.targetRevenue ?? 0.0;
            final String revenueStr = revenue > 0 ? '${_formatFullCurrency(revenue)} đ' : 'Chưa đặt mục tiêu';
            
            return GestureDetector(
              onTap: () => widget.onNavigateToTab(2),
              child: GlassCard(
                glowColor: AppTheme.brandCyan,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Doanh thu mục tiêu', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Text('$revenueStr / tháng', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.textPrimary)),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text('Xem kế hoạch ngay', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _formatFullCurrency(double number) {
    if (!number.isFinite) return '0';
    return number.round().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  Widget _buildAiCmoHighlights() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('TRỢ LÝ AI CMO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.brandCyan, letterSpacing: 1)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => widget.onNavigateToTab(3),
          child: GlassCard(
            glowColor: AppTheme.brandPurple,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppTheme.brandPurple.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Center(child: Text('🤖', style: TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI CMO gợi ý hôm nay', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.brandPurple)),
                      SizedBox(height: 2),
                      Text('Tạo video "unbox + review thật" lên TikTok để kích đơn tự nhiên', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.textTertiary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentAlerts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CẢNH BÁO GẦN ĐÂY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.brandCyan, letterSpacing: 1)),
        const SizedBox(height: 12),
        // Real macro -> micro alert (USP), falls back gracefully.
        FutureBuilder<MacroMicroImpact>(
          future: MacroMicroLinkService.instance.computeImpact(),
          builder: (context, snapshot) {
            final impact = snapshot.data;
            if (impact != null && impact.hasImpact) {
              final color = impact.severity == MacroImpactSeverity.high
                  ? AppTheme.brandRed
                  : impact.severity == MacroImpactSeverity.medium
                      ? Colors.orange
                      : AppTheme.brandGold;
              return _buildAlertItem(
                '🔗',
                'Vĩ mô → Sức mua ${impact.deltaPct.round()}%',
                impact.message,
                'real-time',
                color,
              );
            }
            return const SizedBox.shrink();
          },
        ),
        // Dynamic Gold Price Alert
        FutureBuilder<List<GoldPricePoint>>(
          future: GoldPriceService.instance.getStoredHistory(GoldRange.week),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
            final points = snapshot.data!;
            final latest = points.last;
            final previous = points.length >= 2 ? points[points.length - 2] : latest;
            final changePct = previous.sell == 0 ? 0.0 : ((latest.sell - previous.sell) / previous.sell) * 100;
            
            // Show alert if there's any significant change (>0.1%)
            if (changePct.abs() < 0.1) return const SizedBox.shrink();

            final title = changePct >= 0 ? 'Giá vàng tăng' : 'Giá vàng giảm';
            final emoji = changePct >= 0 ? '📈' : '📉';
            final color = changePct >= 0 ? Colors.orange : AppTheme.brandGreen;
            final desc = 'SJC ${changePct >= 0 ? 'lên' : 'xuống'} ${_fmtTr(latest.sell)} (${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(1)}%)';

            return _buildAlertItem(emoji, title, desc, 'vừa cập nhật', color);
          },
        ),
        _buildAlertItem('✅', 'Break-even đạt 78%', 'Doanh thu tuần vượt kỳ vọng', '5h trước', AppTheme.brandGreen),
      ],
    );
  }

  String _fmtTr(double vnd) => '${(vnd / 1e6).toStringAsFixed(1)} tr';

  Widget _buildAlertItem(String emoji, String title, String desc, String time, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.glassBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
                Text(desc, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Text(time, style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary)),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendItem({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary)),
      ],
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _QuickStatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketTickerCard extends StatelessWidget {
  final String name;
  final String price;
  final String change;
  final bool up;
  final Color color;
  final List<double> history;
  final VoidCallback onTap;

  const _MarketTickerCard({
    required this.name,
    required this.price,
    required this.change,
    required this.up,
    required this.color,
    required this.history,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardWidth = context.w(150);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.glassBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(price, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
            ),
            const SizedBox(height: 2),
            Text(
              change,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: up ? AppTheme.brandGreen : AppTheme.brandRed),
            ),
            const Spacer(),
            if (history.isNotEmpty)
              SparklineChart(data: history, color: color, width: cardWidth - 24, height: 28),
          ],
        ),
      ),
    );
  }
}
