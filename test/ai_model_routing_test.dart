import 'package:flutter_test/flutter_test.dart';

import 'package:finmatrix_flutter/services/ai_gateway_service.dart';
import 'package:finmatrix_flutter/services/llm_service.dart';

/// AI CMO model routing:
///   - Strategic DECISION (đưa ra quyết định) -> Opus 4.8
///   - Data synthesis / planning (bình thường) -> Sonnet 4.5
void main() {
  final gateway = AiGatewayService.instance;

  test('explicit strategic decision -> Opus 4.8', () {
    expect(gateway.modelForTask(taskType: 'strategic_decision'), LlmService.modelOpus);
  });

  test('decision rules -> Opus 4.8', () {
    for (final ruleId in ['R4_fomo_alert', 'R7_competitor_plan', 'R8_macro_purchasing_power']) {
      expect(
        gateway.modelForTask(taskType: 'rephrase', ruleId: ruleId),
        LlmService.modelOpus,
        reason: '$ruleId should use Opus',
      );
    }
  });

  test('routine synthesis rules -> Sonnet 4.5', () {
    for (final ruleId in ['R1_underperform', 'R5_data_reminder', 'default']) {
      expect(
        gateway.modelForTask(taskType: 'rephrase', ruleId: ruleId),
        LlmService.modelSonnet,
        reason: '$ruleId should use Sonnet',
      );
    }
  });

  test('plan / analysis tasks -> Sonnet 4.5', () {
    expect(gateway.modelForTask(taskType: 'marketing_plan'), LlmService.modelSonnet);
    expect(gateway.modelForTask(taskType: 'strategic_analysis'), LlmService.modelSonnet);
  });

  test('model identifiers are correct', () {
    expect(LlmService.modelOpus, 'claude-opus-4-8');
    expect(LlmService.modelSonnet, 'claude-sonnet-4-5');
  });
}

