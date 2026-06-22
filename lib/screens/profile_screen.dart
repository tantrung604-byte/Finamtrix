import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _apifyTokenController = TextEditingController();
  final TextEditingController _ollamaUrlController = TextEditingController();
  bool _useLocalAi = true;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('anthropic_api_key') ?? '';
      _apifyTokenController.text = prefs.getString('apify_api_token') ?? '';
      _ollamaUrlController.text = prefs.getString('ollama_base_url') ?? 'http://localhost:11434/api';
      _useLocalAi = prefs.getBool('use_local_ai_for_chat') ?? true;
    });
  }

  Future<void> _saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('anthropic_api_key', _apiKeyController.text);
    await prefs.setString('apify_api_token', _apifyTokenController.text);
    await prefs.setString('ollama_base_url', _ollamaUrlController.text);
    await prefs.setBool('use_local_ai_for_chat', _useLocalAi);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu cấu hình thành công!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          children: [
            const SizedBox(height: 24),
            // 1. Profile Header
            Center(
              child: Column(
                children: [
                  Container(
                    alignment: Alignment.center,
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      gradient: AppTheme.brandGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      'T',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Trần Minh Tuấn',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'tuan.tran@email.com',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: const Text(
                      '✨ Free Tier',
                      style: TextStyle(
                        color: AppTheme.brandCyan,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2. Premium CTA
            GlassCard(
              glowColor: AppTheme.brandPurple,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.brandPurple.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '👑 PREMIUM',
                      style: TextStyle(
                        color: AppTheme.brandPurple,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Nâng cấp Premium',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Stress-test kịch bản rủi ro • AI CMO chuyên sâu • Cảnh báo sớm biến động sức mua • Phân tích đối thủ realtime',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cảm ơn bạn! Đã kích hoạt 7 ngày dùng thử Premium miễn phí.'),
                          backgroundColor: AppTheme.brandPurple,
                        ),
                      );
                    },
                    child: Container(
                      alignment: Alignment.center,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: AppTheme.premiumGradient,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: AppTheme.getGlow(AppTheme.brandCyan),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.star, color: Colors.white, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Dùng thử 7 ngày miễn phí',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 3. Subscription comparison
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '📦 So sánh gói',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    child: Column(
                      children: const [
                        Text(
                          'Miễn phí',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '0đ',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textSecondary),
                        ),
                        SizedBox(height: 12),
                        Text(
                          '✅ Biểu đồ nhiệt độ cơ bản\n✅ Giá Vàng/BDS realtime\n❌ Stress-test kịch bản\n❌ AI CMO chuyên sâu\n❌ Cảnh báo sớm',
                          style: TextStyle(fontSize: 10.5, color: AppTheme.textSecondary, height: 1.8),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    glowColor: AppTheme.brandPurple.withOpacity(0.3),
                    child: Column(
                      children: [
                        const Text(
                          'Premium ✨',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.brandPurple),
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          text: const TextSpan(
                            text: '199K',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.brandCyan),
                            children: [
                              TextSpan(
                                text: '/tháng',
                                style: TextStyle(fontSize: 11, color: AppTheme.textTertiary, fontWeight: FontWeight.normal),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '✅ Tất cả Free Tier\n✅ Stress-test 3 kịch bản\n✅ AI CMO cá nhân hóa\n✅ Cảnh báo sớm biến động\n✅ Lời khuyên thực chiến',
                          style: TextStyle(fontSize: 10.5, color: AppTheme.textPrimary.withOpacity(0.9), height: 1.8),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 3.5 AI Configuration
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '🤖 Cấu hình AI CMO (Opus 4.8)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Anthropic API Key',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'sk-ant-api03-...',
                      hintStyle: const TextStyle(color: AppTheme.textTertiary),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Apify API Token (Facebook Scraping)',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apifyTokenController,
                    obscureText: true,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'apify_api_...',
                      hintStyle: const TextStyle(color: AppTheme.textTertiary),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _saveConfigs,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandCyan.withOpacity(0.2),
                      foregroundColor: AppTheme.brandCyan,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Lưu cấu hình', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 3.6 Local AI Configuration (Ollama)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '🏠 Cấu hình AI Local (Ollama)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Sử dụng Local cho Chat',
                        style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                      ),
                      Switch(
                        value: _useLocalAi,
                        activeColor: AppTheme.brandCyan,
                        onChanged: (val) {
                          setState(() => _useLocalAi = val);
                        },
                      ),
                    ],
                  ),
                  const Text(
                    'Tiết kiệm chi phí bằng cách dùng Llama 3.2 chạy tại máy cho các câu hỏi thông thường.',
                    style: TextStyle(fontSize: 10.5, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ollama API URL',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ollamaUrlController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'http://localhost:11434/api',
                      hintStyle: const TextStyle(color: AppTheme.textTertiary),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _saveConfigs,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.1),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Lưu AI Local', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 4. Settings List
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '⚙️ Cài đặt',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildSettingsItem(context, '🔔', 'Thông báo'),
                  _buildDivider(),
                  _buildSettingsItem(context, '🌐', 'Ngôn ngữ'),
                  _buildDivider(),
                  _buildSettingsItem(context, '🔒', 'Bảo mật'),
                  _buildDivider(),
                  _buildSettingsItem(context, '❓', 'Hỗ trợ & Feedback'),
                  _buildDivider(),
                  _buildSettingsItem(context, '📄', 'Điều khoản sử dụng'),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 5. Footer
            const Text(
              'FinMatrix v1.0.0',
              style: TextStyle(fontSize: 11, color: AppTheme.textTertiary),
            ),
            const SizedBox(height: 4),
            const Text(
              '"Chiếc la bàn định hướng" cho người Việt 🇻🇳',
              style: TextStyle(fontSize: 10.5, color: AppTheme.textTertiary, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem(BuildContext context, String emoji, String title) {
    return ListTile(
      dense: true,
      leading: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 14)),
      ),
      title: Text(
        title,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textTertiary, size: 16),
      onTap: () {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tính năng "$title" đang phát triển.'),
            backgroundColor: AppTheme.bgSecondary,
          ),
        );
      },
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1.0,
      thickness: 1.0,
      color: Colors.white.withOpacity(0.04),
      indent: 16,
      endIndent: 16,
    );
  }
}
