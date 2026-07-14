/// Outcome of a single completion request from an [AiProvider].
class AiCompletion {
  final bool ok;
  final String? text;
  final int? statusCode;
  final String? error;

  const AiCompletion._({
    required this.ok,
    this.text,
    this.statusCode,
    this.error,
  });

  factory AiCompletion.success(String text) =>
      AiCompletion._(ok: true, text: text);

  factory AiCompletion.failure({int? statusCode, String? error}) =>
      AiCompletion._(ok: false, statusCode: statusCode, error: error);
}

/// Outcome of a lightweight connectivity / credential check.
class AiHealth {
  final bool ok;
  final String message;
  const AiHealth(this.ok, this.message);
}

/// Contract implemented by every model vendor (Anthropic, and future ones).
///
/// The gateway/routing layer stays vendor-agnostic and simply selects a
/// provider + model id; the provider owns transport, auth and error mapping.
abstract class AiProvider {
  /// Stable identifier, e.g. `anthropic`.
  String get id;

  /// Human-friendly name for UI/logging, e.g. `Anthropic (Claude)`.
  String get displayName;

  /// True when a usable credential is currently available.
  Future<bool> isConfigured();

  /// Runs a single system+user completion against [model].
  Future<AiCompletion> complete({
    required String systemPrompt,
    required String userMessage,
    required String model,
    int maxTokens = 1024,
  });

  /// Minimal request used to validate credentials/connectivity.
  Future<AiHealth> ping({required String model, String? apiKeyOverride});
}

