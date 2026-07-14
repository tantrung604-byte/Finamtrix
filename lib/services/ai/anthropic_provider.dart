import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../secure_config_service.dart';
import 'ai_provider.dart';

/// Anthropic (Claude) implementation of [AiProvider].
///
/// The API key is never hard-coded — it is resolved at call time from
/// [SecureConfigService] (build-time env var or encrypted storage).
class AnthropicProvider implements AiProvider {
  AnthropicProvider({http.Client? client, SecureConfigService? config})
      : _client = client ?? http.Client(),
        _config = config ?? SecureConfigService.instance;

  final http.Client _client;
  final SecureConfigService _config;

  static const String _endpoint = 'https://api.anthropic.com/v1/messages';
  static const String _anthropicVersion = '2023-06-01';

  @override
  String get id => 'anthropic';

  @override
  String get displayName => 'Anthropic (Claude)';

  @override
  Future<bool> isConfigured() => _config.hasAnthropicKey();

  @override
  Future<AiCompletion> complete({
    required String systemPrompt,
    required String userMessage,
    required String model,
    int maxTokens = 1024,
  }) async {
    final apiKey = await _config.getAnthropicKey();
    if (apiKey == null || apiKey.isEmpty) {
      return AiCompletion.failure(error: 'no_api_key');
    }

    try {
      final response = await _client.post(
        Uri.parse(_endpoint),
        headers: _headers(apiKey),
        body: jsonEncode({
          'model': model,
          'max_tokens': maxTokens,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': userMessage}
          ],
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final text = (result['content'] as List).first['text'] as String;
        return AiCompletion.success(text);
      }
      if (kDebugMode) debugPrint('Anthropic error ${response.statusCode}: ${response.body}');
      return AiCompletion.failure(statusCode: response.statusCode, error: response.body);
    } catch (e) {
      if (kDebugMode) debugPrint('Anthropic exception: $e');
      return AiCompletion.failure(error: e.toString());
    }
  }

  @override
  Future<AiHealth> ping({required String model, String? apiKeyOverride}) async {
    final apiKey = (apiKeyOverride?.trim().isNotEmpty ?? false)
        ? apiKeyOverride!.trim()
        : await _config.getAnthropicKey();

    if (apiKey == null || apiKey.isEmpty) {
      return const AiHealth(false, 'Chưa cấu hình Anthropic API Key.');
    }

    try {
      final response = await _client.post(
        Uri.parse(_endpoint),
        headers: _headers(apiKey),
        body: jsonEncode({
          'model': model,
          'max_tokens': 1,
          'messages': [
            {'role': 'user', 'content': 'ping'}
          ],
        }),
      );

      switch (response.statusCode) {
        case 200:
          return AiHealth(true, 'Kết nối AI thành công (model: $model).');
        case 401:
          return const AiHealth(false, 'API Key không hợp lệ hoặc đã bị thu hồi (401).');
        case 403:
          return const AiHealth(false, 'API Key không có quyền truy cập model này (403).');
        case 429:
          return const AiHealth(false, 'Đã vượt hạn mức / rate limit (429). Thử lại sau.');
        default:
          return AiHealth(false, 'Lỗi từ Anthropic (${response.statusCode}). Kiểm tra lại key.');
      }
    } catch (e) {
      return AiHealth(false, 'Không thể kết nối máy chủ AI: $e');
    }
  }

  Map<String, String> _headers(String apiKey) => {
        'x-api-key': apiKey,
        'anthropic-version': _anthropicVersion,
        'content-type': 'application/json',
      };
}

