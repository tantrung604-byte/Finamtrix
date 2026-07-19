import 'package:sqflite/sqflite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/glass_card.dart';
import '../widgets/projection_chart_painter.dart';
import '../services/database_helper.dart';
import '../services/forecast_service.dart';
import '../services/ai_gateway_service.dart';
import '../services/business_metrics_service.dart';
import '../services/macro_micro_link_service.dart';
import '../services/fastmoss_service.dart';
import '../models/fastmoss_trend.dart';

class MicroScreen extends StatefulWidget {
  const MicroScreen({Key? key}) : super(key: key);

  @override
  State<MicroScreen> createState() => _MicroScreenState();
}

class _MicroScreenState extends State<MicroScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  double _targetRevenue = 200000000.0;
  double _aov = 0;
  double _grossMargin = 0;
  double _fixedCost = 0;
  int _actualOrders = 0;
  
  final TextEditingController _revenueController = TextEditingController();
  final TextEditingController _aovController = TextEditingController();
  final TextEditingController _marginController = TextEditingController();
  final TextEditingController _costController = TextEditingController();
  
  Map<String, dynamic> _forecastData = {};
  bool _isLoading = true;
  List<ScenarioResult> _scenarios = [];
  MacroMicroImpact _macroImpact = MacroMicroImpact.neutral();
  String _aiAdvice = "Vui lòng nhập các chỉ số kinh doanh bên dưới để AI CMO có thể bắt đầu tư vấn dự báo chính xác cho bạn.";
  bool _isAiLoading = false;
  String _selectedCategory = 'Thời trang';
  bool _hasInputData = false;

  List<FastmossProductTrend> _fastmossTrends = [];
  List<FastmossCreatorTrend> _creatorTrends = [];
  FastmossCategorySummary _categorySummary = FastmossCategorySummary.empty;
  bool _fastmossLoading = false;
  int _fastmossPeriod = 7; // 7 or 30 days
  Timer? _fastmossTimer;

  final List<Map<String, String>> _categories = [
    {'name': 'Thời trang', 'emoji': '👕'},
    {'name': 'Du lịch', 'emoji': '✈️'},
    {'name': 'Ăn uống', 'emoji': '🍕'},
    {'name': 'Tiêu dùng', 'emoji': '🛒'},
    {'name': 'Điện tử', 'emoji': '📱'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadForecast();
    // Live refresh FastMoss category trends every 5 minutes while open.
    _fastmossTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _loadFastmossTrends(_selectedCategory),
    );
  }

  Future<void> _loadForecast() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      print('--- MicroScreen: Loading Backend Data ---');
      final db = await DatabaseHelper.instance.database;
      if (!mounted) return;
      final today = DateTime.now().toIso8601String().split('T')[0];
      final yearMonth = today.substring(0, 7);

      final metrics = await BusinessMetricsService.instance.loadMetrics();
      if (!mounted) return;

      print('DB Check: AOV=${metrics.aov}, Margin=${metrics.grossMarginPct}, Revenue=${metrics.targetRevenue}');

      setState(() {
        _aov = metrics.aov;
        _grossMargin = metrics.grossMarginPct;
        _fixedCost = metrics.fixedOperatingCost;
        _targetRevenue = metrics.targetRevenue;
        _hasInputData = metrics.hasInputData;
      });

      final data = await ForecastService.instance.calculateReverseFunnel('default_user', yearMonth, referenceDate: today);
      print('Forecast Service Result: $data');

      final actualOrdersResult = await db.rawQuery(
        '''
        SELECT SUM(ap.actual_orders) as total
        FROM channel_actual_performance ap
        JOIN user_channel_config c ON ap.channel_config_id = c.channel_config_id
        WHERE c.user_id = ? AND ap.record_date LIKE ?
        ''',
        [defaultUserId, '$yearMonth%'],
      );
      final actualOrders = ((actualOrdersResult.first['total'] as num?) ?? 0).toInt();
      
      // Get current user category
      final userResult = await db.query('users', columns: ['business_type'], where: 'user_id = ?', whereArgs: ['default_user']);
      String category = 'Thời trang';
      if (userResult.isNotEmpty && userResult.first['business_type'] != null) {
        category = userResult.first['business_type'] as String;
      }

      // Macro -> Micro purchasing power impact (USP link).
      final macroImpact = await MacroMicroLinkService.instance.computeImpact();
      if (!mounted) return;

      // Real stress-test scenarios derived from the user's actual funnel.
      final scenarios = ForecastService.instance.calculateScenarios(
        baseForecast: data,
        grossMarginPct: metrics.grossMarginPct,
        fixedCost: metrics.fixedOperatingCost,
        demandMultiplier: macroImpact.purchasingPowerFactor,
      );

      if (mounted) {
        setState(() {
          _forecastData = data;
          _selectedCategory = category;
          _actualOrders = actualOrders;
          _macroImpact = macroImpact;
          _scenarios = scenarios;
          _isLoading = false;
        });
        
        if (_hasInputData && data.isNotEmpty) {
          _getAiStrategicAdvice(data);
        } else {
          setState(() {
            _aiAdvice = "Bạn chưa nhập chỉ số AOV và Tỷ suất lợi nhuận. Hãy hoàn thiện 'Cấu hình chỉ số' bên dưới để tôi bắt đầu lập Plan Marketing nhé! 🚀";
          });
        }

        // Load FastMoss category trends for the resolved category.
        _loadFastmossTrends(category);
      }
    } catch (e) {
      print('MicroScreen Backend Error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateBusinessMetrics() async {
    print('Updating Business Metrics in DB...');

    await BusinessMetricsService.instance.saveMetrics(
      aov: _aov,
      grossMarginPct: _grossMargin,
      fixedOperatingCost: _fixedCost,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã cập nhật chỉ số kinh doanh'),
        duration: Duration(seconds: 2),
      ),
    );

    await _loadForecast();
  }

  Future<void> _getAiStrategicAdvice(Map<String, dynamic> data) async {
    setState(() => _isAiLoading = true);

    final s = _categorySummary;
    final marketBlock = s.hasData
        ? '''
- Dữ liệu thị trường TikTok Shop (FastMoss) ngành $_selectedCategory:
  • Tổng doanh thu top sản phẩm: ${_formatFullCurrency(s.totalGmvVnd)} VNĐ
  • Tổng lượt bán: ${s.totalSales} | Giá TB: ${_formatFullCurrency(s.avgPriceVnd)} VNĐ
  • Hoa hồng TB: ${s.avgCommissionPct.toStringAsFixed(0)}% | Tăng trưởng TB: ${s.avgGrowthPct.toStringAsFixed(0)}%'''
        : '';

    final prompt = '''
Dựa trên dữ liệu dự báo kinh doanh B2C sau:
- Ngành hàng: $_selectedCategory
- Doanh thu mục tiêu: ${_formatFullCurrency(_targetRevenue)} VNĐ
- Tổng đơn hàng cần: ${data['total_orders']?.round()} đơn
- Ngân sách Ads dự kiến: ${_formatFullCurrency(data['total_ad_budget'] ?? 0)} VNĐ
- Điểm hòa vốn (Break-even): ${data['break_even_orders']?.round()} đơn$marketBlock

Hãy đưa ra 1 lời khuyên chiến lược marketing ngắn gọn và đặc thù cho ngành $_selectedCategory để đạt được mục tiêu này và tối ưu chi phí Ads. Nếu có dữ liệu thị trường TikTok Shop, hãy tận dụng mức hoa hồng và tăng trưởng để gợi ý kênh Affiliate/KOC phù hợp.
''';

    try {
      final advice = await AiGatewayService.instance.processAiRequest(
        prompt: prompt,
        taskType: 'strategic_analysis',
      );
      if (mounted) {
        setState(() {
          _aiAdvice = advice;
          _isAiLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiAdvice = "Không thể kết nối AI CMO. Hãy kiểm tra cấu hình trong phần Tài khoản.";
          _isAiLoading = false;
        });
      }
    }
  }

  Future<void> _updateTargetRevenue(double newVal) async {
    final db = await DatabaseHelper.instance.database;
    final yearMonth = DateTime.now().toIso8601String().substring(0, 7);
    await db.insert(
      'monthly_target',
      {'user_id': 'default_user', 'year_month': yearMonth, 'target_revenue': newVal},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _loadForecast();
  }

  Future<void> _updateCategory(String category) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'users',
      {'business_type': category},
      where: 'user_id = ?',
      whereArgs: ['default_user'],
    );
    setState(() {
      _selectedCategory = category;
    });
    _loadFastmossTrends(category);
    _getAiStrategicAdvice(_forecastData);
  }

  /// Best-effort: pull TikTok Shop category product + creator trends from
  /// FastMoss (or cached / seeded fallback) for [category] and refresh the UI.
  ///
  /// [force] bypasses the once-per-day API throttle (used by the manual
  /// refresh button); periodic/auto loads leave it false so FastMoss ranking
  /// data (recomputed daily) is fetched at most once per day per category.
  Future<void> _loadFastmossTrends(String category, {bool force = false}) async {
    if (!mounted) return;
    setState(() => _fastmossLoading = true);
    try {
      final period = _fastmossPeriod;
      await FastmossService.instance
          .syncCategoryTrends(category, periodDays: period, force: force);
      await FastmossService.instance
          .syncCreatorTrends(category, periodDays: period, force: force);
      final trends = await FastmossService.instance.getCategoryTrends(category, periodDays: period);
      final creators = await FastmossService.instance.getCreatorTrends(category, periodDays: period);
      final summary = await FastmossService.instance.getCategorySummary(category, periodDays: period);
      if (mounted) {
        setState(() {
          _fastmossTrends = trends;
          _creatorTrends = creators;
          _categorySummary = summary;
          _fastmossLoading = false;
        });
      }
    } catch (e) {
      print('FastMoss trends load error: $e');
      if (mounted) setState(() => _fastmossLoading = false);
    }
  }

  void _showEditMetricsDialog() {
    _aovController.text = _aov.round().toString();
    _marginController.text = _grossMargin.round().toString();
    _costController.text = _fixedCost.round().toString();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Cấu hình Chỉ số Kinh doanh',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInputField('Giá trị đơn TB (AOV) - VNĐ', _aovController, 'VD: 500000'),
                const SizedBox(height: 16),
                _buildInputField('Tỷ suất Lợi nhuận gộp (%)', _marginController, 'VD: 45'),
                const SizedBox(height: 16),
                _buildInputField('Chi phí vận hành cố định - VNĐ', _costController, 'VD: 15000000'),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Hủy', style: TextStyle(color: AppTheme.textSecondary)),
              onPressed: () => Navigator.of(context).pop(),
            ),
              ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandCyan,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Lưu chỉ số', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () async {
                final double? aov = double.tryParse(_aovController.text.trim());
                final double? margin = double.tryParse(_marginController.text.trim());
                final double? cost = double.tryParse(_costController.text.trim());

                if (aov == null || margin == null || cost == null || aov <= 0 || margin <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Vui lòng nhập đầy đủ số hợp lệ (AOV > 0, Margin > 0)')),
                  );
                  return;
                }

                setState(() {
                  _aov = aov;
                  _grossMargin = margin;
                  _fixedCost = cost;
                  _hasInputData = true;
                });

                Navigator.of(context).pop();
                await _updateBusinessMetrics();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.textTertiary),
            filled: true,
            fillColor: Colors.white.withOpacity(0.04),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _fastmossTimer?.cancel();
    _tabController.dispose();
    _revenueController.dispose();
    _aovController.dispose();
    _marginController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _showEditRevenueDialog() {
    _revenueController.text = _targetRevenue.round().toString();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Mục tiêu Doanh thu',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nhập doanh thu mục tiêu hàng tháng (VND):',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _revenueController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Ví dụ: 200000000',
                  hintStyle: const TextStyle(color: AppTheme.textTertiary),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.brandCyan),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Hủy', style: TextStyle(color: AppTheme.textSecondary)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandCyan,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cập nhật', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () async {
                final double? newVal = double.tryParse(_revenueController.text);
                if (newVal != null && newVal > 0) {
                  await _updateTargetRevenue(newVal);
                }
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  String _formatNumber(double number) {
    if (!number.isFinite) return '0';
    
    // Billion case
    if (number >= 1000000000) {
      double bil = number / 1000000000;
      if (bil % 1 == 0) return '${bil.round()} tỷ';
      
      // Handle cases like 1 tỷ 200 (optional, but keeping it simple for now)
      return '${bil.toStringAsFixed(1)} tỷ';
    } 
    
    // Million case
    if (number >= 1000000) {
      int mil = (number / 1000000).floor();
      int remainderK = ((number % 1000000) / 1000).round();
      
      if (remainderK == 0) {
        return '$mil triệu';
      } else {
        // e.g., 14tr300
        return '${mil}tr${remainderK.toString().padLeft(3, '0').replaceAll(RegExp(r'0+$'), '')}';
      }
    } 
    
    // Thousand case
    if (number >= 1000) {
      double k = number / 1000;
      return k % 1 == 0 ? '${k.round()}K' : '${k.toStringAsFixed(1)}K';
    }
    
    return number.round().toString();
  }

  String _formatFullCurrency(double number) {
    if (!number.isFinite) return '0';
    return number.round().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.brandCyan)));
    }

    final double totalAdOrders = (_forecastData['total_orders'] as num?)?.toDouble() ?? 0.0;
    final double organicOrders = (_forecastData['organic_orders'] as num?)?.toDouble() ?? 0.0;
    final double totalRequiredOrders = (_forecastData['total_required_orders'] as num?)?.toDouble() ?? 0.0;
    
    // For demo, still using benchmarks for clicks/reach based on AD-DRIVEN orders only
    final double computedClicks = totalAdOrders / 0.032;
    final double computedReach = computedClicks / 0.025;
    
    // Break-even logic from DB
    final double rawBreakEven = (_forecastData['break_even_orders'] as num?)?.toDouble() ?? 0.0;
    final double breakEvenOrders = rawBreakEven.isFinite ? rawBreakEven : 0.0;
    final bool breakEvenPossible = (_forecastData['break_even_possible'] as bool?) ?? (breakEvenOrders > 0);
    final double contributionPerOrder = (_forecastData['contribution_per_order'] as num?)?.toDouble() ?? 0.0;
    final bool hasForecast = _forecastData.isNotEmpty && totalRequiredOrders > 0;
    final int currentDoneOrders = _actualOrders;
    final double beProgress = breakEvenOrders > 0 ? (currentDoneOrders / breakEvenOrders).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: context.pagePadding, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DỰ PHÓNG KHỞI NGHIỆP',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brandCyan,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Kinh Doanh B2C',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.brandCyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.brandCyan.withOpacity(0.2)),
                  ),
                  child: Text(
                    _selectedCategory,
                    style: const TextStyle(color: AppTheme.brandCyan, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Macro -> Micro impact banner (USP)
            if (_macroImpact.hasImpact) ...[
              _buildMacroImpactBanner(),
              const SizedBox(height: 16),
            ],

            // Category Selector
            const Text(
              '🏷️ Chọn ngành hàng',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _selectedCategory == cat['name'];
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _updateCategory(cat['name']!);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.brandCyan.withOpacity(0.2) : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? AppTheme.brandCyan.withOpacity(0.4) : Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(cat['emoji']!, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            cat['name']!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // 0.5 FastMoss category trends (TikTok Shop market data)
            _buildFastmossTrendsSection(),
            const SizedBox(height: 20),

            // 1. Revenue Target Card
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showEditRevenueDialog();
              },
              child: GlassCard(
                glowColor: AppTheme.brandCyan,
                child: Column(
                  children: [
                    const Text(
                      'Doanh thu mục tiêu',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _formatFullCurrency(_targetRevenue),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.brandCyan,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'đ / tháng',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildQuickAction('Sửa mục tiêu', Icons.edit_outlined, _showEditRevenueDialog),
                        const SizedBox(width: 12),
                        _buildQuickAction('Sửa chỉ số (AOV/Margin)', Icons.settings_outlined, _showEditMetricsDialog),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 1.5 AI Strategic Advice Card
            const Text(
              '🤖 CMO Marketing Tư Vấn',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            GlassCard(
              glowColor: AppTheme.brandPurple,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.brandPurple.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Text('🤖', style: TextStyle(fontSize: 16)),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Chiến lược tăng trưởng',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (_isAiLoading)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brandPurple),
                        )
                      else
                        GestureDetector(
                          onTap: () => _getAiStrategicAdvice(_forecastData),
                          child: const Icon(Icons.refresh, size: 16, color: AppTheme.textTertiary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _aiAdvice,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textPrimary,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. Kế hoạch
            const Text(
              '🔄 Kế hoạch',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nhập doanh thu mục tiêu → Tự động phân bổ ngân sách theo benchmark thực tế',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFunnelStep(
                    emoji: '🎯',
                    title: 'Doanh thu mục tiêu',
                    subtitle: 'Revenue Target',
                    value: _formatNumber(_targetRevenue),
                    color: AppTheme.brandCyan,
                  ),
                  _buildFunnelConnector(),
                  _buildFunnelStep(
                    emoji: '👁️',
                    title: 'Reach cần đạt',
                    subtitle: 'Lượt tiếp cận / tháng',
                    value: _formatNumber(computedReach),
                    color: AppTheme.brandPurple,
                  ),
                  _buildFunnelConnector(),
                  _buildFunnelStep(
                    emoji: '🖱️',
                    title: 'Click / Lead',
                    subtitle: 'CTR ≈ 2.5%',
                    value: _formatNumber(computedClicks),
                    color: AppTheme.colorWarm,
                  ),
                  _buildFunnelConnector(),
                  _buildFunnelStep(
                    emoji: '💰',
                    title: 'Đơn hàng từ quảng cáo',
                    subtitle: 'CR ≈ 3.2%',
                    value: '${_formatNumber(totalAdOrders)} đơn',
                    color: AppTheme.colorSafe,
                  ),
                  if (organicOrders > 0.5) ...[
                    _buildFunnelConnector(),
                    _buildFunnelStep(
                      emoji: '🌿',
                      title: 'Đơn hàng tự nhiên',
                      subtitle: 'Organic / Không tốn phí',
                      value: '${_formatNumber(organicOrders)} đơn',
                      color: AppTheme.brandCyan,
                    ),
                  ],
                  _buildFunnelConnector(),
                  _buildFunnelStep(
                    emoji: '💳',
                    title: 'Tổng đơn hàng mục tiêu',
                    subtitle: 'Đơn quảng cáo + Tự nhiên',
                    value: '${_formatNumber(totalRequiredOrders)} đơn',
                    color: Colors.white,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Ads Budget Allocation
            const Text(
              '💸 Phân bổ ngân sách Ads',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            _buildBudgetAllocationCard(),
            const SizedBox(height: 20),

            // 4. Break-even Tracker
            const Text(
              '📏 Vạch Sống Sót (Break-even)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            GlassCard(
              child: !hasForecast
                  ? const Text(
                      'Nhập Doanh thu mục tiêu, AOV và Tỷ suất lợi nhuận ở "Sửa chỉ số" để tính điểm hòa vốn.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                    )
                  : !breakEvenPossible
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('⚠️', style: TextStyle(fontSize: 16)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Không thể hòa vốn với cấu hình hiện tại',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.colorDanger,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Mỗi đơn đang lỗ ${_formatNumber(contributionPerOrder.abs())}đ (lợi nhuận gộp không bù nổi chi phí Ads). '
                              'Tăng Tỷ suất lợi nhuận / giảm tỷ lệ chi phí Ads để mỗi đơn có lãi đóng góp dương.',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Cần bán để hòa vốn',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  '${breakEvenOrders.round()} đơn',
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.colorSafe,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Lãi đóng góp ${_formatNumber(contributionPerOrder)}đ/đơn | Định phí ${_formatNumber(_fixedCost)} | Margin ${_grossMargin.round()}%',
                              style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary),
                            ),
                            const SizedBox(height: 12),
                            // Progress Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                height: 10,
                                child: LinearProgressIndicator(
                                  value: beProgress,
                                  backgroundColor: Colors.white.withOpacity(0.06),
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.colorWarm),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('$currentDoneOrders đơn', style: const TextStyle(fontSize: 9.5, color: AppTheme.textTertiary)),
                                Text(
                                  'Tiến độ: ${(beProgress * 100).round()}%',
                                  style: const TextStyle(fontSize: 10.5, color: AppTheme.colorWarm, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Hòa vốn: ${breakEvenOrders.round()}',
                                  style: const TextStyle(fontSize: 9.5, color: AppTheme.textTertiary),
                                ),
                              ],
                            ),
                          ],
                        ),
            ),
            const SizedBox(height: 20),

            // 5. Stress Test 3 Scenarios
            const Text(
              '🧪 Stress-Test 3 Kịch Bản',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Giả lập "Tươi sáng – Thực tế – Thủng phễu" để bạn chủ động phòng thủ dòng tiền',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  _buildScenarioRow(),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 6. Projection chart
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📈 Dự phóng doanh thu 6 tháng',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ProjectionChart(
                    height: 172,
                    optimistic: _projectionFor('optimistic'),
                    realistic: _projectionFor('realistic'),
                    pessimistic: _projectionFor('pessimistic'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFastmossTrendsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '🔥 Xu hướng ngành hàng',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            if (_fastmossLoading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.colorHot),
              )
            else
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _loadFastmossTrends(_selectedCategory, force: true);
                },
                child: const Icon(Icons.refresh, size: 16, color: AppTheme.textTertiary),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Top 30 sản phẩm TikTok Shop đang bán chạy nhất trong ngành "$_selectedCategory"',
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 8),
        // Period filter (7 / 30 ngày).
        Row(
          children: [
            _buildPeriodChip('7 ngày', 7),
            const SizedBox(width: 8),
            _buildPeriodChip('30 ngày', 30),
          ],
        ),
        const SizedBox(height: 10),
        // Category Doanh thu summary (feeds funnel/budget sizing).
        if (_categorySummary.hasData) ...[
          _buildCategorySummaryCard(),
          const SizedBox(height: 10),
        ],
        GlassCard(
          glowColor: AppTheme.colorHot,
          child: _fastmossTrends.isEmpty
              ? Text(
                  _fastmossLoading
                      ? 'Đang tải dữ liệu thị trường…'
                      : 'Chưa có dữ liệu. Vui lòng thử lại sau.',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                )
              : Column(
                  children: [
                    for (int i = 0; i < _fastmossTrends.length && i < 30; i++) ...[
                      _buildFastmossRow(i + 1, _fastmossTrends[i]),
                      if (i < _fastmossTrends.length - 1 && i < 29)
                        Divider(color: Colors.white.withOpacity(0.05), height: 16),
                    ],
                  ],
                ),
        ),
        // Trending creators / videos.
        if (_creatorTrends.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🎬 Creator & video dẫn dắt ngành',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              Text(
                '${_creatorTrends.length} nhà sáng tạo',
                style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 155,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _creatorTrends.length > 30 ? 30 : _creatorTrends.length,
              itemBuilder: (context, i) => _buildCreatorCard(_creatorTrends[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPeriodChip(String label, int days) {
    final bool sel = _fastmossPeriod == days;
    return GestureDetector(
      onTap: () {
        if (_fastmossPeriod == days) return;
        HapticFeedback.lightImpact();
        setState(() => _fastmossPeriod = days);
        _loadFastmossTrends(_selectedCategory);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? AppTheme.colorHot.withOpacity(0.15) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel ? AppTheme.colorHot.withOpacity(0.4) : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            color: sel ? AppTheme.colorHot : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySummaryCard() {
    final s = _categorySummary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.brandCyan.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandCyan.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, size: 18, color: AppTheme.brandCyan),
              const SizedBox(width: 8),
              const Text('Quy mô thị trường ngành',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (s.avgGrowthPct >= 0 ? AppTheme.colorSafe : AppTheme.colorDanger).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${s.avgGrowthPct >= 0 ? '↑' : '↓'} ${s.avgGrowthPct.abs().toStringAsFixed(0)}% TB',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: s.avgGrowthPct >= 0 ? AppTheme.colorSafe : AppTheme.colorDanger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 2x2 Grid for Metrics
          Row(
            children: [
              Expanded(child: _buildProfessionalMetric('Tổng doanh thu', _formatNumber(s.totalGmvVnd), Icons.monetization_on_outlined, AppTheme.brandCyan)),
              Expanded(child: _buildProfessionalMetric('Lượt bán', _formatNumber(s.totalSales.toDouble()), Icons.shopping_cart_outlined, AppTheme.colorWarm)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildProfessionalMetric('Giá TB', '${_formatNumber(s.avgPriceVnd)}đ', Icons.sell_outlined, AppTheme.textPrimary)),
              Expanded(child: _buildProfessionalMetric('Hoa hồng', '${s.avgCommissionPct.toStringAsFixed(0)}%', Icons.percent_outlined, AppTheme.colorSafe)),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('💡 ', style: TextStyle(fontSize: 14)),
              Expanded(
                child: Text(
                  'Gợi ý: giá bán quanh ${_formatNumber(s.avgPriceVnd)}đ; hoa hồng ~${s.avgCommissionPct.toStringAsFixed(0)}% đủ hấp dẫn KOC. Dùng số này để đặt AOV & phân bổ ngân sách Affiliate.',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Apply category Doanh thu → monthly revenue target (1% market share).
          GestureDetector(
            onTap: () => _applyGmvToTarget(s),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.brandCyan.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '🎯 Áp 1% thị phần → Mục tiêu ${_formatNumber(s.monthlyGmvVnd * 0.01)}/tháng',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfessionalMetric(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 9, color: AppTheme.textTertiary)),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ],
    );
  }

  /// Sets the monthly revenue target to 1% of the category's 30-day Doanh thu.
  Future<void> _applyGmvToTarget(FastmossCategorySummary s) async {
    HapticFeedback.mediumImpact();
    final suggested = (s.monthlyGmvVnd * 0.01).roundToDouble();
    if (suggested <= 0) return;
    await _updateTargetRevenue(suggested);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Đã đặt mục tiêu ${_formatFullCurrency(suggested)}đ/tháng '
          '(1% doanh thu ngành ${s.category}, kỳ $_fastmossPeriod ngày quy đổi tháng).',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }


  Widget _buildCreatorCard(FastmossCreatorTrend c) {
    return Container(
      width: 180,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.glassBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.brandPurple.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brandPurple.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Text('👤', style: TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.creatorName,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${_formatNumber(c.followers.toDouble())} follow',
                        style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            c.videoTitle ?? 'Video nổi bật',
            style: const TextStyle(fontSize: 10.5, color: AppTheme.textPrimary, height: 1.3),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text('▶ ${_formatNumber(c.views.toDouble())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5, color: AppTheme.textSecondary)),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text('Doanh thu ${_formatNumber(c.gmvVnd)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.brandCyan)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text('❤️ Tương tác ${c.engagementPct.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 9, color: AppTheme.colorHot, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildFastmossRow(int rank, FastmossProductTrend t) {
    final bool up = t.growthPct >= 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: rank == 1 ? AppTheme.colorHot.withOpacity(0.18) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: rank == 1 ? AppTheme.colorHot : AppTheme.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.productName,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${t.shopName ?? 'Shop'} • ${_formatNumber(t.priceVnd)}đ • HH ${t.commissionPct.round()}%',
                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Doanh thu ${_formatNumber(t.gmvVnd)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.brandCyan),
            ),
            const SizedBox(height: 2),
            Text(
              '${up ? '↑' : '↓'} ${t.growthPct.abs().toStringAsFixed(0)}% • ${_formatNumber(t.sales.toDouble())} bán',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: up ? AppTheme.colorSafe : AppTheme.colorDanger,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickAction(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppTheme.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetAllocationCard() {
    final channels = _getBudgetForecastChannels();
    final displayChannels = channels.isNotEmpty ? channels : _getAllForecastChannels();
    final totalAdBudget = (_forecastData['total_ad_budget'] as num?)?.toDouble() ?? 0;

    return GlassCard(
      child: displayChannels.isEmpty
          ? const Text(
              'Chưa có kênh active để tính phân bổ ngân sách.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            )
          : Column(
              children: [
                for (int i = 0; i < displayChannels.length; i++) ...[
                  _buildBudgetRow(
                    _channelEmoji(displayChannels[i]['channel_key'] as String? ?? ''),
                    (displayChannels[i]['label'] as String?) ??
                        (displayChannels[i]['channel_key'] as String?) ??
                        'Kênh',
                    totalAdBudget > 0
                        ? (((displayChannels[i]['ad_budget'] as num?)?.toDouble() ?? 0) / totalAdBudget)
                        : 0,
                    _channelColor(displayChannels[i]['channel_key'] as String? ?? ''),
                  ),
                  if (i < displayChannels.length - 1) const SizedBox(height: 14),
                ],
              ],
            ),
    );
  }

  List<Map<String, dynamic>> _getBudgetForecastChannels() {
    final channels = _forecastData['channels'];
    if (channels is! List) return const [];

    return channels
        .whereType<Map>()
        .map((channel) => Map<String, dynamic>.from(channel))
        .where((channel) => ((channel['ad_budget'] as num?)?.toDouble() ?? 0) > 0)
        .toList();
  }

  List<Map<String, dynamic>> _getAllForecastChannels() {
    final channels = _forecastData['channels'];
    if (channels is! List) return const [];

    return channels
        .whereType<Map>()
        .map((channel) => Map<String, dynamic>.from(channel))
        .toList();
  }

  String _channelEmoji(String channelKey) {
    switch (channelKey) {
      case 'facebook_ads':
        return '📘';
      case 'tiktok_ads':
        return '🎵';
      case 'google_ads':
        return '🔍';
      default:
        return '📊';
    }
  }

  Color _channelColor(String channelKey) {
    switch (channelKey) {
      case 'facebook_ads':
        return AppTheme.brandCyan;
      case 'tiktok_ads':
        return AppTheme.colorHot;
      case 'google_ads':
        return AppTheme.colorSafe;
      default:
        return AppTheme.brandPurple;
    }
  }

  Widget _buildFunnelStep({
    required String emoji,
    required String title,
    required String subtitle,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFunnelConnector() {
    return Container(
      margin: const EdgeInsets.only(left: 28),
      height: 14,
      width: 1.5,
      color: Colors.white.withOpacity(0.12),
    );
  }

  Widget _buildBudgetRow(String icon, String name, double pct, Color color) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(icon, style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                  Text(
                    '${(pct * 100).round()}%',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: color),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 6,
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: Colors.white.withOpacity(0.04),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Stress-test scenario helpers ---

  static const Map<String, Map<String, dynamic>> _scenarioMeta = {
    'optimistic': {'emoji': '☀️', 'color': AppTheme.colorSafe},
    'realistic': {'emoji': '⚡', 'color': AppTheme.colorWarm},
    'pessimistic': {'emoji': '🌧️', 'color': AppTheme.colorDanger},
  };

  List<double>? _projectionFor(String key) {
    if (_scenarios.isEmpty) return null;
    final match = _scenarios.where((s) => s.key == key);
    if (match.isEmpty) return null;
    // Convert raw VND to millions for a readable chart scale.
    return match.first.projection.map((v) => v / 1000000).toList();
  }

  Widget _buildScenarioRow() {
    if (_scenarios.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: const Text(
          'Nhập AOV & Tỷ suất lợi nhuận ở "Sửa chỉ số" để chạy stress-test thật.',
          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
        ),
      );
    }

    return Row(
      children: [
        for (int i = 0; i < _scenarios.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _buildScenarioCard(_scenarios[i])),
        ],
      ],
    );
  }

  Widget _buildScenarioCard(ScenarioResult s) {
    final meta = _scenarioMeta[s.key] ?? {'emoji': '📊', 'color': AppTheme.brandPurple};
    final Color color = meta['color'] as Color;
    final String emoji = meta['emoji'] as String;
    final String deltaStr = '${s.deltaPct >= 0 ? '+' : ''}${s.deltaPct.round()}%';
    final bool aboveBreakEven = s.breakEvenGap >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 6),
          Text(
            s.name,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(s.sub, style: const TextStyle(fontSize: 8.5, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Text(
            deltaStr,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            'LN ${_formatNumber(s.netProfit)}',
            style: const TextStyle(fontSize: 8.5, color: AppTheme.textTertiary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            aboveBreakEven
                ? '+${_formatNumber(s.breakEvenGap)} đơn'
                : '${_formatNumber(s.breakEvenGap)} đơn',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              color: aboveBreakEven ? AppTheme.colorSafe : AppTheme.colorDanger,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMacroImpactBanner() {
    final Color color = _macroImpact.severity == MacroImpactSeverity.high
        ? AppTheme.colorDanger
        : _macroImpact.severity == MacroImpactSeverity.medium
            ? AppTheme.colorHot
            : AppTheme.colorWarm;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('🔗', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Liên kết Vĩ mô → Vi mô',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Sức mua ${_macroImpact.deltaPct.round()}%',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _macroImpact.message,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
