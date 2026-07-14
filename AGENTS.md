# FinMatrix — AI Agent Guide

Flutter app (Vietnamese-language UX) giving small-business owners financial/marketing
intelligence: market FOMO tracking (gold, USD, stock indices), TikTok/Facebook ad analytics,
and an "AI CMO" advisor. User-facing strings, comments, and prompts are largely in Vietnamese — keep them that way.

## Architecture (read these to grasp the whole)
- `lib/main.dart` — bootstraps in order: `DatabaseHelper.ensureInitialized()` → `DatabaseSeedService.ensureMvpData()` → `runApp`. Also installs a custom `ErrorWidget.builder` that renders exceptions on-screen (even in release) for on-device debugging — don't remove it.
- `lib/screens/main_navigation.dart` — 5-tab `IndexedStack` (Home, Macro, Micro, AI CMO, Profile). Tabs switch via an `onNavigateToTab` callback passed down to children.
- `lib/services/` — all business logic & I/O. Screens stay thin; services are **singletons** (`static final X instance = X._init()`). Follow this exact pattern for new services.
- `lib/models/` — plain data classes with `fromMap`/`toMap` for SQLite rows.
- `lib/widgets/` — reusable custom-painted UI (glassmorphism cards, charts via `CustomPainter`).

## Key data flows
- **Persistence**: SQLite via `sqflite`. `database_helper.dart` owns the schema (`version: 3`) and `_onUpgrade` migrations. To change schema: bump `version`, add a `CREATE TABLE` and an `if (oldVersion < N)` branch. Web/desktop use a platform-split factory: `database_platform_stub.dart` with conditional imports for `_io.dart` (FFI on Windows/Linux) and `_web.dart` (WASM).
- **External market APIs** (e.g. `gold_price_service.dart` → vang.today, plus exchange/stock/tiktok services): each `fetch...()` does network + a *pure* `parseHistory(json)` parser (testable offline), then a `sync...()` that upserts into SQLite with `ConflictAlgorithm.replace` and recalculates derived FOMO scores best-effort (failures swallowed).
- **AI CMO pipeline**: deterministic `cmo_rule_engine.dart` does ALL math first (engagement rate, suggested budget = `safetyFactor * grossMargin`) → `ai_gateway_service.dart` routes to an LLM that only rephrases, never recomputes. The CMO's **input metrics** (`cmo_advisor_service.dart`) are sourced in priority order: **FastMoss** fully-managed market data (`dataSource='fastmoss'`) → TikTok live API if a token is set (`'live'`) → built-in demo (`'demo'`). `CmoRecommendation` carries `dataSource`/`adviceSource` (+`isFullyLive`) so the UI can show real-vs-demo transparently.
- **FastMoss** (`fastmoss_service.dart`): two integrations sharing the FastMoss token — (a) the legacy internal scraping endpoints for the Micro "ngành hàng" trends, and (b) the **official Open API** (`openapi.fastmoss.com`). The token is resolved via `secure_config_service.dart` (`getFastmossToken`): build-time `--dart-define=FASTMOSS_API_TOKEN` → encrypted `flutter_secure_storage` (legacy plaintext `SharedPreferences('fastmoss_token')` auto-migrated then wiped). For the CMO, use **Top Selling** (`POST /product/v1/rank/topSelling`, `/shop/v1/rank/topSelling`) which **supports region VN** (default); the `fullyManaged` endpoints exist too but are cross-border-only (US/EU, no VN). Endpoints need `Authorization: Bearer <token>` + a `date_info` (`buildDateInfo` → day/week/month). Products map to `TikTokAdMetrics` via `buildCmoMetricsFromProducts` (gmv→revenue, units_sold→conversions, commission→cost proxy); VN GMV is already VND (`regionGmvToVnd('VN')==1`), non-VN uses a rough USD→VND factor. Pure parsers `parseFullyManagedProducts/Shops` are tested against the doc examples in `test/fastmoss_fully_managed_test.dart`.

## AI model routing (project-specific, has tests)
`ai_gateway_service.dart` picks the cloud model by task: strategic **decisions** (`taskType: 'strategic_decision'` or rule IDs in `_decisionRuleIds` like `R4_fomo_alert`) → Opus (`LlmService.modelOpus`); synthesis/planning → Sonnet. `llm_service.dart` is a facade over a pluggable `AiProvider` registry (`lib/services/ai/`), defaulting to `AnthropicProvider`; add vendors by registering another `AiProvider`. The Anthropic key is resolved by `secure_config_service.dart` in priority order: build-time `--dart-define=ANTHROPIC_API_KEY` → encrypted `flutter_secure_storage` (legacy plaintext `SharedPreferences('anthropic_api_key')` is auto-migrated then wiped). **No key → provider returns failure → `LlmService` returns null → callers fall back to `AiMockService`**. On Web, local Ollama is skipped. Update `test/ai_model_routing_test.dart` (routing) and `test/ai_provider_test.dart` (provider delegation) when changing this.

## Conventions
- Singleton services with private `._init()` constructors; expose static config as `static const`.
- Diagnostics use `print('Decision: ... ')` strings — kept intentionally for runtime tracing.
- Theme is centralized in `lib/theme/app_theme.dart` (`AppTheme.darkTheme`, brand colors, `getGlow`, glass props). Use these constants, not raw hex.

## Developer workflow
- Run/build: `flutter pub get`, `flutter run -d windows|chrome`. (`flutter_0*.log` are run logs, ignore.)
- Tests: `flutter test`. DB tests use `DatabaseHelper.openForTesting()` (in-memory) in `setUp` and `closeDatabase()` in `tearDown`; shared seed data lives in `test/helpers/backend_seed.dart`. Prefer testing pure parsers and the rule engine directly.
- Lint: `flutter analyze` (config in `analysis_options.yaml`, `flutter_lints`).

