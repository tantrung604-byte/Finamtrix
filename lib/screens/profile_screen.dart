import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/glass_card.dart';
import '../services/llm_service.dart';
import '../services/secure_config_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _apifyTokenController = TextEditingController();
  final TextEditingController _ollamaUrlController = TextEditingController();
  final TextEditingController _wifeedApiKeyController = TextEditingController();
  final TextEditingController _fastmossTokenController = TextEditingController();
  final TextEditingController _fastmossAppIdController = TextEditingController();
  final TextEditingController _fastmossSecretController = TextEditingController();
  bool _useLocalAi = true;
  bool _testingConnection = false;
  bool _apiKeyFromEnv = false;
  bool _fastmossFromEnv = false;
  bool _fastmossSignedFromEnv = false;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    // Anthropic key now comes from encrypted secure storage / build-time env.
    final anthropicKey = await SecureConfigService.instance.getAnthropicKey();
    final fromEnv = SecureConfigService.instance.isAnthropicKeyFromEnv;
    // FastMoss token also moved to encrypted secure storage / build-time env.
    final fastmossToken = await SecureConfigService.instance.getFastmossToken();
    final fmFromEnv = SecureConfigService.instance.isFastmossTokenFromEnv;
    // FastMoss signed Open API credentials (App ID + App Secret).
    final fastmossAppId = await SecureConfigService.instance.getFastmossAppId();
    final fmSignedFromEnv =
        SecureConfigService.instance.isFastmossSignedCredsFromEnv;
    setState(() {
      _apiKeyController.text = fromEnv ? '' : (anthropicKey ?? '');
      _apiKeyFromEnv = fromEnv;
      _apifyTokenController.text = prefs.getString('apify_api_token') ?? '';
      _ollamaUrlController.text = prefs.getString('ollama_base_url') ?? 'http://localhost:11434/api';
      _wifeedApiKeyController.text = prefs.getString('wifeed_apikey') ?? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MTQ0MywiZW1haWwiOiJ0YW50cnVuZzYwNEBnbWFpbC5jb20iLCJuYW1lIjoiVsWpIE5ndXnhu4VuIFThuqVuIFRydW5nIiwicGhvbmUiOiIrODQ5MTg3Mjg1OTUiLCJjb21wYW55IjoiT2x5bXBpYSBUcmF2ZWwiLCJyb2xlIjoidXNlciIsImlhdCI6MTc4MjY5MTYzOX0.5p9tCW3qvyrKVPOvK4tompI__Qnime11YIFcb9c1KWo';
      _fastmossTokenController.text = fmFromEnv ? '' : (fastmossToken ?? '');
      _fastmossFromEnv = fmFromEnv;
      _fastmossAppIdController.text =
          fmSignedFromEnv ? '' : (fastmossAppId ?? '');
      _fastmossSignedFromEnv = fmSignedFromEnv;
      _useLocalAi = prefs.getBool('use_local_ai_for_chat') ?? true;
    });
  }

  Future<void> _saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    // Anthropic key → encrypted secure storage (skip when fixed by env var).
    if (!_apiKeyFromEnv) {
      await SecureConfigService.instance.setAnthropicKey(_apiKeyController.text);
    }
    // FastMoss token → encrypted secure storage (skip when fixed by env var).
    if (!_fastmossFromEnv) {
      await SecureConfigService.instance
          .setFastmossToken(_fastmossTokenController.text);
    }
    // FastMoss signed Open API creds → encrypted storage (skip when env-fixed).
    if (!_fastmossSignedFromEnv) {
      await SecureConfigService.instance
          .setFastmossAppId(_fastmossAppIdController.text);
      // Only overwrite the secret when the user actually typed one, so an empty
      // field doesn't wipe a previously-saved secret unintentionally.
      if (_fastmossSecretController.text.trim().isNotEmpty) {
        await SecureConfigService.instance
            .setFastmossSecret(_fastmossSecretController.text);
        _fastmossSecretController.clear();
      }
    }
    await prefs.setString('apify_api_token', _apifyTokenController.text);
    await prefs.setString('ollama_base_url', _ollamaUrlController.text);
    await prefs.setString('wifeed_apikey', _wifeedApiKeyController.text.trim());
    await prefs.setBool('use_local_ai_for_chat', _useLocalAi);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu cấu hình thành công!')),
      );
    }
  }

  /// Validates the Anthropic key currently typed in the field by making a
  /// minimal live request. Saves first so the key is persisted regardless.
  Future<void> _testAiConnection() async {
    HapticFeedback.lightImpact();
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập Anthropic API Key trước.')),
      );
      return;
    }

    setState(() => _testingConnection = true);
    final result = await LlmService.instance.testConnection(apiKeyOverride: key);
    if (!mounted) return;
    setState(() => _testingConnection = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.ok ? AppTheme.brandCyan : AppTheme.colorHot,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: context.pagePadding, vertical: 12.0),
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
                      'A',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A Trung Travel',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'trung.travel@email.com',
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
