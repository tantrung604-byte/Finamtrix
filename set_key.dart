import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  final prefs = await SharedPreferences.getInstance();
  // We can't use secure storage here directly because it needs Flutter context,
  // but we can set the legacy key which SecureConfigService will then migrate.
  await prefs.setString('anthropic_api_key', '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');
  print('Legacy key set.');
}
