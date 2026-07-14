import 'package:flutter_test/flutter_test.dart';

import 'package:finmatrix_flutter/services/ai/ai_provider.dart';
import 'package:finmatrix_flutter/services/llm_service.dart';

/// A controllable in-memory provider used to verify LlmService delegation
/// without hitting the network.
class _FakeProvider implements AiProvider {
  _FakeProvider({this.reply, this.healthy = true});

  final String? reply; // null → simulate failure
  final bool healthy;

  String? lastModel;
  String? lastSystem;

  @override
  String get id => 'fake';

  @override
  String get displayName => 'Fake Provider';

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<AiCompletion> complete({
    required String systemPrompt,
    required String userMessage,
    required String model,
    int maxTokens = 1024,
  }) async {
    lastModel = model;
    lastSystem = systemPrompt;
    return reply == null
        ? AiCompletion.failure(statusCode: 500)
        : AiCompletion.success(reply!);
  }

  @override
  Future<AiHealth> ping({required String model, String? apiKeyOverride}) async {
    return AiHealth(healthy, healthy ? 'ok' : 'bad key');
  }
}

void main() {
  test('delegates completion to the active provider and returns its text', () async {
    final fake = _FakeProvider(reply: 'PLAN OK');
    final svc = LlmService.withProviders({'anthropic': fake});

    final out = await svc.generateSuggestion('R7_competitor_plan', {'x': 1},
        model: LlmService.modelOpus);

    expect(out, 'PLAN OK');
    expect(fake.lastModel, LlmService.modelOpus);
    expect(fake.lastSystem, contains('AI CMO'));
  });

  test('provider failure yields null so callers fall back to mock', () async {
    final svc = LlmService.withProviders({'anthropic': _FakeProvider(reply: null)});
    final out = await svc.generateCloudChatResponse('sys', 'hi');
    expect(out, isNull);
  });

  test('testConnection surfaces provider health', () async {
    final okSvc = LlmService.withProviders({'anthropic': _FakeProvider(healthy: true)});
    final badSvc = LlmService.withProviders({'anthropic': _FakeProvider(healthy: false)});

    expect((await okSvc.testConnection()).ok, isTrue);
    expect((await badSvc.testConnection()).ok, isFalse);
  });
}

