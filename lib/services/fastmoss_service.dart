import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../models/fastmoss_trend.dart';
import '../models/fastmoss_fully_managed.dart';
import '../models/tiktok_ad_metrics.dart';
import 'database_helper.dart';
import 'secure_config_service.dart';

/// Connects to FastMoss (fastmoss.com) TikTok Shop analytics to extract
/// category product trends, persists them into `fastmoss_category_trend`,
/// and exposes per-category queries for the Micro (Vi Mô) "ngành hàng" section.
///
/// FastMoss sits behind an anti-bot WAF (Tencent EdgeOne) and its data API
/// requires an authenticated session. Provide your logged-in session token via
/// Profile → "Cấu hình FastMoss" (stored under [prefsToken]); the service sends
/// it as a Bearer token + cookie with browser-like headers. When no valid token
/// is set (or the request is blocked), it falls back to category-appropriate
/// seed data so the UI stays functional.
class FastmossService {
  static final FastmossService instance = FastmossService._init();
  FastmossService._init();

  static const String _source = 'fastmoss';

  /// Secure-storage key for the FastMoss token (see [SecureConfigService]).
  static const String prefsToken = SecureConfigService.fastmossKey;

  /// Official FastMoss **Open API** base (developers.fastmoss.com).
  /// Used by the "Fully Managed" ranking endpoints that feed the AI CMO.
  static const String openApiBase = 'https://openapi.fastmoss.com';

  /// Optional CORS/secret-hiding proxy (Cloudflare Worker / Supabase Edge
  /// Function — see `proxy/` and `supabase/functions/`). When set, all Open API
  /// calls are routed through it and NO credentials are sent from the client
  /// (the proxy injects them server-side). Required for Flutter **web** where
  /// the browser blocks direct calls to openapi.fastmoss.com (no CORS).
  ///
  ///   flutter build web --dart-define=FASTMOSS_PROXY_URL=https://xxx.workers.dev
  static const String proxyUrl = String.fromEnvironment('FASTMOSS_PROXY_URL');

  /// True when Open API traffic goes through the proxy.
  static bool get usesProxy => proxyUrl.isNotEmpty;

  /// Regions supported by the fully-managed endpoints (cross-border markets).
  static const List<String> fullyManagedRegions = [
    'US', 'GB', 'ES', 'MX', 'DE', 'IT', 'FR',
  ];

  /// Regions supported by the **Top Selling** ranking endpoints (includes VN
  /// and other SEA/APAC markets) — used as the primary CMO source.
  static const List<String> topSellingRegions = [
    'US', 'ID', 'GB', 'VN', 'TH', 'MY', 'PH', 'SG',
    'ES', 'MX', 'DE', 'FR', 'IT', 'BR', 'JP',
  ];

  /// Default USD→VND rate used when converting non-VN GMV (priced in USD/other)
  /// into the app's VND-based CMO metrics. Override per call if needed.
  static const double usdToVndFallback = 25400;

  /// Approximate factor to convert a region's native GMV currency to VND.
  /// VN GMV is already in VND (factor 1); other regions use a rough USD→VND
  /// fallback (the CMO mostly uses ratios, so absolute precision is secondary).
  static double regionGmvToVnd(String region) =>
      region.toUpperCase() == 'VN' ? 1.0 : usdToVndFallback;

  /// FastMoss category product-ranking endpoint (internal API).
  static const String _baseUrl = 'https://www.fastmoss.com/api/goods/rank';

  /// FastMoss creator ranking endpoint (internal API).
  static const String _creatorUrl = 'https://www.fastmoss.com/api/author/rank';

  /// Region filter for the Vietnam market.
  static const String region = 'VN';

  /// Maps app business categories to TikTok Shop category ids used by FastMoss.
  /// Values are TikTok Shop first-level category ids (VN taxonomy). Each app
  /// category keeps a primary id plus related sub-ids so results stay broad.
  /// Verify/extend against a live token if TikTok updates its taxonomy.
  static const Map<String, FastmossCategoryDef> categoryTaxonomy = {
    'Thời trang': FastmossCategoryDef(
      primaryId: '601152', // Womenswear & Underwear
      subIds: ['824328', '601352'], // Menswear & Underwear, Fashion Accessories
      tiktokName: 'Fashion',
    ),
    'Ăn uống': FastmossCategoryDef(
      primaryId: '600942', // Food & Beverages
      subIds: ['601450'], // Health (supplements/snacks overlap)
      tiktokName: 'Food & Beverages',
    ),
    'Tiêu dùng': FastmossCategoryDef(
      primaryId: '600024', // Household Appliances
      subIds: ['824584', '601739'], // Home Supplies, Household Care
      tiktokName: 'Home & Household',
    ),
    'Điện tử': FastmossCategoryDef(
      primaryId: '802184', // Phones & Electronics
      subIds: ['600154'], // Computers & Office Equipment
      tiktokName: 'Phones & Electronics',
    ),
    'Du lịch': FastmossCategoryDef(
      primaryId: '824406', // Luggage & Bags
      subIds: ['951432'], // Sports & Outdoor
      tiktokName: 'Luggage & Bags',
    ),
  };

  /// Backward-compatible flat id lookup.
  static Map<String, String> get categoryIdMap =>
      {for (final e in categoryTaxonomy.entries) e.key: e.value.primaryId};

  /// Maps app business categories to the **Open API** L1 `category_id`
  /// (openapi.fastmoss.com taxonomy — verified live against topSelling VN):
  ///   2=Womenswear, 7=Luggage & Bags, 13=Household Appliances,
  ///   16=Phones & Electronics, 24=Food & Beverages.
  static const Map<String, int> openApiL1CategoryIds = {
    'Thời trang': 2, // Womenswear & Underwear
    'Ăn uống': 24, // Food & Beverages
    'Tiêu dùng': 13, // Household Appliances
    'Điện tử': 16, // Phones & Electronics
    'Du lịch': 7, // Luggage & Bags
  };


  Future<String?> _getToken() async {
    try {
      // Token is stored encrypted (build-time env var or secure storage);
      // legacy plaintext prefs are auto-migrated by SecureConfigService.
      return await SecureConfigService.instance.getFastmossToken();
    } catch (_) {
      return null;
    }
  }

  /// Browser-like headers to reduce the chance of being blocked by the WAF.
  Map<String, String> _headers(String? token) => {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'vi-VN,vi;q=0.9,en;q=0.8',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Referer': 'https://www.fastmoss.com/vi/dashboard',
        'Origin': 'https://www.fastmoss.com',
        if (token != null) 'Authorization': 'Bearer $token',
        if (token != null) 'Cookie': 'fm_token=$token',
      };

  /// Fetches trending products for [category] from FastMoss.
  /// Returns [] on any error / block (caller falls back to cached/seed).
  Future<List<FastmossProductTrend>> fetchCategoryTrends(String category, {int periodDays = 7}) async {
    final token = await _getToken();
    if (token == null) return [];

    final catId = categoryTaxonomy[category]?.primaryId ?? '';
    final snapshotDate = DateTime.now().toIso8601String().split('T')[0];
    final url = '$_baseUrl?category=$catId&region=$region&date_type=$periodDays&page=1&size=30&sort=gmv';

    try {
      final response = await http
          .get(Uri.parse(url), headers: _headers(token))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        // ignore: avoid_print
        print('FastMoss API error ${response.statusCode} (blocked or auth).');
        return [];
      }
      return parseResponse(jsonDecode(response.body),
          category: category, snapshotDate: snapshotDate, periodDays: periodDays);
    } catch (e) {
      // ignore: avoid_print
      print('FastMoss fetch exception: $e');
      return [];
    }
  }

  /// Pure parser (no network). Handles the common FastMoss `{data:{list:[]}}`
  /// and `{data:[]}` shapes defensively.
  List<FastmossProductTrend> parseResponse(
    dynamic json, {
    required String category,
    required String snapshotDate,
    int periodDays = 7,
  }) {
    List? items;
    if (json is Map) {
      final data = json['data'];
      if (data is List) {
        items = data;
      } else if (data is Map) {
        items = (data['list'] ?? data['items'] ?? data['rows']) as List?;
      }
    } else if (json is List) {
      items = json;
    }
    if (items == null) return [];

    return items
        .whereType<Map>()
        .map((e) => FastmossProductTrend.fromApi(
              Map<String, dynamic>.from(e),
              category: category,
              snapshotDate: snapshotDate,
              periodDays: periodDays,
            ))
        .toList();
  }

  /// Fetches trending products for [category] from the **official Open API**
  /// (`/product/v1/rank/topSelling`, region VN) and converts them into the
  /// [FastmossProductTrend] shape the Micro "ngành hàng" UI already renders.
  /// Returns [] on any error / missing credentials.
  Future<List<FastmossProductTrend>> fetchCategoryTrendsOpenApi(
      String category,
      {int periodDays = 7}) async {
    final categoryId = openApiL1CategoryIds[category];
    final snapshotDate = DateTime.now().toIso8601String().split('T')[0];

    final products = await fetchTopSellingProducts(
      region: 'VN',
      categoryId: categoryId,
      periodDays: periodDays,
      pagesize: 30,
      orderField: 'gmv',
    );
    if (products.isEmpty) return [];

    return products
        .map((p) {
          final gmvVnd =
              p.gmv * regionGmvToVnd(p.region.isEmpty ? 'VN' : p.region);
          // VN `real_price` uses dot thousand-separators ("58.726 ₫") which a
          // generic parse mangles; the average selling price GMV/units is
          // exact and format-independent.
          final priceVnd =
              p.unitsSold > 0 ? gmvVnd / p.unitsSold : p.realPrice;
          return FastmossProductTrend(
            category: category,
            productName: p.title,
            shopName: p.shopName,
            gmvVnd: gmvVnd,
            sales: p.unitsSold,
            priceVnd: priceVnd,
            // FastMoss growth is basis-points-like (e.g. 3242 → 32.42%).
            growthPct: p.unitsSoldGrowthRate / 100.0,
            commissionPct: p.commissionPct,
            periodDays: periodDays,
            snapshotDate: snapshotDate,
          );
        })
        .toList();
  }

  /// Fetches (or seeds) trends for [category]/[periodDays] and upserts them.
  /// Returns the number of rows written.
  ///
  /// **Auto-update cadence**: FastMoss ranking data is recomputed once per day
  /// (day/week windows, ~T+2 lag), so calling more often returns identical
  /// data and burns API quota. This method therefore self-throttles: when a
  /// snapshot for **today** already exists for this category+period it returns
  /// immediately without a network call. Pass [force] to bypass (e.g. an
  /// explicit pull-to-refresh by the user).
  ///
  /// Source priority:
  ///   1. Official Open API topSelling VN (Name + Client Secret).
  ///   2. Legacy internal API (session token).
  ///   3. Existing cache, then seed data.
  Future<int> syncCategoryTrends(String category,
      {int periodDays = 7, bool force = false}) async {
    // Daily throttle: skip the network when today's snapshot is stored.
    if (!force && await _hasSnapshotForToday(category, periodDays)) return 0;

    var points =
        await fetchCategoryTrendsOpenApi(category, periodDays: periodDays);

    if (points.isEmpty) {
      points = await fetchCategoryTrends(category, periodDays: periodDays);
    }

    // Fallback: only seed if we have nothing stored for this category+period.
    if (points.isEmpty) {
      final existing = await getCategoryTrends(category, periodDays: periodDays);
      if (existing.isNotEmpty) return 0;
      points = _seedTrends(category, periodDays);
    }
    if (points.isEmpty) return 0;

    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (final p in points) {
      batch.insert(
        'fastmoss_category_trend',
        {...p.toDbMap(), 'source': _source},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    return points.length;
  }

  /// Latest stored trends for [category]/[periodDays], highest GMV first.
  Future<List<FastmossProductTrend>> getCategoryTrends(String category,
      {int periodDays = 7, int limit = 30}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'fastmoss_category_trend',
      where: 'category = ? AND period_days = ?',
      whereArgs: [category, periodDays],
      orderBy: 'snapshot_date DESC, gmv_vnd DESC',
      limit: limit,
    );
    return rows.map((r) => FastmossProductTrend.fromDbMap(r)).toList();
  }

  /// True when a trend snapshot dated **today** already exists for
  /// [category]+[periodDays] — used to throttle API calls to once per day.
  Future<bool> _hasSnapshotForToday(String category, int periodDays) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'fastmoss_category_trend',
        columns: ['snapshot_date'],
        where: 'category = ? AND period_days = ? AND snapshot_date = ?',
        whereArgs: [category, periodDays, today],
        limit: 1,
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false; // On any DB issue, fall through to a normal sync.
    }
  }

  /// Aggregated market summary (total GMV, sales, avg price/commission/growth)
  /// for [category]/[periodDays], computed from the latest stored product
  /// trends. Used to size the funnel / ad budget in the Micro screen.
  Future<FastmossCategorySummary> getCategorySummary(String category, {int periodDays = 7}) async {
    final items = await getCategoryTrends(category, periodDays: periodDays);
    return FastmossCategorySummary.fromProducts(category, items, periodDays: periodDays);
  }

  // ---------------------------------------------------------------------------
  // Official FastMoss Open API — "Fully Managed" ranking (feeds the AI CMO)
  // ---------------------------------------------------------------------------

  /// POSTs to an Open API endpoint with Bearer auth. Returns the decoded body
  /// (or `null` on missing token / error) so callers can parse defensively.
  Future<dynamic> _postOpenApi(String path, Map<String, dynamic> body) async {
    final String base;
    final Map<String, String> headers;

    if (usesProxy) {
      // Proxy injects credentials server-side; client sends none.
      base = proxyUrl.endsWith('/')
          ? proxyUrl.substring(0, proxyUrl.length - 1)
          : proxyUrl;
      headers = const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
    } else {
      base = openApiBase;
      final auth = await _openApiHeaders();
      if (auth == null) return null;
      headers = auth;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$base$path'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        // ignore: avoid_print
        print('FastMoss OpenAPI $path error ${response.statusCode}.');
        return null;
      }
      final decoded = jsonDecode(response.body);
      final code = decoded is Map ? decoded['code'] : null;
      if (code != null && code != 0) {
        // ignore: avoid_print
        print('FastMoss OpenAPI $path code=$code: '
            '${decoded['message'] ?? decoded['msg'] ?? ''}');
      }
      return decoded;
    } catch (e) {
      // ignore: avoid_print
      print('FastMoss OpenAPI $path exception: $e');
      return null;
    }
  }

  /// Builds the auth headers for an Open API call.
  ///
  /// The FastMoss developer console only issues a **Name** (client identifier)
  /// and a **Client Secret** — there is no separate signing key. So the Client
  /// Secret is sent directly as the credential:
  ///   - `Authorization: Bearer <client_secret>`
  ///   - `access-key: <name>` (client identifier, e.g. "finmatrix")
  ///
  /// Falls back to a plain session/Bearer token when only that is configured.
  /// Returns `null` when nothing is available (caller falls back to seed data).
  Future<Map<String, String>?> _openApiHeaders() async {
    final appId = await SecureConfigService.instance.getFastmossAppId();
    final secret = await SecureConfigService.instance.getFastmossSecret();

    if (secret != null && secret.isNotEmpty) {
      return {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $secret',
        if (appId != null && appId.isNotEmpty) 'access-key': appId,
      };
    }

    // Legacy fallback: session/Bearer token only.
    final token = await _getToken();
    if (token == null) return null;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Computes a request signature, kept for FastMoss accounts whose docs require
  /// signed requests. Not used by the default header flow above (the standard
  /// Name + Client Secret console only needs the secret sent directly), but
  /// retained + tested so it can be wired in without a rewrite if needed.
  ///
  ///   `sign = md5(name + nonce + timestamp + secret)` → lowercase hex.
  String signOpenApi({
    required String appId,
    required String secret,
    required String timestamp,
    required String nonce,
  }) {
    final raw = '$appId$nonce$timestamp$secret';
    return md5.convert(utf8.encode(raw)).toString();
  }

  /// Random 16-char hex nonce (available for signed-request accounts).
  // ignore: unused_element
  String _nonce() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(8, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Builds the required `date_info` object from a [periodDays] window:
  /// 30+ → month, 7+ → ISO week, else → day.
  Map<String, String> buildDateInfo(int periodDays, [DateTime? date]) {
    final d = date ?? DateTime.now().subtract(const Duration(days: 2));
    if (periodDays >= 30) return {'type': 'month', 'value': _ym(d)};
    if (periodDays >= 7) return {'type': 'week', 'value': _isoYearWeek(d)};
    return {'type': 'day', 'value': _ymd(d)};
  }

  /// `POST /product/v1/rank/fullyManaged` — top fully-managed products.
  Future<List<FmFullyManagedProduct>> fetchFullyManagedProducts({
    String region = 'US',
    int? categoryId,
    int page = 1,
    int pagesize = 10,
    String orderField = 'units_sold',
    int periodDays = 7,
    DateTime? date,
  }) async {
    final body = {
      'filter': {
        'region': region,
        if (categoryId != null) 'category_id': categoryId,
        'date_info': buildDateInfo(periodDays, date),
      },
      'orderby': [
        {'field': orderField, 'order': 'desc'}
      ],
      'page': page,
      'pagesize': pagesize,
    };
    final json = await _postOpenApi('/product/v1/rank/fullyManaged', body);
    if (json == null) return [];
    return parseFullyManagedProducts(json, region: region);
  }

  /// `POST /shop/v1/rank/fullyManaged` — top fully-managed shops.
  Future<List<FmFullyManagedShop>> fetchFullyManagedShops({
    String region = 'US',
    int? categoryId,
    int? shopType,
    int page = 1,
    int pagesize = 10,
    String orderField = 'units_sold',
    int periodDays = 7,
    DateTime? date,
  }) async {
    final body = {
      'filter': {
        'region': region,
        if (categoryId != null) 'category_id': categoryId,
        if (shopType != null) 'shop_type': shopType,
        'date_info': buildDateInfo(periodDays, date),
      },
      'orderby': [
        {'field': orderField, 'order': 'desc'}
      ],
      'page': page,
      'pagesize': pagesize,
    };
    final json = await _postOpenApi('/shop/v1/rank/fullyManaged', body);
    if (json == null) return [];
    return parseFullyManagedShops(json);
  }

  /// Pure parser for the fully-managed **product** response.
  List<FmFullyManagedProduct> parseFullyManagedProducts(dynamic json,
      {String region = ''}) {
    return _extractList(json)
        .whereType<Map>()
        .map((e) => FmFullyManagedProduct.fromApi(
              Map<String, dynamic>.from(e),
              fallbackRegion: region,
            ))
        .toList();
  }

  /// Pure parser for the fully-managed **shop** response.
  List<FmFullyManagedShop> parseFullyManagedShops(dynamic json) {
    return _extractList(json)
        .whereType<Map>()
        .map((e) => FmFullyManagedShop.fromApi(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// `POST /product/v1/rank/topSelling` — top-selling products.
  /// Supports VN (and other SEA/APAC + Western markets); primary CMO source.
  Future<List<FmFullyManagedProduct>> fetchTopSellingProducts({
    String region = 'VN',
    int? categoryId,
    int page = 1,
    int pagesize = 30,
    String orderField = 'gmv',
    int periodDays = 7,
    DateTime? date,
  }) async {
    final body = {
      'filter': {
        'region': region,
        if (categoryId != null) 'category_id': categoryId,
        'date_info': buildDateInfo(periodDays, date),
      },
      'orderby': [
        {'field': orderField, 'order': 'desc'}
      ],
      'page': page,
      'pagesize': pagesize,
    };
    final json = await _postOpenApi('/product/v1/rank/topSelling', body);
    if (json == null) return [];
    return parseFullyManagedProducts(json, region: region);
  }

  /// `POST /shop/v1/rank/topSelling` — top-selling shops. Supports VN.
  Future<List<FmFullyManagedShop>> fetchTopSellingShops({
    String region = 'VN',
    int? categoryId,
    int? shopType,
    int? isCrossBorder,
    int page = 1,
    int pagesize = 30,
    String orderField = 'units_sold',
    int periodDays = 7,
    DateTime? date,
  }) async {
    final body = {
      'filter': {
        'region': region,
        if (categoryId != null) 'category_id': categoryId,
        if (shopType != null) 'shop_type': shopType,
        if (isCrossBorder != null) 'is_cross_border': isCrossBorder,
        'date_info': buildDateInfo(periodDays, date),
      },
      'orderby': [
        {'field': orderField, 'order': 'desc'}
      ],
      'page': page,
      'pagesize': pagesize,
    };
    final json = await _postOpenApi('/shop/v1/rank/topSelling', body);
    if (json == null) return [];
    return parseFullyManagedShops(json);
  }

  /// Builds the AI CMO's [TikTokAdMetrics] input from real market ranking data.
  ///
  /// Endpoint strategy (adapts to whatever the API package is licensed for):
  ///   1. **Top Selling** for [region] (supports VN) when available.
  ///   2. Fallback to **Fully Managed** ranking. Because fully-managed only
  ///      covers cross-border markets (US/GB/…), a VN/unsupported [region] is
  ///      mapped to [fullyManagedFallbackRegion] (default `US`).
  ///
  /// Returns `null` when nothing is available (no token / blocked / empty) so
  /// the caller can fall back to demo data.
  Future<TikTokAdMetrics?> fetchCmoMetrics({
    String region = 'VN',
    int? categoryId,
    int periodDays = 7,
    int pagesize = 10,
    double cogsRatio = 0.55,
    double? gmvToVnd,
    String fullyManagedFallbackRegion = 'US',
  }) async {
    // 1) Try Top Selling for the requested region (best for VN).
    var products = await fetchTopSellingProducts(
      region: region,
      categoryId: categoryId,
      periodDays: periodDays,
      pagesize: pagesize,
    );
    var effectiveRegion = region;

    // 2) Fallback to Fully Managed (cross-border) when Top Selling is empty or
    //    not licensed for this account.
    if (products.isEmpty) {
      effectiveRegion = fullyManagedRegions.contains(region.toUpperCase())
          ? region
          : fullyManagedFallbackRegion;
      products = await fetchFullyManagedProducts(
        region: effectiveRegion,
        categoryId: categoryId,
        periodDays: periodDays,
        pagesize: pagesize,
      );
    }

    if (products.isEmpty) return null;
    return buildCmoMetricsFromProducts(
      products,
      region: effectiveRegion,
      periodDays: periodDays,
      cogsRatio: cogsRatio,
      usdToVnd: gmvToVnd ?? regionGmvToVnd(effectiveRegion),
    );
  }

  /// Pure mapping: fully-managed products → CMO [TikTokAdMetrics].
  TikTokAdMetrics buildCmoMetricsFromProducts(
    List<FmFullyManagedProduct> products, {
    String region = 'US',
    int periodDays = 7,
    double cogsRatio = 0.55,
    double usdToVnd = usdToVndFallback,
  }) {
    final now = DateTime.now();
    return TikTokAdMetrics.fromJson({
      'shop_id': 'fastmoss:$region',
      'period_start': _ymd(now.subtract(Duration(days: periodDays))),
      'period_end': _ymd(now),
      'cogs_ratio': cogsRatio,
      'videos':
          products.map((p) => p.toCmoVideoJson(usdToVnd: usdToVnd)).toList(),
    });
  }

  /// Normalizes the common `{data:{list:[]}}`, `{data:[]}` and `[]` shapes.
  List _extractList(dynamic json) {
    if (json is List) return json;
    if (json is Map) {
      final data = json['data'];
      if (data is List) return data;
      if (data is Map) {
        final list = data['list'] ?? data['items'] ?? data['rows'];
        if (list is List) return list;
      }
    }
    return const [];
  }

  String _ymd(DateTime d) => d.toIso8601String().split('T')[0];

  String _ym(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// ISO-8601 year-week string, e.g. "2026-18".
  String _isoYearWeek(DateTime d) {
    final date = DateTime.utc(d.year, d.month, d.day);
    // ISO weeks start on Monday; week 1 contains the first Thursday.
    final thursday = date.add(Duration(days: 4 - (date.weekday)));
    final firstThursday = DateTime.utc(thursday.year, 1, 1).add(
      Duration(days: (4 - DateTime.utc(thursday.year, 1, 1).weekday) % 7),
    );
    final week = 1 + (thursday.difference(firstThursday).inDays ~/ 7);
    return '${thursday.year}-${week.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------------------
  // Creator / video trends
  // ---------------------------------------------------------------------------

  /// Fetches trending creators/videos for [category] from FastMoss.
  Future<List<FastmossCreatorTrend>> fetchCreatorTrends(String category, {int periodDays = 7}) async {
    final token = await _getToken();
    if (token == null) return [];

    final catId = categoryTaxonomy[category]?.primaryId ?? '';
    final snapshotDate = DateTime.now().toIso8601String().split('T')[0];
    final url = '$_creatorUrl?category=$catId&region=$region&date_type=$periodDays&page=1&size=30&sort=gmv';

    try {
      final response = await http
          .get(Uri.parse(url), headers: _headers(token))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        // ignore: avoid_print
        print('FastMoss creator API error ${response.statusCode} (blocked or auth).');
        return [];
      }
      return parseCreatorResponse(jsonDecode(response.body),
          category: category, snapshotDate: snapshotDate, periodDays: periodDays);
    } catch (e) {
      // ignore: avoid_print
      print('FastMoss creator fetch exception: $e');
      return [];
    }
  }

  /// Pure parser for the creator ranking response.
  List<FastmossCreatorTrend> parseCreatorResponse(
    dynamic json, {
    required String category,
    required String snapshotDate,
    int periodDays = 7,
  }) {
    List? items;
    if (json is Map) {
      final data = json['data'];
      if (data is List) {
        items = data;
      } else if (data is Map) {
        items = (data['list'] ?? data['items'] ?? data['rows']) as List?;
      }
    } else if (json is List) {
      items = json;
    }
    if (items == null) return [];

    return items
        .whereType<Map>()
        .map((e) => FastmossCreatorTrend.fromApi(
              Map<String, dynamic>.from(e),
              category: category,
              snapshotDate: snapshotDate,
              periodDays: periodDays,
            ))
        .toList();
  }

  /// Fetches (or seeds) creator trends for [category]/[periodDays] and upserts.
  /// Self-throttles to one network sync per day (see [syncCategoryTrends]).
  Future<int> syncCreatorTrends(String category,
      {int periodDays = 7, bool force = false}) async {
    if (!force && await _hasCreatorSnapshotForToday(category, periodDays)) {
      return 0;
    }
    var points = await fetchCreatorTrends(category, periodDays: periodDays);

    if (points.isEmpty) {
      final existing = await getCreatorTrends(category, periodDays: periodDays);
      if (existing.isNotEmpty) return 0;
      points = _seedCreators(category, periodDays);
    }
    if (points.isEmpty) return 0;

    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (final p in points) {
      batch.insert(
        'fastmoss_creator_trend',
        {...p.toDbMap(), 'source': _source},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    return points.length;
  }

  /// True when a creator-trend snapshot dated **today** exists (daily throttle).
  Future<bool> _hasCreatorSnapshotForToday(String category, int periodDays) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'fastmoss_creator_trend',
        columns: ['snapshot_date'],
        where: 'category = ? AND period_days = ? AND snapshot_date = ?',
        whereArgs: [category, periodDays, today],
        limit: 1,
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Latest stored creator trends for [category]/[periodDays], highest GMV first.
  Future<List<FastmossCreatorTrend>> getCreatorTrends(String category,
      {int periodDays = 7, int limit = 30}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'fastmoss_creator_trend',
      where: 'category = ? AND period_days = ?',
      whereArgs: [category, periodDays],
      orderBy: 'snapshot_date DESC, gmv_vnd DESC',
      limit: limit,
    );
    return rows.map((r) => FastmossCreatorTrend.fromDbMap(r)).toList();
  }

  /// Category-appropriate sample trends used when no token / blocked.
  /// Deterministic so the UI is stable across reloads. GMV/sales scale with
  /// the [periodDays] window (30-day ≈ ~3.6× the 7-day baseline).
  List<FastmossProductTrend> _seedTrends(String category, int periodDays) {
    final date = DateTime.now().toIso8601String().split('T')[0];
    final scale = periodDays >= 30 ? 3.6 : 1.0;
    final seeds = _seedCatalog[category] ?? _seedCatalog['Tiêu dùng']!;
    return seeds
        .map((s) => FastmossProductTrend(
              category: category,
              productName: s['name'] as String,
              shopName: s['shop'] as String,
              gmvVnd: (s['gmv'] as num).toDouble() * scale,
              sales: ((s['sales'] as int) * scale).round(),
              priceVnd: (s['price'] as num).toDouble(),
              growthPct: (s['growth'] as num).toDouble(),
              commissionPct: (s['commission'] as num).toDouble(),
              periodDays: periodDays,
              snapshotDate: date,
            ))
        .toList();
  }

  static const Map<String, List<Map<String, dynamic>>> _seedCatalog = {
    'Thời trang': [
      {'name': 'Áo thun oversize form rộng unisex', 'shop': 'Local Brand VN', 'gmv': 2450000000, 'sales': 12400, 'price': 199000, 'growth': 48.2, 'commission': 18},
      {'name': 'Quần jean baggy lưng cao', 'shop': 'Denim House', 'gmv': 1820000000, 'sales': 7300, 'price': 289000, 'growth': 33.5, 'commission': 15},
      {'name': 'Set đồ nữ công sở thanh lịch', 'shop': 'Elegant Studio', 'gmv': 1310000000, 'sales': 5100, 'price': 359000, 'growth': 21.0, 'commission': 20},
      {'name': 'Váy hai dây lụa mùa hè', 'shop': 'Summer Vibes', 'gmv': 980000000, 'sales': 6200, 'price': 159000, 'growth': 62.4, 'commission': 22},
      {'name': 'Áo khoác gió thể thao', 'shop': 'Sporty Life', 'gmv': 850000000, 'sales': 4500, 'price': 249000, 'growth': 15.8, 'commission': 15},
      {'name': 'Chân váy tennis xếp ly', 'shop': 'Teen Style', 'gmv': 720000000, 'sales': 5800, 'price': 129000, 'growth': 28.4, 'commission': 20},
      {'name': 'Áo sơ mi lụa cổ V', 'shop': 'Lady Fashion', 'gmv': 680000000, 'sales': 3200, 'price': 299000, 'growth': 12.5, 'commission': 18},
      {'name': 'Quần jogger thun tăm', 'shop': 'Lazy Wear', 'gmv': 610000000, 'sales': 4800, 'price': 189000, 'growth': 42.1, 'commission': 16},
      {'name': 'Đầm body len tăm co giãn', 'shop': 'Sexy Curve', 'gmv': 590000000, 'sales': 3900, 'price': 219000, 'growth': 37.6, 'commission': 20},
      {'name': 'Áo croptop ôm body', 'shop': 'Girl Power', 'gmv': 540000000, 'sales': 6500, 'price': 99000, 'growth': 55.2, 'commission': 25},
      {'name': 'Quần short jean rách', 'shop': 'Bad Boy Denim', 'gmv': 510000000, 'sales': 3100, 'price': 239000, 'growth': 18.9, 'commission': 15},
      {'name': 'Áo hoodie nỉ ngoại', 'shop': 'Winter Chill', 'gmv': 480000000, 'sales': 2200, 'price': 329000, 'growth': 9.4, 'commission': 12},
      {'name': 'Set yếm váy tiểu thư', 'shop': 'Cute Corner', 'gmv': 450000000, 'sales': 1800, 'price': 389000, 'growth': 25.1, 'commission': 22},
      {'name': 'Áo polo nam basic', 'shop': 'Gentle Shop', 'gmv': 420000000, 'sales': 2900, 'price': 199000, 'growth': 14.7, 'commission': 15},
      {'name': 'Quần tây baggy công sở', 'shop': 'Office Pro', 'gmv': 390000000, 'sales': 1500, 'price': 349000, 'growth': 8.2, 'commission': 18},
      {'name': 'Váy hoa nhí vintage', 'shop': 'Old Soul', 'gmv': 360000000, 'sales': 2100, 'price': 259000, 'growth': 31.8, 'commission': 20},
      {'name': 'Áo len cardigan mỏng', 'shop': 'Soft Touch', 'gmv': 330000000, 'sales': 2500, 'price': 179000, 'growth': 22.3, 'commission': 18},
      {'name': 'Quần legging nâng mông', 'shop': 'Gym Queen', 'gmv': 310000000, 'sales': 2800, 'price': 149000, 'growth': 45.9, 'commission': 16},
      {'name': 'Áo 2 dây lụa satin', 'shop': 'Night Out', 'gmv': 290000000, 'sales': 3400, 'price': 119000, 'growth': 39.4, 'commission': 22},
      {'name': 'Set đồ ngủ pijama lụa', 'shop': 'Sweet Dream', 'gmv': 270000000, 'sales': 1200, 'price': 299000, 'growth': 16.2, 'commission': 20},
      {'name': 'Áo khoác denim oversize', 'shop': 'Street King', 'gmv': 250000000, 'sales': 900, 'price': 429000, 'growth': 5.7, 'commission': 15},
      {'name': 'Quần kaki ống suông', 'shop': 'Smart Casual', 'gmv': 230000000, 'sales': 1100, 'price': 279000, 'growth': 11.4, 'commission': 18},
      {'name': 'Váy trễ vai dự tiệc', 'shop': 'Party Girl', 'gmv': 210000000, 'sales': 600, 'price': 499000, 'growth': 28.6, 'commission': 25},
      {'name': 'Áo thun gân cổ lọ', 'shop': 'Basic Needs', 'gmv': 190000000, 'sales': 2400, 'price': 89000, 'growth': 19.1, 'commission': 20},
      {'name': 'Quần culottes lụa', 'shop': 'Flowy Style', 'gmv': 170000000, 'sales': 1300, 'price': 189000, 'growth': 14.3, 'commission': 16},
      {'name': 'Set vest nữ thời thượng', 'shop': 'Boss Lady', 'gmv': 150000000, 'sales': 300, 'price': 799000, 'growth': 7.5, 'commission': 20},
      {'name': 'Áo blazer form rộng', 'shop': 'Modernist', 'gmv': 130000000, 'sales': 450, 'price': 399000, 'growth': 10.2, 'commission': 18},
      {'name': 'Chân váy chữ A caro', 'shop': 'Preppy Look', 'gmv': 110000000, 'sales': 950, 'price': 159000, 'growth': 24.8, 'commission': 20},
      {'name': 'Áo tank top nam tập gym', 'shop': 'Beast Mode', 'gmv': 90000000, 'sales': 1100, 'price': 99000, 'growth': 33.1, 'commission': 15},
      {'name': 'Đầm maxi đi biển', 'shop': 'Ocean Breeze', 'gmv': 80000000, 'sales': 250, 'price': 459000, 'growth': 62.9, 'commission': 22},
    ],
    'Ăn uống': [
      {'name': 'Combo hạt dinh dưỡng mix 5 loại', 'shop': 'Healthy Nuts', 'gmv': 1650000000, 'sales': 15800, 'price': 129000, 'growth': 54.1, 'commission': 25},
      {'name': 'Cà phê phin giấy pha sẵn', 'shop': 'Viet Coffee Co', 'gmv': 1240000000, 'sales': 21000, 'price': 89000, 'growth': 40.3, 'commission': 20},
      {'name': 'Bánh tráng phơi sương Tây Ninh', 'shop': 'Đặc Sản 3 Miền', 'gmv': 870000000, 'sales': 18400, 'price': 59000, 'growth': 71.6, 'commission': 28},
      {'name': 'Trà sữa hòa tan đóng gói', 'shop': 'Milk Tea Lab', 'gmv': 640000000, 'sales': 9600, 'price': 99000, 'growth': 18.9, 'commission': 24},
      {'name': 'Khô gà lá chanh loại 1', 'shop': 'Snack Time', 'gmv': 580000000, 'sales': 7200, 'price': 105000, 'growth': 35.2, 'commission': 25},
      {'name': 'Granola siêu hạt ăn kiêng', 'shop': 'Fit Food', 'gmv': 510000000, 'sales': 4500, 'price': 149000, 'growth': 22.8, 'commission': 20},
      {'name': 'Mực rim me Nha Trang', 'shop': 'Sea Food Deli', 'gmv': 480000000, 'sales': 5900, 'price': 95000, 'growth': 48.1, 'commission': 26},
      {'name': 'Trà mãng cầu xiêm đặc sản', 'shop': 'Nature Tea', 'gmv': 420000000, 'sales': 3800, 'price': 159000, 'growth': 65.4, 'commission': 22},
      {'name': 'Cơm cháy siêu chà bông', 'shop': 'Crispy Rice', 'gmv': 390000000, 'sales': 8400, 'price': 65000, 'growth': 29.7, 'commission': 28},
      {'name': 'Hạt điều rang muối vỏ lụa', 'shop': 'Cashew King', 'gmv': 360000000, 'sales': 2400, 'price': 189000, 'growth': 15.6, 'commission': 20},
      {'name': 'Bột ngũ cốc dinh dưỡng 22 loại hạt', 'shop': 'Pure Grain', 'gmv': 330000000, 'sales': 1900, 'price': 229000, 'growth': 12.3, 'commission': 18},
      {'name': 'Mật ong hoa nhãn nguyên chất', 'shop': 'Bee Farm', 'gmv': 310000000, 'sales': 1500, 'price': 289000, 'growth': 8.9, 'commission': 15},
      {'name': 'Táo đỏ Tân Cương thượng hạng', 'shop': 'Herb Store', 'gmv': 290000000, 'sales': 2200, 'price': 179000, 'growth': 42.1, 'commission': 20},
      {'name': 'Đậu phộng tỏi ớt hũ 500g', 'shop': 'Spicy Nut', 'gmv': 270000000, 'sales': 6400, 'price': 59000, 'growth': 37.8, 'commission': 25},
      {'name': 'Bún gạo lứt ăn kiêng', 'shop': 'Healthy Carb', 'gmv': 250000000, 'sales': 4800, 'price': 75000, 'growth': 55.6, 'commission': 22},
      {'name': 'Bánh gấu nhân kem sữa', 'shop': 'Sweetie', 'gmv': 230000000, 'sales': 7500, 'price': 45000, 'growth': 21.4, 'commission': 28},
      {'name': 'Rong biển cháy tỏi giòn rụm', 'shop': 'Green Snack', 'gmv': 210000000, 'sales': 5200, 'price': 69000, 'growth': 49.2, 'commission': 26},
      {'name': 'Bột cần tây sấy lạnh nguyên chất', 'shop': 'Green Detox', 'gmv': 190000000, 'sales': 1100, 'price': 249000, 'growth': 68.3, 'commission': 20},
      {'name': 'Bánh trung thu handmade ít ngọt', 'shop': 'Moon Cake', 'gmv': 170000000, 'sales': 450, 'price': 450000, 'growth': 150.0, 'commission': 18},
      {'name': 'Nho khô Ninh Thuận không hạt', 'shop': 'Vineyard', 'gmv': 150000000, 'sales': 1800, 'price': 120000, 'growth': 24.7, 'commission': 22},
      {'name': 'Khô bò que vị truyền thống', 'shop': 'Beef Jerky', 'gmv': 130000000, 'sales': 750, 'price': 220000, 'growth': 18.2, 'commission': 25},
      {'name': 'Trà dưỡng nhan 7 vị', 'shop': 'Beauty Tea', 'gmv': 110000000, 'sales': 1300, 'price': 119000, 'growth': 33.9, 'commission': 20},
      {'name': 'Bánh pía Sóc Trăng nhân trứng muối', 'shop': 'Pia House', 'gmv': 100000000, 'sales': 1600, 'price': 85000, 'growth': 9.5, 'commission': 24},
      {'name': 'Thanh gạo lứt chà bông', 'shop': 'Brown Rice', 'gmv': 90000000, 'sales': 2400, 'price': 55000, 'growth': 44.1, 'commission': 26},
      {'name': 'Chuối hột sấy dẻo không đường', 'shop': 'Banana Farm', 'gmv': 80000000, 'sales': 1200, 'price': 89000, 'growth': 12.6, 'commission': 22},
      {'name': 'Bánh đa nem không cần nhúng nước', 'shop': 'Spring Roll', 'gmv': 70000000, 'sales': 3500, 'price': 25000, 'growth': 6.8, 'commission': 30},
      {'name': 'Tương ớt Mường Khương cay nồng', 'shop': 'Hillside', 'gmv': 60000000, 'sales': 1800, 'price': 45000, 'growth': 25.4, 'commission': 28},
      {'name': 'Mắm tép chưng thịt Hàng Bè', 'shop': 'Old Hanoi', 'gmv': 50000000, 'sales': 650, 'price': 95000, 'growth': 15.2, 'commission': 25},
      {'name': 'Bánh cáy Thái Bình chính gốc', 'shop': 'Heritage', 'gmv': 40000000, 'sales': 1100, 'price': 48000, 'growth': 8.7, 'commission': 26},
      {'name': 'Chè dưỡng nhan đóng chai', 'shop': 'Cool Drink', 'gmv': 30000000, 'sales': 2500, 'price': 15000, 'growth': 58.9, 'commission': 20},
    ],
    'Tiêu dùng': [
      {'name': 'Nước giặt hương nước hoa 3.5L', 'shop': 'Clean Home', 'gmv': 1980000000, 'sales': 16700, 'price': 149000, 'growth': 29.7, 'commission': 16},
      {'name': 'Khăn giấy rút cao cấp lốc 30 gói', 'shop': 'Soft Paper', 'gmv': 1120000000, 'sales': 24500, 'price': 79000, 'growth': 22.4, 'commission': 12},
      {'name': 'Hộp đựng thực phẩm nắp khóa 10 món', 'shop': 'Kitchen Plus', 'gmv': 760000000, 'sales': 8900, 'price': 189000, 'growth': 44.8, 'commission': 19},
      {'name': 'Nước lau sàn tinh dầu sả chanh', 'shop': 'Fresh Living', 'gmv': 540000000, 'sales': 11200, 'price': 69000, 'growth': 15.3, 'commission': 14},
      {'name': 'Bàn chải điện sóng âm thông minh', 'shop': 'Dental Care', 'gmv': 490000000, 'sales': 1800, 'price': 359000, 'growth': 62.1, 'commission': 20},
      {'name': 'Dầu gội thảo dược ngăn rụng tóc', 'shop': 'Nature Hair', 'gmv': 450000000, 'sales': 2600, 'price': 229000, 'growth': 38.4, 'commission': 18},
      {'name': 'Bộ lau nhà xoay 360 độ', 'shop': 'Smart House', 'gmv': 410000000, 'sales': 1500, 'price': 389000, 'growth': 25.6, 'commission': 15},
      {'name': 'Túi rác tự phân hủy sinh học', 'shop': 'Green Life', 'gmv': 380000000, 'sales': 12500, 'price': 45000, 'growth': 12.9, 'commission': 12},
      {'name': 'Xịt thơm quần áo lưu hương lâu', 'shop': 'Aroma', 'gmv': 350000000, 'sales': 5400, 'price': 89000, 'growth': 55.7, 'commission': 22},
      {'name': 'Kem đánh răng trắng răng thảo mộc', 'shop': 'Herb Smile', 'gmv': 320000000, 'sales': 6200, 'price': 75000, 'growth': 19.3, 'commission': 16},
      {'name': 'Khăn lau tay nhà bếp siêu thấm', 'shop': 'Kitchen Pro', 'gmv': 290000000, 'sales': 8900, 'price': 49000, 'growth': 31.8, 'commission': 14},
      {'name': 'Nước rửa chén tinh chất trà xanh', 'shop': 'Sparkle', 'gmv': 270000000, 'sales': 9200, 'price': 39000, 'growth': 8.5, 'commission': 10},
      {'name': 'Máy hút bụi mini cầm tay', 'shop': 'Gadget Home', 'gmv': 250000000, 'sales': 1100, 'price': 299000, 'growth': 48.2, 'commission': 18},
      {'name': 'Hộp đựng giày trong suốt', 'shop': 'Organizer', 'gmv': 230000000, 'sales': 7800, 'price': 39000, 'growth': 22.4, 'commission': 15},
      {'name': 'Kệ để gia vị xoay 360', 'shop': 'Kitchen Hero', 'gmv': 210000000, 'sales': 1400, 'price': 219000, 'growth': 35.1, 'commission': 19},
      {'name': 'Bộ 5 khăn tắm cotton 100%', 'shop': 'Soft Touch', 'gmv': 190000000, 'sales': 950, 'price': 289000, 'growth': 14.7, 'commission': 16},
      {'name': 'Đèn bắt muỗi thông minh', 'shop': 'Safe Home', 'gmv': 170000000, 'sales': 1200, 'price': 189000, 'growth': 72.3, 'commission': 20},
      {'name': 'Dụng cụ cắt tỉa rau củ đa năng', 'shop': 'Chef Tool', 'gmv': 150000000, 'sales': 1800, 'price': 129000, 'growth': 29.8, 'commission': 22},
      {'name': 'Túi đựng quần áo khung sắt', 'shop': 'Box Pro', 'gmv': 130000000, 'sales': 900, 'price': 199000, 'growth': 11.2, 'commission': 18},
      {'name': 'Móc treo quần áo đa năng 9 lỗ', 'shop': 'Closet Master', 'gmv': 110000000, 'sales': 5200, 'price': 29000, 'growth': 45.6, 'commission': 15},
      {'name': 'Thảm lau chân san hô siêu thấm', 'shop': 'Floor Care', 'gmv': 100000000, 'sales': 3400, 'price': 45000, 'growth': 19.4, 'commission': 16},
      {'name': 'Bình nước giữ nhiệt 1000ml', 'shop': 'Hydrate', 'gmv': 90000000, 'sales': 750, 'price': 159000, 'growth': 24.1, 'commission': 15},
      {'name': 'Găng tay cao su rửa bát', 'shop': 'Hand Guard', 'gmv': 80000000, 'sales': 4200, 'price': 25000, 'growth': 5.8, 'commission': 12},
      {'name': 'Xịt khử mùi giày nano bạc', 'shop': 'Fresh Step', 'gmv': 70000000, 'sales': 1500, 'price': 79000, 'growth': 37.9, 'commission': 20},
      {'name': 'Lõi lọc nước vòi sen khử Clo', 'shop': 'Pure Shower', 'gmv': 60000000, 'sales': 600, 'price': 149000, 'growth': 52.3, 'commission': 22},
      {'name': 'Kéo cắt gà SK5 Nhật Bản', 'shop': 'Iron Cut', 'gmv': 50000000, 'sales': 850, 'price': 89000, 'growth': 14.6, 'commission': 25},
      {'name': 'Giấy bạc nướng thực phẩm', 'shop': 'BBQ Fan', 'gmv': 40000000, 'sales': 2100, 'price': 29000, 'growth': 9.2, 'commission': 15},
      {'name': 'Bông tẩy trang 222 miếng', 'shop': 'Skincare Box', 'gmv': 30000000, 'sales': 4800, 'price': 15000, 'growth': 12.8, 'commission': 10},
      {'name': 'Viên tẩy bồn cầu vỉ 10 viên', 'shop': 'Toilet King', 'gmv': 20000000, 'sales': 1200, 'price': 25000, 'growth': 6.5, 'commission': 12},
      {'name': 'Que thông cống Sani Stick', 'shop': 'Drain Care', 'gmv': 10000000, 'sales': 950, 'price': 19000, 'growth': 3.1, 'commission': 15},
    ],
    'Điện tử': [
      {'name': 'Tai nghe Bluetooth chống ồn ANC', 'shop': 'Audio Tech', 'gmv': 3120000000, 'sales': 8600, 'price': 459000, 'growth': 58.9, 'commission': 10},
      {'name': 'Sạc dự phòng 20000mAh sạc nhanh', 'shop': 'Power Store', 'gmv': 2240000000, 'sales': 11300, 'price': 299000, 'growth': 37.2, 'commission': 12},
      {'name': 'Đèn LED để bàn cảm ứng chống cận', 'shop': 'Bright Home', 'gmv': 1180000000, 'sales': 7400, 'price': 219000, 'growth': 26.5, 'commission': 15},
      {'name': 'Giá đỡ điện thoại kẹp bàn xoay 360', 'shop': 'Gadget World', 'gmv': 690000000, 'sales': 14800, 'price': 89000, 'growth': 49.1, 'commission': 18},
      {'name': 'Loa Bluetooth Mini Bass Cực Mạnh', 'shop': 'Sound Max', 'gmv': 620000000, 'sales': 2400, 'price': 349000, 'growth': 42.8, 'commission': 12},
      {'name': 'Chuột không dây Silent 2.4GHz', 'shop': 'PC Master', 'gmv': 580000000, 'sales': 5200, 'price': 129000, 'growth': 19.5, 'commission': 15},
      {'name': 'Cáp sạc 3 trong 1 bọc dù siêu bền', 'shop': 'Link Tech', 'gmv': 510000000, 'sales': 9600, 'price': 69000, 'growth': 31.4, 'commission': 20},
      {'name': 'Bàn phím cơ Blue Switch giá rẻ', 'shop': 'Gamer Zone', 'gmv': 470000000, 'sales': 1100, 'price': 549000, 'growth': 22.6, 'commission': 10},
      {'name': 'Micro thu âm không dây cho TikTok', 'shop': 'Content Creator', 'gmv': 430000000, 'sales': 850, 'price': 689000, 'growth': 75.3, 'commission': 15},
      {'name': 'Quạt mini cầm tay tích điện', 'shop': 'Cool Breeze', 'gmv': 390000000, 'sales': 4200, 'price': 119000, 'growth': 120.0, 'commission': 20},
      {'name': 'Máy phun sương tạo ẩm 500ml', 'shop': 'Air Care', 'gmv': 350000000, 'sales': 1600, 'price': 289000, 'growth': 33.7, 'commission': 18},
      {'name': 'Hub USB Type-C 5 trong 1', 'shop': 'Connect Pro', 'gmv': 320000000, 'sales': 750, 'price': 459000, 'growth': 15.2, 'commission': 12},
      {'name': 'Gậy chụp ảnh tripod bluetooth', 'shop': 'Selfie Pro', 'gmv': 290000000, 'sales': 2100, 'price': 189000, 'growth': 28.9, 'commission': 20},
      {'name': 'Đồng hồ thông minh theo dõi sức khỏe', 'shop': 'Fit Tech', 'gmv': 260000000, 'sales': 450, 'price': 799000, 'growth': 41.6, 'commission': 15},
      {'name': 'Máy xay sinh tố cầm tay sạc USB', 'shop': 'Kitchen Tech', 'gmv': 230000000, 'sales': 900, 'price': 329000, 'growth': 52.4, 'commission': 18},
      {'name': 'Lót chuột cỡ lớn 80x30cm', 'shop': 'Desktop Decor', 'gmv': 210000000, 'sales': 2400, 'price': 99000, 'growth': 14.8, 'commission': 22},
      {'name': 'Pin tiểu AA sạc lại được', 'shop': 'Green Energy', 'gmv': 190000000, 'sales': 1200, 'price': 159000, 'growth': 9.7, 'commission': 15},
      {'name': 'Bộ vệ sinh bàn phím tai nghe 7 in 1', 'shop': 'Clean Tech', 'gmv': 170000000, 'sales': 3200, 'price': 59000, 'growth': 68.2, 'commission': 25},
      {'name': 'Tay cầm chơi game cho điện thoại', 'shop': 'Mobile Game', 'gmv': 150000000, 'sales': 550, 'price': 389000, 'growth': 24.3, 'commission': 12},
      {'name': 'Máy chơi game cầm tay 400 trò', 'shop': 'Retro Play', 'gmv': 130000000, 'sales': 950, 'price': 189000, 'growth': 18.9, 'commission': 20},
      {'name': 'Bút cảm ứng Stylus cho iPad/Android', 'shop': 'Design Tool', 'gmv': 110000000, 'sales': 400, 'price': 359000, 'growth': 31.5, 'commission': 15},
      {'name': 'Đèn LED dây RGB dán bàn', 'shop': 'Light Decor', 'gmv': 100000000, 'sales': 1100, 'price': 119000, 'growth': 49.7, 'commission': 22},
      {'name': 'Kính thực tế ảo VR Box', 'shop': 'Vision Tech', 'gmv': 90000000, 'sales': 250, 'price': 459000, 'growth': 5.4, 'commission': 18},
      {'name': 'Máy massage cổ vai gáy 4 đầu', 'shop': 'Relax Pro', 'gmv': 80000000, 'sales': 150, 'price': 699000, 'growth': 22.1, 'commission': 15},
      {'name': 'Ổ cắm điện thông minh hẹn giờ', 'shop': 'Smart Home', 'gmv': 70000000, 'sales': 650, 'price': 149000, 'growth': 37.8, 'commission': 18},
      {'name': 'Balo laptop chống trộm có cổng sạc', 'shop': 'Carry On', 'gmv': 60000000, 'sales': 200, 'price': 399000, 'growth': 11.6, 'commission': 12},
      {'name': 'Thẻ nhớ 64GB MicroSD Class 10', 'shop': 'Storage Pro', 'gmv': 50000000, 'sales': 450, 'price': 139000, 'growth': 8.2, 'commission': 15},
      {'name': 'Kẹp dây cáp chống rối silicon', 'shop': 'Tidy Desk', 'gmv': 40000000, 'sales': 1800, 'price': 25000, 'growth': 45.9, 'commission': 25},
      {'name': 'Túi chống sốc laptop 14-15 inch', 'shop': 'Laptop Case', 'gmv': 30000000, 'sales': 350, 'price': 99000, 'growth': 14.3, 'commission': 20},
      {'name': 'Vỏ bảo vệ tai nghe Airpods Cute', 'shop': 'Case World', 'gmv': 20000000, 'sales': 1100, 'price': 49000, 'growth': 55.2, 'commission': 30},
    ],
    'Du lịch': [
      {'name': 'Vali kéo khung nhôm size 20 inch', 'shop': 'Travel Gear', 'gmv': 1740000000, 'sales': 4200, 'price': 649000, 'growth': 35.8, 'commission': 12},
      {'name': 'Balo chống nước du lịch 40L', 'shop': 'Outdoor Pro', 'gmv': 1010000000, 'sales': 6100, 'price': 329000, 'growth': 41.6, 'commission': 16},
      {'name': 'Túi đựng đồ cá nhân chống sốc', 'shop': 'Pack Smart', 'gmv': 520000000, 'sales': 9700, 'price': 99000, 'growth': 53.2, 'commission': 20},
      {'name': 'Gối chữ U memory foam du lịch', 'shop': 'Comfort Trip', 'gmv': 410000000, 'sales': 8300, 'price': 129000, 'growth': 19.4, 'commission': 22},
      {'name': 'Lều cắm trại 4 người tự bung', 'shop': 'Camp Life', 'gmv': 380000000, 'sales': 550, 'price': 890000, 'growth': 75.1, 'commission': 15},
      {'name': 'Sạc dự phòng năng lượng mặt trời', 'shop': 'Solar Power', 'gmv': 350000000, 'sales': 950, 'price': 459000, 'growth': 28.4, 'commission': 12},
      {'name': 'Giày trekking chống trượt cao cổ', 'shop': 'Hiker King', 'gmv': 320000000, 'sales': 420, 'price': 950000, 'growth': 15.6, 'commission': 15},
      {'name': 'Bình nước gấp gọn silicon', 'shop': 'Eco Travel', 'gmv': 290000000, 'sales': 2800, 'price': 119000, 'growth': 49.2, 'commission': 20},
      {'name': 'Túi ngủ du lịch siêu nhẹ 1.2kg', 'shop': 'Sleep Tight', 'gmv': 260000000, 'sales': 650, 'price': 489000, 'growth': 22.3, 'commission': 18},
      {'name': 'Bộ chiết mỹ phẩm du lịch 8 món', 'shop': 'Beauty Go', 'gmv': 230000000, 'sales': 3400, 'price': 79000, 'growth': 58.7, 'commission': 25},
      {'name': 'Ổ cắm điện đa năng quốc tế', 'shop': 'Global Plug', 'gmv': 210000000, 'sales': 850, 'price': 259000, 'growth': 37.1, 'commission': 15},
      {'name': 'Đèn pin siêu sáng chiếu xa 500m', 'shop': 'Night Light', 'gmv': 190000000, 'sales': 750, 'price': 289000, 'growth': 18.9, 'commission': 20},
      {'name': 'Võng du lịch có màn chống muỗi', 'shop': 'Relax Pro', 'gmv': 170000000, 'sales': 1100, 'price': 199000, 'growth': 42.6, 'commission': 22},
      {'name': 'Gậy leo núi hợp kim nhôm', 'shop': 'Mountain Peak', 'gmv': 150000000, 'sales': 600, 'price': 249000, 'growth': 12.8, 'commission': 18},
      {'name': 'Túi chống nước điện thoại cao cấp', 'shop': 'Safe Dive', 'gmv': 130000000, 'sales': 5200, 'price': 35000, 'growth': 150.0, 'commission': 30},
      {'name': 'Khăn nén du lịch dạng viên', 'shop': 'Clean Trip', 'gmv': 110000000, 'sales': 9800, 'price': 15000, 'growth': 62.4, 'commission': 25},
      {'name': 'Cân hành lý cầm tay điện tử', 'shop': 'Weight Pro', 'gmv': 100000000, 'sales': 950, 'price': 129000, 'growth': 24.7, 'commission': 18},
      {'name': 'Mũ tai bèo chống nắng kèm khẩu trang', 'shop': 'Sun Guard', 'gmv': 90000000, 'sales': 1400, 'price': 85000, 'growth': 39.2, 'commission': 22},
      {'name': 'Dây đai vali kèm khóa mã số', 'shop': 'Secure Bag', 'gmv': 80000000, 'sales': 1100, 'price': 99000, 'growth': 14.1, 'commission': 20},
      {'name': 'Áo mưa bộ cao cấp đi phượt', 'shop': 'Dry Run', 'gmv': 70000000, 'sales': 350, 'price': 229000, 'growth': 55.6, 'commission': 16},
      {'name': 'Tấm lót cách nhiệt cắm trại', 'shop': 'Base Camp', 'gmv': 60000000, 'sales': 850, 'price': 89000, 'growth': 29.3, 'commission': 15},
      {'name': 'Bếp ga du lịch mini gấp gọn', 'shop': 'Flame Go', 'gmv': 50000000, 'sales': 250, 'price': 259000, 'growth': 18.2, 'commission': 12},
      {'name': 'Xịt chống côn trùng hữu cơ', 'shop': 'Safe Skin', 'gmv': 40000000, 'sales': 650, 'price': 75000, 'growth': 48.9, 'commission': 25},
      {'name': 'Túi y tế cá nhân sơ cứu', 'shop': 'First Aid', 'gmv': 35000000, 'sales': 450, 'price': 99000, 'growth': 33.1, 'commission': 20},
      {'name': 'Kính râm du lịch chống tia UV', 'shop': 'Sunny Day', 'gmv': 30000000, 'sales': 300, 'price': 159000, 'growth': 12.5, 'commission': 22},
      {'name': 'Móc khóa đa năng sinh tồn', 'shop': 'Utility', 'gmv': 25000000, 'sales': 750, 'price': 45000, 'growth': 9.4, 'commission': 25},
      {'name': 'Đệm hơi tự bơm du lịch', 'shop': 'Soft Cloud', 'gmv': 20000000, 'sales': 150, 'price': 499000, 'growth': 21.8, 'commission': 15},
      {'name': 'Adapter đổi nguồn 220V sang 110V', 'shop': 'Power Travel', 'gmv': 15000000, 'sales': 100, 'price': 350000, 'growth': 5.7, 'commission': 18},
      {'name': 'Ô gấp ngược thông minh', 'shop': 'Rainy Day', 'gmv': 10000000, 'sales': 450, 'price': 189000, 'growth': 31.2, 'commission': 20},
      {'name': 'Ví đựng hộ chiếu Passport chống trộm', 'shop': 'Safe Travel', 'gmv': 5000000, 'sales': 200, 'price': 79000, 'growth': 8.9, 'commission': 25},
    ],
  };

  /// Category-appropriate sample creators used when no token / blocked.
  /// Views/GMV scale with the [periodDays] window.
  List<FastmossCreatorTrend> _seedCreators(String category, int periodDays) {
    final date = DateTime.now().toIso8601String().split('T')[0];
    final scale = periodDays >= 30 ? 3.6 : 1.0;
    final seeds = _creatorCatalog[category] ?? _creatorCatalog['Tiêu dùng']!;
    return seeds
        .map((s) => FastmossCreatorTrend(
              category: category,
              creatorName: s['name'] as String,
              handle: s['handle'] as String,
              followers: s['followers'] as int,
              videoTitle: s['video'] as String,
              views: ((s['views'] as int) * scale).round(),
              gmvVnd: (s['gmv'] as num).toDouble() * scale,
              engagementPct: (s['eng'] as num).toDouble(),
              periodDays: periodDays,
              snapshotDate: date,
            ))
        .toList();
  }

  static const Map<String, List<Map<String, dynamic>>> _creatorCatalog = {
    'Thời trang': [
      {'name': 'Mai Streetwear', 'handle': '@maistreet', 'followers': 1250000, 'video': 'Mix đồ đi làm chỉ 300k', 'views': 3400000, 'gmv': 890000000, 'eng': 12.4},
      {'name': 'Linh Try-on', 'handle': '@linhtryon', 'followers': 780000, 'video': 'Haul váy hè 2026', 'views': 2100000, 'gmv': 560000000, 'eng': 9.8},
      {'name': 'Tú Menswear', 'handle': '@tumens', 'followers': 540000, 'video': 'Set đồ nam tối giản', 'views': 1500000, 'gmv': 410000000, 'eng': 8.1},
      {'name': 'Vân Basic', 'handle': '@vanbasic', 'followers': 620000, 'video': 'Phối đồ với áo thun trắng', 'views': 1200000, 'gmv': 320000000, 'eng': 10.5},
      {'name': 'Fashionista Hoàng', 'handle': '@hoangfashion', 'followers': 1500000, 'video': 'Xu hướng Thu Đông 2026', 'views': 4500000, 'gmv': 1200000000, 'eng': 14.2},
      {'name': 'Thảo Review Đồ', 'handle': '@thaoreview', 'followers': 450000, 'video': 'Unboxing set đồ Local Brand', 'views': 950000, 'gmv': 280000000, 'eng': 7.6},
      {'name': 'Đức Sneaker', 'handle': '@ducsneaker', 'followers': 890000, 'video': 'Vệ sinh giày đúng cách', 'views': 2300000, 'gmv': 640000000, 'eng': 11.8},
      {'name': 'Phương Dress Up', 'handle': '@phuongdress', 'followers': 560000, 'video': 'Chọn đầm đi tiệc sang chảnh', 'views': 1400000, 'gmv': 390000000, 'eng': 9.2},
      {'name': 'KOL Thời Trang', 'handle': '@koltime', 'followers': 730000, 'video': 'Top 5 item must-have', 'views': 1800000, 'gmv': 510000000, 'eng': 10.9},
      {'name': 'Z-Style', 'handle': '@zstyle', 'followers': 1100000, 'video': 'OOTD đi học năng động', 'views': 3100000, 'gmv': 820000000, 'eng': 13.5},
      {'name': 'Ngọc Ánh Silk', 'handle': '@ngocanhsilk', 'followers': 320000, 'video': 'Vẻ đẹp từ lụa tơ tằm', 'views': 600000, 'gmv': 180000000, 'eng': 6.8},
      {'name': 'Quân Denim', 'handle': '@quandenim', 'followers': 680000, 'video': 'Phối đồ với quần jean', 'views': 1600000, 'gmv': 430000000, 'eng': 8.7},
      {'name': 'Yến Summer', 'handle': '@yensummer', 'followers': 490000, 'video': 'Set đồ đi biển cực xinh', 'views': 1100000, 'gmv': 310000000, 'eng': 12.1},
      {'name': 'Trí Sporty', 'handle': '@trisport', 'followers': 750000, 'video': 'Gym wear phong cách', 'views': 2000000, 'gmv': 580000000, 'eng': 9.4},
      {'name': 'Hương Office', 'handle': '@huongoffice', 'followers': 420000, 'video': 'Thanh lịch chốn công sở', 'views': 800000, 'gmv': 250000000, 'eng': 8.5},
      {'name': 'Minh Streetwear', 'handle': '@minhstreet', 'followers': 920000, 'video': 'Áo hoodie cho mùa đông', 'views': 2500000, 'gmv': 690000000, 'eng': 11.2},
      {'name': 'Lan Try-on Bag', 'handle': '@lanbags', 'followers': 380000, 'video': 'Review túi xách đi chơi', 'views': 750000, 'gmv': 210000000, 'eng': 7.3},
      {'name': 'Cường Men Style', 'handle': '@cuongmen', 'followers': 640000, 'video': 'Suit nam lịch lãm', 'views': 1500000, 'gmv': 460000000, 'eng': 8.9},
      {'name': 'Vicky Fashion', 'handle': '@vickyfashion', 'followers': 1300000, 'video': 'Makeup & phối đồ đi tiệc', 'views': 3800000, 'gmv': 1050000000, 'eng': 15.6},
      {'name': 'KOL Ngọc', 'handle': '@kolngoc', 'followers': 510000, 'video': 'Đồ ngủ lụa cao cấp', 'views': 1200000, 'gmv': 340000000, 'eng': 13.8},
      {'name': 'Tân Vintage', 'handle': '@tanvintage', 'followers': 280000, 'video': 'Săn đồ cũ giá rẻ', 'views': 550000, 'gmv': 150000000, 'eng': 6.2},
      {'name': 'Ly Aesthetic', 'handle': '@lyaesthetic', 'followers': 840000, 'video': 'Phối đồ tone pastel', 'views': 2100000, 'gmv': 620000000, 'eng': 12.7},
      {'name': 'Dũng Blazer', 'handle': '@dungblazer', 'followers': 460000, 'video': 'Cách mặc blazer không bị già', 'views': 900000, 'gmv': 270000000, 'eng': 7.9},
      {'name': 'Nga Accessories', 'handle': '@ngaacc', 'followers': 390000, 'video': 'Phối phụ kiện làm điểm nhấn', 'views': 850000, 'gmv': 230000000, 'eng': 10.4},
      {'name': 'Bình Streetwear', 'handle': '@binhstreet', 'followers': 770000, 'video': 'Áo thun loang màu unisex', 'views': 1900000, 'gmv': 540000000, 'eng': 9.8},
      {'name': 'Tuyết Lady', 'handle': '@tuyetlady', 'followers': 590000, 'video': 'Chân váy dài cho nấm lùn', 'views': 1300000, 'gmv': 380000000, 'eng': 11.5},
      {'name': 'Khải Classic', 'handle': '@khaiclassic', 'followers': 660000, 'video': 'Giày tây cao cấp', 'views': 1400000, 'gmv': 420000000, 'eng': 8.3},
      {'name': 'My Cute Style', 'handle': '@mycute', 'followers': 950000, 'video': 'Mix đồ phong cách Hàn Quốc', 'views': 2800000, 'gmv': 790000000, 'eng': 14.1},
      {'name': 'Đăng Tech-Fashion', 'handle': '@dangtechf', 'followers': 430000, 'video': 'Đồng hồ & trang phục', 'views': 900000, 'gmv': 260000000, 'eng': 7.5},
      {'name': 'Quỳnh Maxi', 'handle': '@quynhmixi', 'followers': 1050000, 'video': 'Haul đầm maxi đi biển', 'views': 3200000, 'gmv': 910000000, 'eng': 13.2},
    ],
    'Ăn uống': [
      {'name': 'Ăn Sập Sài Gòn', 'handle': '@ansapsg', 'followers': 2100000, 'video': 'Review hạt dinh dưỡng healthy', 'views': 5200000, 'gmv': 1100000000, 'eng': 15.2},
      {'name': 'Bếp Của Mẹ', 'handle': '@bepcuame', 'followers': 960000, 'video': 'Pha cà phê phin sạch tại nhà', 'views': 2800000, 'gmv': 720000000, 'eng': 11.0},
      {'name': 'Foodie Trang', 'handle': '@foodietrang', 'followers': 610000, 'video': 'Đặc sản bánh tráng Tây Ninh', 'views': 1900000, 'gmv': 480000000, 'eng': 13.6},
      {'name': 'Thánh Ăn Cay', 'handle': '@thanhancay', 'followers': 1200000, 'video': 'Thử thách mì cay cấp 7', 'views': 3500000, 'gmv': 850000000, 'eng': 14.8},
      {'name': 'Review Food VN', 'handle': '@reviewfood', 'followers': 820000, 'video': 'Top 5 món ăn vặt TikTok', 'views': 2200000, 'gmv': 610000000, 'eng': 10.4},
      {'name': 'Tiểu Bảo Review', 'handle': '@tieubao', 'followers': 1500000, 'video': 'Khô gà lá chanh cực phẩm', 'views': 4100000, 'gmv': 950000000, 'eng': 12.9},
      {'name': 'Mẹ Bỉm Nấu Ăn', 'handle': '@mebimcook', 'followers': 540000, 'video': 'Thực đơn cơm gia đình 100k', 'views': 1500000, 'gmv': 380000000, 'eng': 9.2},
      {'name': 'Ông Chú Ăn Chơi', 'handle': '@ongchuan', 'followers': 780000, 'video': 'Làm mực rim me tại nhà', 'views': 2000000, 'gmv': 520000000, 'eng': 8.7},
      {'name': 'Eater Hà Nội', 'handle': '@eaterhn', 'followers': 950000, 'video': 'Bún chả gia truyền', 'views': 2700000, 'gmv': 740000000, 'eng': 11.5},
      {'name': 'Healthy Life', 'handle': '@healthylife', 'followers': 480000, 'video': 'Salad ức gà giảm cân', 'views': 1100000, 'gmv': 290000000, 'eng': 12.3},
      {'name': 'Trà Chiều KOL', 'handle': '@trachieu', 'followers': 660000, 'video': 'Review các loại trà hoa', 'views': 1800000, 'gmv': 460000000, 'eng': 10.9},
      {'name': 'Snack Monster', 'handle': '@snackmon', 'followers': 1100000, 'video': 'Haul đồ ăn vặt Trung Quốc', 'views': 3200000, 'gmv': 790000000, 'eng': 13.6},
      {'name': 'Đầu Bếp Nhí', 'handle': '@dabepnhi', 'followers': 320000, 'video': 'Làm bánh gấu nhân kem', 'views': 750000, 'gmv': 190000000, 'eng': 15.1},
      {'name': 'Cà Phê & Chuyện', 'handle': '@cafechuyen', 'followers': 580000, 'video': 'Quán cafe chill Sài Gòn', 'views': 1400000, 'gmv': 360000000, 'eng': 7.8},
      {'name': 'Fruit Lover', 'handle': '@fruitlover', 'followers': 420000, 'video': 'Trái cây sấy dẻo mix vị', 'views': 950000, 'gmv': 260000000, 'eng': 9.5},
      {'name': 'Gia Đình Foodie', 'handle': '@gdfoodie', 'followers': 890000, 'video': 'Mukbang lẩu buffet', 'views': 2500000, 'gmv': 680000000, 'eng': 12.4},
      {'name': 'Vua Đầu Bếp', 'handle': '@vuadaubep', 'followers': 1800000, 'video': 'Bí quyết kho thịt ngon', 'views': 5500000, 'gmv': 1400000000, 'eng': 16.2},
      {'name': 'Sweet Tooth', 'handle': '@sweettooth', 'followers': 610000, 'video': 'Review bánh trung thu handmade', 'views': 1600000, 'gmv': 430000000, 'eng': 13.2},
      {'name': 'Kitchen Tips', 'handle': '@kitchentips', 'followers': 730000, 'video': 'Mẹo bảo quản thực phẩm', 'views': 1900000, 'gmv': 510000000, 'eng': 8.9},
      {'name': 'Đặc Sản Vùng Miền', 'handle': '@dacsanvn', 'followers': 490000, 'video': 'Nho khô Ninh Thuận', 'views': 1200000, 'gmv': 320000000, 'eng': 10.7},
      {'name': 'Thành Thơi Nấu Nướng', 'handle': '@thanhthoi', 'followers': 380000, 'video': 'Canh chua cá lóc', 'views': 850000, 'gmv': 220000000, 'eng': 7.6},
      {'name': 'Youtuber Ăn Uống', 'handle': '@ytan', 'followers': 1050000, 'video': 'Một ngày ăn uống tại Huế', 'views': 3000000, 'gmv': 820000000, 'eng': 11.9},
      {'name': 'Bé Yêu Ăn Dặm', 'handle': '@beyeuad', 'followers': 280000, 'video': 'Bánh flan cho bé', 'views': 600000, 'gmv': 160000000, 'eng': 14.2},
      {'name': 'Trang Nấu Chay', 'handle': '@trangnauchay', 'followers': 460000, 'video': 'Món chay ngon dễ làm', 'views': 1100000, 'gmv': 290000000, 'eng': 9.8},
      {'name': 'KOL Ẩm Thực', 'handle': '@kolamthuc', 'followers': 1300000, 'video': 'Buffet hải sản cao cấp', 'views': 4000000, 'gmv': 1150000000, 'eng': 13.5},
      {'name': 'Chuyện Của Bếp', 'handle': '@chuyenbep', 'followers': 510000, 'video': 'Tương ớt Mường Khương', 'views': 1300000, 'gmv': 350000000, 'eng': 10.6},
      {'name': 'Hot Pot Lover', 'handle': '@hotpot', 'followers': 680000, 'video': 'Review các loại cốt lẩu', 'views': 1700000, 'gmv': 480000000, 'eng': 9.4},
      {'name': 'Món Ngon Mỗi Ngày', 'handle': '@monngon', 'followers': 920000, 'video': 'Sườn xào chua ngọt', 'views': 2600000, 'gmv': 710000000, 'eng': 11.2},
      {'name': 'Anh Chef', 'handle': '@anhchef', 'followers': 350000, 'video': 'Hướng dẫn làm beefsteak', 'views': 800000, 'gmv': 240000000, 'eng': 8.1},
      {'name': 'Vloger Ăn Uống', 'handle': '@vlogerfood', 'followers': 840000, 'video': 'Chè dưỡng nhan mát lạnh', 'views': 2100000, 'gmv': 580000000, 'eng': 12.7},
    ],
    'Tiêu dùng': [
      {'name': 'Nhà Sạch Mỗi Ngày', 'handle': '@nhasach', 'followers': 1400000, 'video': 'Dọn nhà cùng nước giặt thơm', 'views': 3100000, 'gmv': 950000000, 'eng': 10.7},
      {'name': 'Mẹ Bỉm Thông Thái', 'handle': '@mebimtt', 'followers': 890000, 'video': 'Trữ đồ ăn gọn gàng', 'views': 2200000, 'gmv': 610000000, 'eng': 9.3},
      {'name': 'Review Đồ Gia Dụng', 'handle': '@reviewgd', 'followers': 520000, 'video': 'Top hộp đựng đáng mua', 'views': 1400000, 'gmv': 380000000, 'eng': 7.9},
      {'name': 'Mẹo Vặt Nhà Cửa', 'handle': '@meovat', 'followers': 1100000, 'video': 'Tẩy vết bẩn trên áo trắng', 'views': 3500000, 'gmv': 820000000, 'eng': 11.5},
      {'name': 'Home Decor VN', 'handle': '@homedecor', 'followers': 750000, 'video': 'Trang trí phòng ngủ chill', 'views': 2100000, 'gmv': 540000000, 'eng': 12.4},
      {'name': 'Yêu Bếp Nghiện Nhà', 'handle': '@yeubep', 'followers': 1800000, 'video': 'Review nồi chiên không dầu', 'views': 5200000, 'gmv': 1400000000, 'eng': 14.8},
      {'name': 'Smart Home Review', 'handle': '@smartreview', 'followers': 640000, 'video': 'Robot hút bụi tự giẻ', 'views': 1800000, 'gmv': 510000000, 'eng': 9.8},
      {'name': 'Lan Tips', 'handle': '@lantips', 'followers': 420000, 'video': 'Dùng nước lau sàn đúng cách', 'views': 950000, 'gmv': 280000000, 'eng': 8.5},
      {'name': 'Gia Đình Nhỏ', 'handle': '@giadinhnho', 'followers': 960000, 'video': 'Haul đồ tiêu dùng Shopee', 'views': 2800000, 'gmv': 790000000, 'eng': 11.2},
      {'name': 'Review Tận Tâm', 'handle': '@reviewtt', 'followers': 580000, 'video': 'Khăn giấy rút nào dai?', 'views': 1500000, 'gmv': 420000000, 'eng': 10.4},
      {'name': 'Decor & Lifestyle', 'handle': '@decorlife', 'followers': 490000, 'video': 'Sắp xếp bàn làm việc', 'views': 1200000, 'gmv': 350000000, 'eng': 13.1},
      {'name': 'Mẹ Cam Review', 'handle': '@mecam', 'followers': 1250000, 'video': 'Đồ chơi giáo dục cho bé', 'views': 3800000, 'gmv': 1100000000, 'eng': 15.6},
      {'name': 'KOL Gia Dụng', 'handle': '@kolgd', 'followers': 320000, 'video': 'Bàn chải điện cho người mới', 'views': 750000, 'gmv': 220000000, 'eng': 7.6},
      {'name': 'Phong Cách Sống', 'handle': '@lifestylevn', 'followers': 680000, 'video': 'Xịt thơm quần áo review', 'views': 1700000, 'gmv': 490000000, 'eng': 9.5},
      {'name': 'Vloger Tiêu Dùng', 'handle': '@vlogertd', 'followers': 840000, 'video': 'Dọn dẹp bếp siêu nhanh', 'views': 2300000, 'gmv': 680000000, 'eng': 11.9},
      {'name': 'Tú Organizer', 'handle': '@tuorg', 'followers': 280000, 'video': 'Cách gấp quần áo gọn', 'views': 650000, 'gmv': 180000000, 'eng': 6.8},
      {'name': 'Review Mọi Thứ', 'handle': '@reviewmt', 'followers': 1050000, 'video': 'Đèn bắt muỗi có hiệu quả?', 'views': 3100000, 'gmv': 850000000, 'eng': 12.1},
      {'name': 'Bé Bắp Review', 'handle': '@bebap', 'followers': 450000, 'video': 'Hộp đựng thực phẩm nắp khóa', 'views': 1100000, 'gmv': 320000000, 'eng': 8.9},
      {'name': 'Nhà Của An', 'handle': '@nhacuaan', 'followers': 770000, 'video': 'Trang trí góc ban công', 'views': 1900000, 'gmv': 520000000, 'eng': 10.6},
      {'name': 'Gia Đình Vui Vẻ', 'handle': '@giadinhvv', 'followers': 1350000, 'video': 'Làm mới phòng khách với 1tr', 'views': 4200000, 'gmv': 1250000000, 'eng': 14.3},
      {'name': 'Review Smart', 'handle': '@reviewsmart', 'followers': 550000, 'video': 'Máy lọc không khí review', 'views': 1400000, 'gmv': 430000000, 'eng': 9.2},
      {'name': 'Mẹ Gấu Cook', 'handle': '@megau', 'followers': 620000, 'video': 'Dụng cụ cắt tỉa đa năng', 'views': 1600000, 'gmv': 460000000, 'eng': 11.4},
      {'name': 'KOL Hạnh', 'handle': '@kolhanh', 'followers': 410000, 'video': 'Dầu gội thảo dược tốt nhất', 'views': 1000000, 'gmv': 290000000, 'eng': 8.3},
      {'name': 'Tiện Ích Nhà Ở', 'handle': '@tienich', 'followers': 920000, 'video': 'Kệ gia vị xoay review', 'views': 2500000, 'gmv': 750000000, 'eng': 12.7},
      {'name': 'Vloger Lan', 'handle': '@vlogerlan', 'followers': 390000, 'video': 'Bộ 5 khăn tắm cotton', 'views': 850000, 'gmv': 250000000, 'eng': 7.5},
      {'name': 'Review Đồ Hay', 'handle': '@reviewdh', 'followers': 880000, 'video': 'Móc treo đa năng 9 lỗ', 'views': 2400000, 'gmv': 660000000, 'eng': 10.2},
      {'name': 'Tech Home', 'handle': '@techhome', 'followers': 510000, 'video': 'Khóa cửa thông minh vân tay', 'views': 1300000, 'gmv': 410000000, 'eng': 9.1},
      {'name': 'Lifestyle VN', 'handle': '@lifestylevn2', 'followers': 690000, 'video': 'Xịt khử mùi giày review', 'views': 1800000, 'gmv': 480000000, 'eng': 11.7},
      {'name': 'Home Tips', 'handle': '@hometips', 'followers': 430000, 'video': 'Cách vệ sinh máy giặt', 'views': 1100000, 'gmv': 310000000, 'eng': 7.7},
      {'name': 'KOL Linh', 'handle': '@kollinh', 'followers': 730000, 'video': 'Dụng cụ massage cổ review', 'views': 2000000, 'gmv': 590000000, 'eng': 12.2},
    ],
    'Điện tử': [
      {'name': 'Tech Bình Dân', 'handle': '@techbinhdan', 'followers': 1800000, 'video': 'Tai nghe chống ồn giá rẻ', 'views': 4600000, 'gmv': 1300000000, 'eng': 8.8},
      {'name': 'Vọc Đồ Công Nghệ', 'handle': '@vocdo', 'followers': 1020000, 'video': 'Sạc dự phòng nào bền?', 'views': 2700000, 'gmv': 780000000, 'eng': 7.5},
      {'name': 'Gadget Review VN', 'handle': '@gadgetvn', 'followers': 640000, 'video': 'Phụ kiện bàn làm việc', 'views': 1600000, 'gmv': 450000000, 'eng': 9.1},
      {'name': 'Duy Thẩm Tech', 'handle': '@duythẩm', 'followers': 3500000, 'video': 'iPhone 17 Pro Max review', 'views': 12000000, 'gmv': 4500000000, 'eng': 15.2},
      {'name': 'Vinh Vật Vờ', 'handle': '@vinhvatvo', 'followers': 2800000, 'video': 'Đánh giá laptop gaming', 'views': 8500000, 'gmv': 3200000000, 'eng': 12.8},
      {'name': 'Tech Reviewer', 'handle': '@techrev', 'followers': 1500000, 'video': 'Loa bluetooth bass cực căng', 'views': 4100000, 'gmv': 1100000000, 'eng': 10.4},
      {'name': 'KOL Công Nghệ', 'handle': '@koltech', 'followers': 890000, 'video': 'Setup góc làm việc 20tr', 'views': 2300000, 'gmv': 680000000, 'eng': 11.7},
      {'name': 'Gamer VN', 'handle': '@gamervn', 'followers': 1250000, 'video': 'Review chuột không dây 200k', 'views': 3800000, 'gmv': 950000000, 'eng': 13.9},
      {'name': 'Review Phụ Kiện', 'handle': '@pkreview', 'followers': 540000, 'video': 'Cáp sạc 3 trong 1 siêu bền', 'views': 1500000, 'gmv': 420000000, 'eng': 9.2},
      {'name': 'Smart Watch Tips', 'handle': '@swtips', 'followers': 680000, 'video': 'Đồng hồ thông minh 500k', 'views': 1900000, 'gmv': 560000000, 'eng': 8.5},
      {'name': 'Tech Lady', 'handle': '@techlady', 'followers': 420000, 'video': 'Case điện thoại cute', 'views': 950000, 'gmv': 280000000, 'eng': 12.1},
      {'name': 'Vloger Tech', 'handle': '@vlogertech', 'followers': 730000, 'video': 'Micro thu âm không dây review', 'views': 2000000, 'gmv': 610000000, 'eng': 14.3},
      {'name': 'Reviewer Dạo', 'handle': '@revdao', 'followers': 1100000, 'video': 'Tai nghe gaming giá sinh viên', 'views': 3100000, 'gmv': 890000000, 'eng': 11.6},
      {'name': 'Gadget World', 'handle': '@gadgetworld', 'followers': 580000, 'video': 'Đèn LED RGB dán bàn', 'views': 1600000, 'gmv': 450000000, 'eng': 10.8},
      {'name': 'Tech For Everyone', 'handle': '@tech4all', 'followers': 920000, 'video': 'Cách chọn củ sạc nhanh', 'views': 2500000, 'gmv': 740000000, 'eng': 9.7},
      {'name': 'Reviewer Nam', 'handle': '@revnam', 'followers': 390000, 'video': 'Bàn phím cơ Blue Switch', 'views': 850000, 'gmv': 250000000, 'eng': 8.9},
      {'name': 'KOL Minh Tech', 'handle': '@minhtech', 'followers': 660000, 'video': 'Quạt mini cầm tay review', 'views': 1800000, 'gmv': 520000000, 'eng': 12.5},
      {'name': 'Tech Insight', 'handle': '@techinsight', 'followers': 480000, 'video': 'Hub USB-C đa năng', 'views': 1200000, 'gmv': 350000000, 'eng': 7.8},
      {'name': 'Gadget Lover', 'handle': '@gadgetlove', 'followers': 840000, 'video': 'Gậy chụp ảnh tripod review', 'views': 2100000, 'gmv': 620000000, 'eng': 11.2},
      {'name': 'Reviewer Trang', 'handle': '@revtrang', 'followers': 320000, 'video': 'Máy tạo ẩm mini cute', 'views': 750000, 'gmv': 190000000, 'eng': 9.5},
      {'name': 'Tech Hunter', 'handle': '@techhunter', 'followers': 510000, 'video': 'Bút cảm ứng cho máy tính bảng', 'views': 1300000, 'gmv': 380000000, 'eng': 10.9},
      {'name': 'KOL Đức Tech', 'handle': '@ductech', 'followers': 770000, 'video': 'Máy chơi game retro 400 trò', 'views': 1900000, 'gmv': 560000000, 'eng': 8.6},
      {'name': 'Tech Master', 'handle': '@techmaster', 'followers': 1350000, 'video': 'Top 5 laptop văn phòng', 'views': 4200000, 'gmv': 1250000000, 'eng': 13.4},
      {'name': 'Reviewer An', 'handle': '@revan', 'followers': 460000, 'video': 'Đèn bắt muỗi review', 'views': 1100000, 'gmv': 310000000, 'eng': 12.2},
      {'name': 'Tech Vibe', 'handle': '@techvibe', 'followers': 690000, 'video': 'Lót chuột cỡ lớn review', 'views': 1700000, 'gmv': 490000000, 'eng': 9.4},
      {'name': 'Tech Zone', 'handle': '@techzone', 'followers': 880000, 'video': 'Pin sạc dự phòng 20000mAh', 'views': 2400000, 'gmv': 710000000, 'eng': 11.6},
      {'name': 'Reviewer Bình', 'handle': '@revbinh', 'followers': 380000, 'video': 'Tay cầm chơi game mobile', 'views': 900000, 'gmv': 270000000, 'eng': 7.9},
      {'name': 'KOL Lan Tech', 'handle': '@lantech', 'followers': 590000, 'video': 'Balo laptop chống trộm', 'views': 1500000, 'gmv': 430000000, 'eng': 8.3},
      {'name': 'Tech Trends', 'handle': '@techtrends', 'followers': 950000, 'video': 'Đồng hồ thông minh theo dõi ngủ', 'views': 2700000, 'gmv': 820000000, 'eng': 12.7},
      {'name': 'Reviewer Hoàng', 'handle': '@revhoang', 'followers': 430000, 'video': 'Máy massage cổ 4 đầu', 'views': 1000000, 'gmv': 290000000, 'eng': 9.1},
    ],
    'Du lịch': [
      {'name': 'Đi Là Ghiền', 'handle': '@dilaghien', 'followers': 1150000, 'video': 'Pack vali 3 ngày gọn nhẹ', 'views': 2900000, 'gmv': 720000000, 'eng': 12.1},
      {'name': 'Balo Và Núi', 'handle': '@balonui', 'followers': 700000, 'video': 'Balo chống nước cho phượt', 'views': 1800000, 'gmv': 470000000, 'eng': 10.4},
      {'name': 'Travel Cùng An', 'handle': '@travelan', 'followers': 480000, 'video': 'Đồ du lịch must-have', 'views': 1200000, 'gmv': 300000000, 'eng': 11.7},
      {'name': 'Kẻ Du Hành', 'handle': '@keduhanh', 'followers': 1500000, 'video': 'Review vali khung nhôm', 'views': 4100000, 'gmv': 950000000, 'eng': 13.6},
      {'name': 'Phượt Thủ VN', 'handle': '@phuothu', 'followers': 920000, 'video': 'Lều cắm trại tự bung 4 người', 'views': 2500000, 'gmv': 680000000, 'eng': 12.9},
      {'name': 'Review Du Lịch', 'handle': '@reviewdl', 'followers': 640000, 'video': 'Gối chữ U memory foam', 'views': 1700000, 'gmv': 450000000, 'eng': 9.8},
      {'name': 'Travel Blogger', 'handle': '@travelblog', 'followers': 1250000, 'video': 'Bộ chiết mỹ phẩm du lịch', 'views': 3500000, 'gmv': 820000000, 'eng': 14.2},
      {'name': 'Trang Vi Vu', 'handle': '@trangvivu', 'followers': 560000, 'video': 'Túi đựng đồ cá nhân chống sốc', 'views': 1400000, 'gmv': 380000000, 'eng': 11.5},
      {'name': 'Dũng Khám Phá', 'handle': '@dungkp', 'followers': 730000, 'video': 'Sạc dự phòng năng lượng mặt trời', 'views': 1900000, 'gmv': 510000000, 'eng': 8.7},
      {'name': 'Travel Tips', 'handle': '@traveltips', 'followers': 890000, 'video': 'Ổ cắm điện đa năng quốc tế', 'views': 2300000, 'gmv': 640000000, 'eng': 10.5},
      {'name': 'KOL An Du Lịch', 'handle': '@kolandl', 'followers': 410000, 'video': 'Đèn pin siêu sáng đi rừng', 'views': 950000, 'gmv': 270000000, 'eng': 9.4},
      {'name': 'Review Đồ Phượt', 'handle': '@phuotreview', 'followers': 510000, 'video': 'Giày trekking chống trượt', 'views': 1300000, 'gmv': 360000000, 'eng': 7.8},
      {'name': 'Bình Travel', 'handle': '@binhtravel', 'followers': 770000, 'video': 'Túi ngủ siêu nhẹ review', 'views': 2000000, 'gmv': 540000000, 'eng': 12.3},
      {'name': 'Vloger Du Lịch', 'handle': '@vlogerdl', 'followers': 1050000, 'video': 'Kinh nghiệm đi camping', 'views': 3200000, 'gmv': 890000000, 'eng': 11.9},
      {'name': 'Travel Holic', 'handle': '@travelholic', 'followers': 320000, 'video': 'Võng có màn chống muỗi', 'views': 750000, 'gmv': 190000000, 'eng': 15.6},
      {'name': 'Hương Vi Vu', 'handle': '@huongvivu', 'followers': 490000, 'video': 'Túi chống nước điện thoại', 'views': 1200000, 'gmv': 330000000, 'eng': 10.7},
      {'name': 'KOL Minh Travel', 'handle': '@minhdl', 'followers': 680000, 'video': 'Khăn nén du lịch dạng viên', 'views': 1800000, 'gmv': 470000000, 'eng': 9.2},
      {'name': 'Travel Advice', 'handle': '@traveladv', 'followers': 380000, 'video': 'Cân hành lý điện tử mini', 'views': 850000, 'gmv': 220000000, 'eng': 7.6},
      {'name': 'Ly Camping', 'handle': '@lycamp', 'followers': 590000, 'video': 'Tấm lót cách nhiệt review', 'views': 1500000, 'gmv': 410000000, 'eng': 11.4},
      {'name': 'Reviewer Nam', 'handle': '@revnamdl', 'followers': 840000, 'video': 'Áo mưa bộ cao cấp review', 'views': 2100000, 'gmv': 580000000, 'eng': 12.8},
      {'name': 'Travel Guru', 'handle': '@travelguru', 'followers': 1350000, 'video': 'Mẹo săn vé máy bay giá rẻ', 'views': 4500000, 'gmv': 1300000000, 'eng': 14.1},
      {'name': 'An Review Đồ', 'handle': '@anreview', 'followers': 460000, 'video': 'Xịt chống côn trùng review', 'views': 1100000, 'gmv': 310000000, 'eng': 9.4},
      {'name': 'Travel Passion', 'handle': '@travelp', 'followers': 510000, 'video': 'Gậy leo núi review', 'views': 1300000, 'gmv': 350000000, 'eng': 8.9},
      {'name': 'KOL Ngọc DL', 'handle': '@kolngocdl', 'followers': 730000, 'video': 'Bình nước silicon gấp gọn', 'views': 2000000, 'gmv': 590000000, 'eng': 10.5},
      {'name': 'Travel Zone', 'handle': '@travelzone', 'followers': 950000, 'video': 'Dây đai vali khóa mã số', 'views': 2800000, 'gmv': 790000000, 'eng': 12.6},
      {'name': 'Reviewer Đức', 'handle': '@revducdl', 'followers': 390000, 'video': 'Bếp ga mini gấp gọn review', 'views': 850000, 'gmv': 240000000, 'eng': 7.7},
      {'name': 'Camping Lover', 'handle': '@camplove', 'followers': 690000, 'video': 'Đệm hơi tự bơm review', 'views': 1800000, 'gmv': 490000000, 'eng': 11.2},
      {'name': 'Travel Geek', 'handle': '@travelgeek', 'followers': 880000, 'video': 'Adapter đổi nguồn quốc tế', 'views': 2400000, 'gmv': 690000000, 'eng': 9.5},
      {'name': 'Reviewer Lan', 'handle': '@revlandl', 'followers': 430000, 'video': 'Ô gấp ngược thông minh review', 'views': 1000000, 'gmv': 290000000, 'eng': 8.1},
      {'name': 'Travel Smart', 'handle': '@travelsmart', 'followers': 550000, 'video': 'Ví đựng hộ chiếu chống trộm', 'views': 1400000, 'gmv': 400000000, 'eng': 13.2},
    ],
  };
}

/// TikTok Shop category taxonomy entry for FastMoss queries.
class FastmossCategoryDef {
  /// Primary TikTok Shop first-level category id.
  final String primaryId;

  /// Related sub-category ids for broader coverage.
  final List<String> subIds;

  /// TikTok category display name (English).
  final String tiktokName;

  const FastmossCategoryDef({
    required this.primaryId,
    this.subIds = const [],
    required this.tiktokName,
  });
}

