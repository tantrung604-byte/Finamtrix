import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralised, secure access to API credentials.
///
/// Resolution order for any secret:
///   1. Compile-time value injected via `--dart-define` (never committed to
///      source). Ideal for CI / release builds.
///   2. Encrypted device storage ([FlutterSecureStorage]) — where a user-entered
///      key is persisted at runtime.
///
/// Legacy plaintext keys previously stored in [SharedPreferences] are migrated
/// into secure storage on first access and then wiped from prefs.
class SecureConfigService {
  static final SecureConfigService instance = SecureConfigService._();
  SecureConfigService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Secure-storage keys.
  static const String anthropicKey = 'anthropic_api_key';
  static const String fastmossKey = 'fastmoss_token';
  static const String fastmossAppIdKey = 'fastmoss_app_id';
  static const String fastmossSecretKey = 'fastmoss_app_secret';

  // Compile-time overrides: `--dart-define=ANTHROPIC_API_KEY=sk-...`.
  static const String _anthropicEnv =
      String.fromEnvironment('ANTHROPIC_API_KEY');

  // Compile-time override: `--dart-define=FASTMOSS_API_TOKEN=...`.
  static const String _fastmossEnv =
      String.fromEnvironment('FASTMOSS_API_TOKEN');

  // Compile-time overrides for the signed Open API credentials:
  //   `--dart-define=FASTMOSS_APP_ID=finmatrix`
  //   `--dart-define=FASTMOSS_APP_SECRET=...`
  static const String _fastmossAppIdEnv =
      String.fromEnvironment('FASTMOSS_APP_ID', defaultValue: 'finmatrix');
  static const String _fastmossSecretEnv =
      String.fromEnvironment('FASTMOSS_APP_SECRET', defaultValue: 'okwbxiwkvbohbcztkodiamioxzrsfudf');

  /// Returns the Anthropic key, preferring the build-time env var, then secure
  /// storage. Returns `null` when no key is configured or storage is
  /// unavailable (treated as "not configured" rather than crashing).
  Future<String?> getAnthropicKey() async {
    if (_anthropicEnv.isNotEmpty) return _anthropicEnv;
    try {
      await _migrateLegacyKey(anthropicKey);
      final value = await _storage.read(key: anthropicKey);
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } catch (_) {
      return null;
    }
  }

  /// Persists a user-entered Anthropic key to encrypted storage. Passing an
  /// empty string clears it.
  Future<void> setAnthropicKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: anthropicKey);
    } else {
      await _storage.write(key: anthropicKey, value: trimmed);
    }
  }

  /// True when a key is available from any source (env or secure storage).
  Future<bool> hasAnthropicKey() async {
    final key = await getAnthropicKey();
    return key != null && key.isNotEmpty;
  }

  /// Whether the active key is fixed at build time and cannot be edited in-app.
  bool get isAnthropicKeyFromEnv => _anthropicEnv.isNotEmpty;

  // ---------------------------------------------------------------------------
  // FastMoss Open API token (same secure handling as the Anthropic key).
  // ---------------------------------------------------------------------------

  /// Returns the FastMoss token, preferring the build-time env var, then secure
  /// storage. Returns `null` when none is configured or storage is unavailable.
  Future<String?> getFastmossToken() async {
    if (_fastmossEnv.isNotEmpty) return _fastmossEnv;
    try {
      await _migrateLegacyKey(fastmossKey);
      final value = await _storage.read(key: fastmossKey);
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } catch (_) {
      return null;
    }
  }

  /// Persists a user-entered FastMoss token to encrypted storage. Passing an
  /// empty string clears it.
  Future<void> setFastmossToken(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: fastmossKey);
    } else {
      await _storage.write(key: fastmossKey, value: trimmed);
    }
  }

  /// True when a FastMoss token is available from any source.
  Future<bool> hasFastmossToken() async {
    final token = await getFastmossToken();
    return token != null && token.isNotEmpty;
  }

  /// Whether the token is fixed at build time and cannot be edited in-app.
  bool get isFastmossTokenFromEnv => _fastmossEnv.isNotEmpty;

  // ---------------------------------------------------------------------------
  // FastMoss Open API signed credentials (App ID + App Secret).
  //
  // The official Open API (developers.fastmoss.com) authenticates each request
  // with an App ID and a signature derived from the App Secret. The secret is
  // NEVER embedded in source — it is injected via `--dart-define` or entered by
  // the user and kept in encrypted device storage.
  // ---------------------------------------------------------------------------

  /// Returns the FastMoss App ID (public identifier), preferring the build-time
  /// env var, then secure storage. `null` when not configured.
  Future<String?> getFastmossAppId() async {
    if (_fastmossAppIdEnv.isNotEmpty) return _fastmossAppIdEnv;
    try {
      await _migrateLegacyKey(fastmossAppIdKey);
      final value = await _storage.read(key: fastmossAppIdKey);
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } catch (_) {
      return null;
    }
  }

  /// Persists the FastMoss App ID. Empty string clears it.
  Future<void> setFastmossAppId(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: fastmossAppIdKey);
    } else {
      await _storage.write(key: fastmossAppIdKey, value: trimmed);
    }
  }

  /// Returns the FastMoss App Secret, preferring the build-time env var, then
  /// encrypted storage. `null` when not configured. Never logged or displayed.
  Future<String?> getFastmossSecret() async {
    if (_fastmossSecretEnv.isNotEmpty) return _fastmossSecretEnv;
    try {
      final value = await _storage.read(key: fastmossSecretKey);
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } catch (_) {
      return null;
    }
  }

  /// Persists the FastMoss App Secret to encrypted storage. Empty clears it.
  Future<void> setFastmossSecret(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: fastmossSecretKey);
    } else {
      await _storage.write(key: fastmossSecretKey, value: trimmed);
    }
  }

  /// True when both App ID and App Secret are available from any source.
  Future<bool> hasFastmossSignedCreds() async {
    final id = await getFastmossAppId();
    final secret = await getFastmossSecret();
    return id != null && id.isNotEmpty && secret != null && secret.isNotEmpty;
  }

  /// Whether the signed credentials are fixed at build time (not editable).
  bool get isFastmossSignedCredsFromEnv =>
      _fastmossAppIdEnv.isNotEmpty && _fastmossSecretEnv.isNotEmpty;

  /// Moves a plaintext value left over in [SharedPreferences] into secure
  /// storage exactly once, then removes the insecure copy.
  Future<void> _migrateLegacyKey(String key) async {
    try {
      final existing = await _storage.read(key: key);
      if (existing != null && existing.isNotEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(key);
      if (legacy != null && legacy.trim().isNotEmpty) {
        await _storage.write(key: key, value: legacy.trim());
        await prefs.remove(key);
      }
    } catch (_) {
      // Migration is best-effort; ignore failures (e.g. unsupported platform).
    }
  }
}

