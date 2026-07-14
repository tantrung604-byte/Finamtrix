import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/glass_card.dart';
import '../widgets/fomo_gauge.dart';
import '../widgets/line_chart_painter.dart';
import '../models/market_data.dart';
import '../services/database_helper.dart';
import '../services/gold_price_service.dart';
import '../services/stock_index_service.dart';
import '../services/exchange_rate_service.dart';
import '../services/deposit_rate_service.dart';
import '../services/cpi_service.dart';
import '../models/usd_rate_point.dart';
import '../models/cpi_point.dart';
import '../models/gold_price_point.dart';
import '../models/deposit_rate_point.dart';

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
  List<String>? _goldMetrics;
  List<String>? _stockMetrics;
  List<String>? _rateMetrics;
  UsdRatePoint? _usdRate;
  double? _depositRatePct;
  List<BankGroupRate> _bankGroupRates = [];
  int _rateTermMonths = 12;
  CpiPoint? _latestCpi;
  List<double> _worldGoldPrices = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _initData();
    // Live refresh every 3 minutes while the screen is open.
    _refreshTimer = Timer.periodic(const Duration(minutes: 3), (_) => _initData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Best-effort: pull up to 1 năm of gold (vang.today) and stock-index (VCI)
  /// history, then load. A single 365-day sync also covers 7/30/90-day windows.
  Future<void> _initData() async {
    await Future.wait([
      GoldPriceService.instance
          .syncGoldHistory(days: 365)
          .catchError((e) {
        print('Gold sync failed (using cached history): $e');
        return 0;
      }),
      StockIndexService.instance
          .syncIndexHistory(days: 365)
          .catchError((e) {
        print('Stock index sync failed (using cached history): $e');
        return 0;
      }),
      _syncUsdRate(),
      // Best-effort: bank deposit rates from WIFEED.
      DepositRateService.instance.syncDepositRates().catchError((e) {
        print('Deposit rate sync failed (using cached): $e');
        return 0;
      }),
      // Best-effort: CPI from WIFEED.
      CpiService.instance.syncCpiHistory().catchError((e) {
        print('CPI sync failed (using cached): $e');
        return 0;
      }),
      // Best-effort: World Gold from vang.today.
      GoldPriceService.instance.syncGoldHistory(type: GoldPriceService.worldType).catchError((e) {
        print('World Gold sync failed (using cached): $e');
        return 0;
      }),
    ]);
    await _loadData();
  }

  /// Best-effort USD/VND sync: seed recent history once, then today's snapshot.
  Future<void> _syncUsdRate() async {
    try {
      await ExchangeRateService.instance.backfillRecentIfEmpty(days: 14);
      await ExchangeRateService.instance.syncTodayRate();
    } catch (e) {
      print('USD rate sync failed (using cached): $e');
    }
  }

  /// Maps the chart period chip to a tracking window in days.
  int _daysForPeriod(String period) {
    switch (period) {
      case '1W':
        return 7;
      case '1M':
        return 30;
      case '3M':
        return 90;
      case '6M':
        return 180;
      case '1Y':
        return 365;
      default:
        return 7;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final db = await DatabaseHelper.instance.database;

      final fomoResult = await db.query(
        'fomo_score_daily',
        where: 'asset_type = ?',
        whereArgs: [_selectedAssetId],
        orderBy: 'date DESC',
        limit: 1,
      );

      // Pull history for the selected tracking window (oldest → newest).
      final days = _daysForPeriod(_selectedPeriod);
      final cutoff = DateTime.now()
          .subtract(Duration(days: days - 1))
          .toIso8601String()
          .split('T')[0];

      List<double> chartPrices = [];
      List<String>? goldMetrics;
      List<String>? stockMetrics;

      if (_selectedAssetId == 'gold') {
        final priceHistory = await db.query(
          'gold_price_daily',
          where: 'date >= ? AND type = ?',
          whereArgs: [cutoff, 'domestic'],
          orderBy: 'date ASC',
        );
        chartPrices =
            priceHistory.map((p) => (p['price_sell'] as num).toDouble()).toList();

        // Full history (up to ~52 weeks) for the "Chỉ số quan trọng" cards.
        final allRows = await db.query(
          'gold_price_daily',
          where: 'type = ?',
          whereArgs: ['domestic'],
          orderBy: 'date ASC',
        );
        goldMetrics = _computeGoldMetrics(allRows);
      } else if (_selectedAssetId == 'stock') {
        final indexHistory = await db.query(
          'market_index_daily',
          where: 'symbol = ? AND date >= ?',
          whereArgs: [StockIndexService.defaultSymbol, cutoff],
          orderBy: 'date ASC',
        );
        chartPrices =
            indexHistory.map((p) => (p['close'] as num).toDouble()).toList();

        final allRows = await db.query(
          'market_index_daily',
          where: 'symbol = ?',
          whereArgs: [StockIndexService.defaultSymbol],
          orderBy: 'date ASC',
        );
        stockMetrics = _computeStockMetrics(allRows);
      } else if (_selectedAssetId == 'rate') {
        // Fetch historical average 12 or 13-month rates (oldest -> newest).
        final rows = await db.rawQuery(
          'SELECT effective_date, AVG(value) as avg_value FROM deposit_interest_rate '
          'WHERE (duration_months = 12 OR duration_months = 13) AND effective_date >= ? '
          'GROUP BY effective_date ORDER BY effective_date ASC',
          [cutoff],
        );
        chartPrices = rows.map((r) => (r['avg_value'] as num).toDouble()).toList();

        final allHistoryRows = await db.rawQuery(
          'SELECT effective_date, AVG(value) as avg_value FROM deposit_interest_rate '
          'WHERE (duration_months = 12 OR duration_months = 13) GROUP BY effective_date ORDER BY effective_date ASC',
        );
        _rateMetrics = _computeRateMetrics(allHistoryRows);
      }

      // Latest USD/VND rate (shown in the macro indicators section).
      final usdRate = await ExchangeRateService.instance.getLatestStored();

      // Latest representative 12-month bank deposit rate (WIFEED).
      final depositRate =
          await DepositRateService.instance.getAverageRate(durationMonths: 12);

      // Per commercial-bank (NHTM) group breakdown for the selected term.
      final bankGroupRates = await DepositRateService.instance
          .getBankGroupRates(durationMonths: _rateTermMonths);

      // Latest CPI (WIFEED).
      final latestCpi = await CpiService.instance.getLatestCpi();

      // World Gold history (vang.today) for indicators section.
      final worldGoldHistory = await GoldPriceService.instance.getStoredHistory(GoldRange.week, dbType: 'world');

      if (mounted) {
        setState(() {
          _dbFomoScore = fomoResult.isNotEmpty ? (fomoResult.first['fomo_score'] as num? ?? 0).toDouble() : 0;
          _dbPrices = chartPrices;
          _goldMetrics = goldMetrics ?? _goldMetrics;
          _stockMetrics = stockMetrics ?? _stockMetrics;
          _usdRate = usdRate ?? _usdRate;
          _depositRatePct = depositRate ?? _depositRatePct;
          _bankGroupRates = bankGroupRates.isNotEmpty ? bankGroupRates : _bankGroupRates;
          _latestCpi = latestCpi ?? _latestCpi;
          _worldGoldPrices = worldGoldHistory.map((p) => p.buy).toList();
          _isLoading = false;
          _lastUpdated = DateTime.now();
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
    
    // Override with DB data
    double displayFomoValue =
        (_selectedAssetId == 'gold' || _selectedAssetId == 'stock' || _selectedAssetId == 'rate') &&
                _dbFomoScore > 0
            ? _dbFomoScore
            : activeAsset.gaugeValue;
    
    final bool hasDbChart =
        (_selectedAssetId == 'gold' || _selectedAssetId == 'stock' || _selectedAssetId == 'rate') &&
            _dbPrices.isNotEmpty;
    List<double> chartData = hasDbChart ? _dbPrices : activeAsset.weekData;

    // Custom metrics details mapping based on selected asset
    Map<String, List<String>> metricsMap = {
      'gold': ['Mua: 91.0 tr - Bán: 92.5 tr', '↑ +1.8%', '+3.2%', '+2.87 triệu', '94.1 tr', '12/05/2026', '78.3 tr', '08/11/2025'],
      'bds': ['68.2 tr/m²', '↓ -0.3%', '+0.5%', '+0.34 triệu', '69.5 tr', '18/02/2026', '62.0 tr', '15/09/2025'],
      'stock': ['1,285', '↑ +0.6%', '+1.2%', '+15.4 điểm', '1,310', '02/04/2026', '1,080', '28/10/2025'],
    };
    final metrics = metricsMap[_selectedAssetId] ?? metricsMap['gold']!;

    // Prefer real metrics computed from stored history (gold: vang.today,
    // stock: VCI/vnstock). Fall back to sample data otherwise.
    List<String> displayMetrics = metrics;
    if (_selectedAssetId == 'gold' && _goldMetrics != null) {
      displayMetrics = _goldMetrics!;
    } else if (_selectedAssetId == 'stock' && _stockMetrics != null) {
      displayMetrics = _stockMetrics!;
    } else if (_selectedAssetId == 'rate' && _rateMetrics != null) {
      displayMetrics = _rateMetrics!;
    }

    return Scaffold(
      body: RefreshIndicator(
        color: AppTheme.brandCyan,
        onRefresh: _initData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: context.pagePadding, vertical: 12.0),
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
            const SizedBox(height: 8),
            _buildLiveBadge(),
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
                  _buildTabItem('📈 CK', 'stock'),
                  _buildTabItem('📉 Lãi suất', 'rate'),
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
                          // Reload chart for the selected tracking window.
                          if (_selectedAssetId == 'gold' ||
                              _selectedAssetId == 'stock') {
                            _loadData();
                          }
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
              childAspectRatio: context.isCompact ? 1.45 : 1.6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                _buildMetricCard('Giá hiện tại', displayMetrics[0], displayMetrics[1], activeAsset.color, activeAsset.up ? AppTheme.colorSafe : AppTheme.colorDanger),
                _buildMetricCard('Thay đổi 7 ngày', displayMetrics[2], displayMetrics[3], AppTheme.colorSafe, AppTheme.textSecondary),
                _buildMetricCard('Đỉnh 52 tuần', displayMetrics[4], displayMetrics[5], AppTheme.textPrimary, AppTheme.textSecondary),
                _buildMetricCard('Đáy 52 tuần', displayMetrics[6], displayMetrics[7], AppTheme.textPrimary, AppTheme.textSecondary),
              ],
            ),
            const SizedBox(height: 20),

            // 3b. Commercial-bank (NHTM) deposit-rate breakdown (rate tab only).
            if (_selectedAssetId == 'rate') ...[
              _buildNhtmBreakdown(),
              const SizedBox(height: 20),
            ],

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
                _buildIndicatorCard(
                  '📉',
                  'Lãi suất tiền gửi',
                  _depositRatePct != null
                      ? 'NHTM • TB 12 tháng (WIFEED)'
                      : 'TB 12 tháng • WIFEED',
                  _depositRatePct != null
                      ? '${_depositRatePct!.toStringAsFixed(2)}%'
                      : '5.2%',
                  AppTheme.brandCyan,
                ),
                const SizedBox(height: 8),
                _buildIndicatorCard(
                  '📊',
                  'CPI ${_latestCpi != null ? _fmtDateMonth(_latestCpi!.date) : 'tháng 6'}',
                  'Chỉ số giá tiêu dùng',
                  _latestCpi != null ? _fmtPct(_latestCpi!.cpiYoY ?? 0) : '+3.8%',
                  AppTheme.colorHot,
                ),
                const SizedBox(height: 8),
                _buildIndicatorCard(
                  '🌐',
                  'Giá vàng thế giới',
                  'XAU/USD • vang.today',
                  _worldGoldPrices.isNotEmpty ? '\$${_fmtIndex(_worldGoldPrices.last)}' : '—',
                  AppTheme.brandCyan,
                ),
                const SizedBox(height: 8),
                _buildIndicatorCard(
                  '💵',
                  'Tỷ giá USD/VND',
                  _usdRate != null
                      ? 'Vietcombank • ${_fmtVnd(_usdRate!.transfer)} Mua - ${_fmtVnd(_usdRate!.sell)} Bán'
                      : 'Vietcombank',
                  _usdRate != null ? _fmtVnd(_usdRate!.sell) : '—',
                  AppTheme.colorSafe,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
    );
  }

  /// Builds the 8 "Chỉ số quan trọng" strings from stored gold history.
  /// Order: [price, priceBadge, change7dPct, change7dAbs, high, highDate, low, lowDate].
  List<String> _computeGoldMetrics(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return ['—', '', '—', '', '—', '', '—', ''];
    }

    final pricesSell = rows.map((r) => (r['price_sell'] as num).toDouble()).toList();
    final pricesBuy = rows.map((r) => (r['price_buy'] as num?)?.toDouble() ?? 0.0).toList();
    final dates = rows.map((r) => r['date'] as String).toList();

    final currentSell = pricesSell.last;
    final currentBuy = pricesBuy.last;

    // Day-over-day change for the current-price badge.
    final prevSell = pricesSell.length >= 2 ? pricesSell[pricesSell.length - 2] : currentSell;
    final dayChangePct = prevSell == 0 ? 0.0 : ((currentSell - prevSell) / prevSell) * 100;

    // 7-day change (fallback to earliest available if < 8 points).
    double change7dAbs = 0;
    double change7dPct = 0;
    if (pricesSell.length >= 8) {
      final p7 = pricesSell[pricesSell.length - 8];
      change7dAbs = currentSell - p7;
      change7dPct = p7 == 0 ? 0 : ((currentSell - p7) / p7) * 100;
    } else if (pricesSell.length >= 2) {
      final p0 = pricesSell.first;
      change7dAbs = currentSell - p0;
      change7dPct = p0 == 0 ? 0 : ((currentSell - p0) / p0) * 100;
    }

    // 52-week (≈ whole stored window) high / low with their dates.
    int hi = 0, lo = 0;
    for (int i = 1; i < pricesSell.length; i++) {
      if (pricesSell[i] > pricesSell[hi]) hi = i;
      if (pricesSell[i] < pricesSell[lo]) lo = i;
    }

    return [
      'Mua: ${_fmtTr(currentBuy)} - Bán: ${_fmtTr(currentSell)}',
      _fmtBadge(dayChangePct),
      _fmtPct(change7dPct),
      _fmtTrieu(change7dAbs),
      _fmtTr(pricesSell[hi]),
      _fmtDate(dates[hi]),
      _fmtTr(pricesSell[lo]),
      _fmtDate(dates[lo]),
    ];
  }

  /// Builds the 8 "Chỉ số quan trọng" strings from stored stock-index history.
  /// Order: [value, valueBadge, change7dPct, change7dDiem, high, highDate, low, lowDate].
  List<String> _computeStockMetrics(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return ['—', '', '—', '', '—', '', '—', ''];
    }

    final closes = rows.map((r) => (r['close'] as num).toDouble()).toList();
    final dates = rows.map((r) => r['date'] as String).toList();

    final current = closes.last;

    final prev = closes.length >= 2 ? closes[closes.length - 2] : current;
    final dayChangePct = prev == 0 ? 0.0 : ((current - prev) / prev) * 100;

    double change7dDiem = 0;
    double change7dPct = 0;
    if (closes.length >= 8) {
      final p7 = closes[closes.length - 8];
      change7dDiem = current - p7;
      change7dPct = p7 == 0 ? 0 : ((current - p7) / p7) * 100;
    } else if (closes.length >= 2) {
      final p0 = closes.first;
      change7dDiem = current - p0;
      change7dPct = p0 == 0 ? 0 : ((current - p0) / p0) * 100;
    }

    int hi = 0, lo = 0;
    for (int i = 1; i < closes.length; i++) {
      if (closes[i] > closes[hi]) hi = i;
      if (closes[i] < closes[lo]) lo = i;
    }

    return [
      _fmtIndex(current),
      _fmtBadge(dayChangePct),
      _fmtPct(change7dPct),
      _fmtDiem(change7dDiem),
      _fmtIndex(closes[hi]),
      _fmtDate(dates[hi]),
      _fmtIndex(closes[lo]),
      _fmtDate(dates[lo]),
    ];
  }

  /// Builds the 8 "Chỉ số quan trọng" strings from stored interest rate history.
  /// Order: [value, valueBadge, change7dPct, changeAbs, high, highDate, low, lowDate].
  List<String> _computeRateMetrics(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return ['—', '', '—', '', '—', '', '—', ''];
    }

    final rates = rows.map((r) => (r['avg_value'] as num).toDouble()).toList();
    final dates = rows.map((r) => r['effective_date'] as String).toList();

    final current = rates.last;
    final prev = rates.length >= 2 ? rates[rates.length - 2] : current;
    final dayChangePct = prev == 0 ? 0.0 : ((current - prev) / prev) * 100;

    double change7dAbs = 0;
    double change7dPct = 0;
    if (rates.length >= 8) {
      final p7 = rates[rates.length - 8];
      change7dAbs = current - p7;
      change7dPct = p7 == 0 ? 0 : ((current - p7) / p7) * 100;
    } else if (rates.length >= 2) {
      final p0 = rates.first;
      change7dAbs = current - p0;
      change7dPct = p0 == 0 ? 0 : ((current - p0) / p0) * 100;
    }

    int hi = 0, lo = 0;
    for (int i = 1; i < rates.length; i++) {
      if (rates[i] > rates[hi]) hi = i;
      if (rates[i] < rates[lo]) lo = i;
    }

    return [
      '${current.toStringAsFixed(2)}%',
      _fmtBadge(dayChangePct),
      _fmtPct(change7dPct),
      '${change7dAbs >= 0 ? '+' : ''}${change7dAbs.toStringAsFixed(2)}%',
      '${rates[hi].toStringAsFixed(2)}%',
      _fmtDate(dates[hi]),
      '${rates[lo].toStringAsFixed(2)}%',
      _fmtDate(dates[lo]),
    ];
  }

  /// Index value → "1,871.91" (thousands separator, 2 decimals).
  String _fmtIndex(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '${buf.toString()}.${parts[1]}';
  }

  /// Index delta → "+15.4 điểm" / "-8.2 điểm".
  String _fmtDiem(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} điểm';

  /// VND amount → "26,454" (thousands separator, no decimals).
  String _fmtVnd(double v) {
    final digits = v.round().abs().toString();
    final buf = StringBuffer(v < 0 ? '-' : '');
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  /// VND → "148.5 tr".
  String _fmtTr(double vnd) => '${(vnd / 1e6).toStringAsFixed(1)} tr';

  /// VND delta → "+2.87 triệu" / "-1.50 triệu".
  String _fmtTrieu(double vnd) {
    final sign = vnd >= 0 ? '+' : '-';
    return '$sign${(vnd.abs() / 1e6).toStringAsFixed(2)} triệu';
  }

  /// Percent → "+3.2%" / "-1.8%".
  String _fmtPct(double pct) =>
      '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%';

  /// Percent with arrow → "↑ +1.8%" / "↓ -0.3%".
  String _fmtBadge(double pct) => '${pct >= 0 ? '↑' : '↓'} ${_fmtPct(pct)}';

  /// ISO "2026-06-28" → "28/06/2026".
  String _fmtDate(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  /// ISO "2026-06-28" → "Tháng 06/2026".
  String _fmtDateMonth(String iso) {
    final parts = iso.split('-');
    if (parts.length < 2) return iso;
    return 'Tháng ${parts[1]}/${parts[0]}';
  }

  Widget _buildNhtmBreakdown() {
    final terms = [6, 12, 24];
    return GlassCard(
      glowColor: AppTheme.brandCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  '🏦 Lãi suất NHTM theo nhóm',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              // Term selector chips (kỳ hạn tháng).
              Row(
                children: terms.map((t) {
                  final bool sel = _rateTermMonths == t;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _rateTermMonths = t);
                      _loadData();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: sel ? AppTheme.brandCyan.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: sel ? AppTheme.brandCyan.withOpacity(0.4) : AppTheme.glassBorder,
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        '${t}T',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: sel ? AppTheme.brandCyan : AppTheme.textTertiary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_bankGroupRates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Đang tải dữ liệu WIFEED…',
                style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
              ),
            )
          else
            ...List.generate(_bankGroupRates.length, (i) {
              final g = _bankGroupRates[i];
              final bool isTop = i == 0;
              return Container(
                margin: EdgeInsets.only(bottom: i == _bankGroupRates.length - 1 ? 0 : 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isTop ? AppTheme.brandCyan.withOpacity(0.06) : AppTheme.glassBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isTop ? AppTheme.brandCyan.withOpacity(0.25) : AppTheme.glassBorder,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            g.banks,
                            style: const TextStyle(
                              fontSize: 10.5,
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
                      '${g.ratePct.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isTop ? AppTheme.brandCyan : AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 8),
          Text(
            'Nguồn: WIFEED • Kỳ hạn $_rateTermMonths tháng'
            '${_bankGroupRates.isNotEmpty ? ' • ${_fmtDate(_bankGroupRates.first.effectiveDate)}' : ''}',
            style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveBadge() {
    final t = _lastUpdated;
    final label = t == null
        ? 'Đang cập nhật realtime…'
        : 'Cập nhật lúc ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')} • tự động mỗi 3 phút';
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(color: AppTheme.colorSafe, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary)),
      ],
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
          if (id == 'gold' || id == 'stock' || id == 'rate') {
            _loadData();
          }
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: valColor,
              ),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 10.5,
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
