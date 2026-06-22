import 'package:sqflite/sqflite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/projection_chart_painter.dart';
import '../services/database_helper.dart';
import '../services/forecast_service.dart';
import '../services/ai_gateway_service.dart';

class MicroScreen extends StatefulWidget {
  const MicroScreen({Key? key}) : super(key: key);

  @override
  State<MicroScreen> createState() => _MicroScreenState();
}

class _MicroScreenState extends State<MicroScreen> {
  double _targetRevenue = 200000000.0;
  double _aov = 0;
  double _grossMargin = 0;
  double _fixedCost = 0;
  
  final TextEditingController _revenueController = TextEditingController();
  final TextEditingController _aovController = TextEditingController();
  final TextEditingController _marginController = TextEditingController();
  final TextEditingController _costController = TextEditingController();
  
  Map<String, dynamic> _forecastData = {};
  bool _isLoading = true;
  String _aiAdvice = "Vui lòng nhập các chỉ số kinh doanh bên dưới để AI CMO có thể bắt đầu tư vấn dự báo chính xác cho bạn.";
  bool _isAiLoading = false;
  String _selectedCategory = 'Thời trang';
  bool _hasInputData = false;

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
    _loadForecast();
  }

  Future<void> _loadForecast() async {
    setState(() => _isLoading = true);
    try {
      print('--- MicroScreen: Loading Backend Data ---');
      final db = await DatabaseHelper.instance.database;
      final today = DateTime.now().toIso8601String().split('T')[0];
      final yearMonth = today.substring(0, 7);

      // --- CRITICAL: Ensure User Exists ---
      final userCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM users WHERE user_id = ?', ['default_user']));
      if (userCount == 0) {
        print('Seed: Creating default user...');
        await db.insert('users', {
          'user_id': 'default_user',
          'phone_or_email': 'user@example.com',
          'display_name': 'Tantr',
          'subscription_tier': 'premium',
        });
      }

      // --- CRITICAL: Ensure Master Data Exists (for Joins) ---
      final channelMasterCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sales_channel'));
      if (channelMasterCount == 0) {
        print('Seed: Re-seeding Master Channels...');
        await db.insert('sales_channel', {'channel_key': 'tiktok_ads', 'display_name': 'TikTok Ads', 'channel_type': 'paid_channel', 'has_benchmark': 1, 'is_system_default': 1});
        await db.insert('sales_channel', {'channel_key': 'facebook_ads', 'display_name': 'Facebook Ads', 'channel_type': 'paid_channel', 'has_benchmark': 1, 'is_system_default': 1});
        await db.insert('sales_channel', {'channel_key': 'google_ads', 'display_name': 'Google Ads', 'channel_type': 'paid_channel', 'has_benchmark': 1, 'is_system_default': 1});
      }

      // --- Robust Initialization (Seed if configs empty) ---
      final configCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM user_channel_config WHERE user_id = ?', ['default_user']));
      if (configCount == 0) {
        print('Seed: Initializing default B2C backend data...');
        await db.insert('business_profile', {
          'user_id': 'default_user',
          'effective_from': '2020-01-01',
          'gross_margin_pct': 45.0,
          'fixed_operating_cost': 15000000.0,
        });
        await db.insert('monthly_target', {
          'user_id': 'default_user',
          'year_month': yearMonth,
          'target_revenue': 200000000.0,
        });
        await db.insert('user_channel_config', {
          'channel_config_id': 'default_config',
          'user_id': 'default_user',
          'channel_key': 'tiktok_ads',
          'effective_from': '2020-01-01',
          'revenue_share_pct': 100.0,
          'user_aov': 500000.0,
          'user_ad_cost_ratio': 25.0,
        });
      }

      // 1. Get Profile data
      final profile = await db.query('business_profile', where: 'user_id = ? AND effective_from <= ?', whereArgs: ['default_user', today], orderBy: 'effective_from DESC', limit: 1);
      
      // 2. Get Target data
      final target = await db.query('monthly_target', where: 'user_id = ? AND year_month = ?', whereArgs: ['default_user', yearMonth]);

      // 3. Get Channel data (for AOV)
      final channels = await db.query('user_channel_config', where: 'user_id = ? AND effective_from <= ?', whereArgs: ['default_user', today], orderBy: 'effective_from DESC', limit: 1);

      print('DB Check: Profile(${profile.length}), Target(${target.length}), Channels(${channels.length})');

      if (profile.isNotEmpty && target.isNotEmpty && channels.isNotEmpty) {
        final double currentAov = (channels.first['user_aov'] as num).toDouble();
        final double currentMargin = (profile.first['gross_margin_pct'] as num).toDouble();
        final double currentRevenue = (target.first['target_revenue'] as num).toDouble();
        final double currentCost = (profile.first['fixed_operating_cost'] as num ?? 0).toDouble();

        print('Loaded Metrics: AOV=$currentAov, Margin=$currentMargin, Revenue=$currentRevenue');
        
        setState(() {
          _aov = currentAov;
          _grossMargin = currentMargin;
          _fixedCost = currentCost;
          _targetRevenue = currentRevenue;
          _hasInputData = _aov > 0 && _grossMargin > 0;
        });
      }

      final data = await ForecastService.instance.calculateReverseFunnel('default_user', yearMonth, referenceDate: today);
      print('Forecast Service Result: $data');
      
      // Get current user category
      final userResult = await db.query('users', columns: ['business_type'], where: 'user_id = ?', whereArgs: ['default_user']);
      String category = 'Thời trang';
      if (userResult.isNotEmpty && userResult.first['business_type'] != null) {
        category = userResult.first['business_type'] as String;
      }

      if (mounted) {
        setState(() {
          _forecastData = data;
          _selectedCategory = category;
          _isLoading = false;
        });
        
        if (_hasInputData && data.isNotEmpty) {
          _getAiStrategicAdvice(data);
        } else {
          setState(() {
            _aiAdvice = "Bạn chưa nhập chỉ số AOV và Tỷ suất lợi nhuận. Hãy hoàn thiện 'Cấu hình chỉ số' bên dưới để tôi bắt đầu lập Plan Marketing nhé! 🚀";
          });
        }
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
    final db = await DatabaseHelper.instance.database;
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    print('Updating Business Metrics in DB (Point-in-time pattern)...');
    
    // 1. Update Profile (New history entry)
    await db.insert('business_profile', {
      'user_id': 'default_user',
      'effective_from': today,
      'gross_margin_pct': _grossMargin,
      'fixed_operating_cost': _fixedCost,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // 2. Update Channels (New history entry for point-in-time)
    final existingConfigs = await db.query('user_channel_config', where: 'user_id = ?', whereArgs: ['default_user']);
    for (var config in existingConfigs) {
      await db.insert('user_channel_config', {
        'channel_config_id': '${config['channel_key']}_$today',
        'user_id': 'default_user',
        'channel_key': config['channel_key'],
        'effective_from': today,
        'revenue_share_pct': config['revenue_share_pct'],
        'user_aov': _aov, // Apply new AOV
        'user_ad_cost_ratio': config['user_ad_cost_ratio'],
        'is_active': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await _loadForecast();
  }

  Future<void> _getAiStrategicAdvice(Map<String, dynamic> data) async {
    setState(() => _isAiLoading = true);
    
    final prompt = '''
Dựa trên dữ liệu dự báo kinh doanh B2C sau:
- Ngành hàng: $_selectedCategory
- Doanh thu mục tiêu: ${_formatFullCurrency(_targetRevenue)} VNĐ
- Tổng đơn hàng cần: ${data['total_orders']?.round()} đơn
- Ngân sách Ads dự kiến: ${_formatFullCurrency(data['total_ad_budget'] ?? 0)} VNĐ
- Điểm hòa vốn (Break-even): ${data['break_even_orders']?.round()} đơn

Hãy đưa ra 1 lời khuyên chiến lược marketing ngắn gọn và đặc thù cho ngành $_selectedCategory để đạt được mục tiêu này và tối ưu chi phí Ads.
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
    _getAiStrategicAdvice(_forecastData);
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
                final double? aov = double.tryParse(_aovController.text);
                final double? margin = double.tryParse(_marginController.text);
                final double? cost = double.tryParse(_costController.text);

                if (aov != null && margin != null && cost != null) {
                  setState(() {
                    _aov = aov;
                    _grossMargin = margin;
                    _fixedCost = cost;
                  });
                  await _updateBusinessMetrics();
                }
                Navigator.of(context).pop();
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
    if (number >= 1000000) {
      double mil = number / 1000000;
      return mil % 1 == 0 ? '${mil.round()}tr' : '${mil.toStringAsFixed(1)}tr';
    } else if (number >= 1000) {
      double k = number / 1000;
      return k % 1 == 0 ? '${k.round()}K' : '${k.toStringAsFixed(1)}K';
    }
    return number.round().toString();
  }

  String _formatFullCurrency(double number) {
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

    final double computedOrders = _forecastData['total_orders'] ?? 0;
    // For demo, still using benchmarks for clicks/reach if not defined in DB
    final double computedClicks = computedOrders / 0.032;
    final double computedReach = computedClicks / 0.025;
    
    // Break-even logic from DB
    final double breakEvenOrders = _forecastData['break_even_orders'] ?? 0;
    final int currentDoneOrders = (computedOrders * 0.78).round(); // Still mocking current progress
    final double beProgress = breakEvenOrders > 0 ? (currentDoneOrders / breakEvenOrders).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
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
                    ),
                  ],
                ),
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

            // 2. Reverse Funnel
            const Text(
              '🔄 Tính Ngược Phễu',
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
                    emoji: '💳',
                    title: 'Đơn hàng',
                    subtitle: 'CR ≈ 3.2%',
                    value: '${_formatNumber(computedOrders)} đơn',
                    color: AppTheme.colorSafe,
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
            GlassCard(
              child: Column(
                children: [
                  _buildBudgetRow('📘', 'Facebook Ads', 0.45, AppTheme.brandCyan),
                  const SizedBox(height: 14),
                  _buildBudgetRow('🎵', 'TikTok Ads', 0.35, AppTheme.colorHot),
                  const SizedBox(height: 14),
                  _buildBudgetRow('🔍', 'Google Ads', 0.20, AppTheme.colorSafe),
                ],
              ),
            ),
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
              child: Column(
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
                    'Dựa trên: AOV ${_formatNumber(_aov)} | Margin ${_grossMargin.round()}% | Định phí ${_formatNumber(_fixedCost)}',
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
                      const Text('0 đơn', style: TextStyle(fontSize: 9.5, color: AppTheme.textTertiary)),
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
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: const Text(
                      '💡 Công thức: (Định phí + Tiền Ads) / (AOV * %Lợi nhuận gộp)',
                      style: TextStyle(fontSize: 9.5, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                    ),
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
                  Row(
                    children: [
                      Expanded(
                        child: _buildScenarioCard(
                          emoji: '☀️',
                          name: 'Tươi sáng',
                          sub: 'Lạc quan',
                          val: '+45%',
                          color: AppTheme.colorSafe,
                          bgColor: AppTheme.colorSafe.withOpacity(0.05),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildScenarioCard(
                          emoji: '⚡',
                          name: 'Thực tế',
                          sub: 'Khả thi',
                          val: '+12%',
                          color: AppTheme.colorWarm,
                          bgColor: AppTheme.colorWarm.withOpacity(0.05),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildScenarioCard(
                          emoji: '🌧️',
                          name: 'Thủng phễu',
                          sub: 'Rủi ro',
                          val: '-18%',
                          color: AppTheme.colorDanger,
                          bgColor: AppTheme.colorDanger.withOpacity(0.05),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 6. Projection chart
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '📈 Dự phóng doanh thu 6 tháng',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: 16),
                  ProjectionChart(height: 172),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
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

  Widget _buildScenarioCard({
    required String emoji,
    required String name,
    required String sub,
    required String val,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 6),
          Text(
            name,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(fontSize: 8.5, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Text(
            val,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}
