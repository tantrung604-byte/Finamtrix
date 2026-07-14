import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../models/tiktok_ad_metrics.dart';

class TikTokApiService {
  static final TikTokApiService instance = TikTokApiService._init();
  TikTokApiService._init();

  /// Source of the most recent [fetchTikTokAdMetrics] result:
  /// `'live'` = real TikTok API, `'demo'` = built-in sample data.
  String lastMetricsSource = 'demo';

  /// 1️⃣ TikTok API Client — fetches ad/video performance metrics for a shop.
  ///
  /// When a non-empty [accessToken] is supplied, a REAL request is made to the
  /// TikTok reporting endpoint and mapped into [TikTokAdMetrics]
  /// (`lastMetricsSource = 'live'`). Without a token — or if the call fails —
  /// deterministic demo data is returned (`lastMetricsSource = 'demo'`) so the
  /// pipeline stays usable in demos/offline.
  Future<TikTokAdMetrics> fetchTikTokAdMetrics({
    required String shopId,
    String? accessToken,
  }) async {
    // --- Real API call (used automatically once a token is available) ---
    if (accessToken != null && accessToken.trim().isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(
          '$_baseUrl/ads/reports?access_token=$accessToken&shop_id=$shopId',
        ));
        if (response.statusCode == 200) {
          final metrics =
              TikTokAdMetrics.fromJson(_mapReport(jsonDecode(response.body), shopId));
          if (metrics.videos.isNotEmpty) {
            lastMetricsSource = 'live';
            return metrics;
          }
        }
        print('TikTok metrics: live call returned ${response.statusCode}, using demo.');
      } catch (e) {
        print('TikTok metrics: live call failed ($e), using demo.');
      }
    }

    // --- Demo data (deterministic) ---
    lastMetricsSource = 'demo';
    final now = DateTime.now();
    final periodEnd = now.toIso8601String().split('T')[0];
    final periodStart =
        now.subtract(const Duration(days: 7)).toIso8601String().split('T')[0];

    return TikTokAdMetrics.fromJson({
      'shop_id': shopId,
      'period_start': periodStart,
      'period_end': periodEnd,
      'cogs_ratio': 0.55,
      'videos': [
        {
          'video_id': 'v_001',
          'title': 'Review sản phẩm thật - không dàn dựng',
          'impressions': 120000,
          'likes': 5400,
          'comments': 820,
          'shares': 1300,
          'clicks': 4200,
          'conversions': 310,
          'cost': 9000000,
          'revenue': 42000000,
        },
        {
          'video_id': 'v_002',
          'title': 'Unbox sản phẩm hot trend',
          'impressions': 86000,
          'likes': 2100,
          'comments': 240,
          'shares': 410,
          'clicks': 1800,
          'conversions': 95,
          'cost': 6500000,
          'revenue': 14000000,
        },
        {
          'video_id': 'v_003',
          'title': 'So sánh giá - mua sắm thông minh',
          'impressions': 54000,
          'likes': 980,
          'comments': 110,
          'shares': 130,
          'clicks': 720,
          'conversions': 38,
          'cost': 4800000,
          'revenue': 6200000,
        },
      ],
    });
  }

  /// Maps a raw TikTok reporting payload into the flat shape expected by
  /// [TikTokAdMetrics.fromJson]. Accepts either an already-flat body or a
  /// `{ data: { videos: [...] } }` envelope; unknown shapes yield no videos so
  /// the caller falls back to demo data.
  Map<String, dynamic> _mapReport(dynamic body, String shopId) {
    final Map<String, dynamic> root =
        body is Map<String, dynamic> ? body : <String, dynamic>{};
    final Map<String, dynamic> data =
        (root['data'] as Map<String, dynamic>?) ?? root;

    final rawVideos = (data['videos'] as List?) ?? const [];
    final videos = rawVideos.whereType<Map>().map((v) {
      final m = v.cast<String, dynamic>();
      return {
        'video_id': (m['video_id'] ?? m['item_id'] ?? '').toString(),
        'title': (m['title'] ?? m['video_name'] ?? '').toString(),
        'impressions': m['impressions'] ?? m['show_cnt'] ?? 0,
        'likes': m['likes'] ?? m['like_cnt'] ?? 0,
        'comments': m['comments'] ?? m['comment_cnt'] ?? 0,
        'shares': m['shares'] ?? m['share_cnt'] ?? 0,
        'clicks': m['clicks'] ?? m['click_cnt'] ?? 0,
        'conversions': m['conversions'] ?? m['sku_order_cnt'] ?? 0,
        'cost': m['cost'] ?? m['spend'] ?? 0,
        'revenue': m['revenue'] ?? m['gross_revenue'] ?? 0,
      };
    }).toList();

    return {
      'shop_id': shopId,
      'period_start': (data['period_start'] ?? data['start_date'] ?? '').toString(),
      'period_end': (data['period_end'] ?? data['end_date'] ?? '').toString(),
      'cogs_ratio': data['cogs_ratio'] ?? 0.55,
      'videos': videos,
    };
  }

  // Note: These should come from a secure config or backend in a real app
  static const String _clientId = 'YOUR_TIKTOK_CLIENT_ID';
  static const String _clientSecret = 'YOUR_TIKTOK_CLIENT_SECRET';
  static const String _baseUrl = 'https://open-api.tiktokglobalshop.com/api/v2';

  /// Starts the OAuth flow (this usually happens via a webview in Flutter)
  String getAuthorizationUrl(String state) {
    return 'https://auth.tiktok-seller.com/authorize?app_key=$_clientId&state=$state';
  }

  /// Exchanges auth code for tokens
  Future<void> handleAuthCallback(String code, String channelConfigId) async {
    final response = await http.get(
      Uri.parse('https://auth.tiktok-seller.com/token?app_key=$_clientId&app_secret=$_clientSecret&auth_code=$code&grant_type=authorized_code'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _saveConnection(data, channelConfigId);
    } else {
      throw Exception('Failed to authorize TikTok Shop');
    }
  }

  Future<void> _saveConnection(Map<String, dynamic> data, String channelConfigId) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final expiresAt = now.add(Duration(seconds: data['expires_in']));

    await db.insert(
      'tiktok_shop_connection',
      {
        'id': DateTime.now().millisecondsSinceEpoch.toString(), // Simplified ID
        'channel_config_id': channelConfigId,
        'tiktok_shop_id': data['seller_id'],
        'access_token': data['access_token'], // TODO: Encrypt this
        'refresh_token': data['refresh_token'], // TODO: Encrypt this
        'token_expires_at': expiresAt.toIso8601String(),
        'authorized_at': now.toIso8601String(),
        'sync_status': 'active',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Syncs orders for a specific connection
  Future<void> syncOrders(String connectionId) async {
    final db = await DatabaseHelper.instance.database;
    
    // 1. Get connection info
    final connResult = await db.query(
      'tiktok_shop_connection',
      where: 'id = ?',
      whereArgs: [connectionId],
    );
    if (connResult.isEmpty) return;
    final conn = connResult.first;

    // 2. Refresh token if expired
    String accessToken = conn['access_token'] as String;
    final expiresAt = DateTime.parse(conn['token_expires_at'] as String);
    if (DateTime.now().isAfter(expiresAt)) {
      accessToken = await _refreshToken(connectionId, conn['refresh_token'] as String);
    }

    // 3. Fetch orders from TikTok API
    // GET /api/v2/seller/orders/search
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
    final response = await http.get(
      Uri.parse('$_baseUrl/seller/orders/search?access_token=$accessToken&shop_id=${conn['tiktok_shop_id']}&update_time_from=$yesterday'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final orders = data['data']['order_list'] as List;
      
      // Filter for COMPLETED orders as per spec T3
      final completedOrders = orders.where((o) => o['order_status'] == 'COMPLETED').toList();

      // 4. Update channel_actual_performance
      await db.insert('channel_actual_performance', {
        'channel_config_id': conn['channel_config_id'],
        'record_date': DateTime.now().toIso8601String().split('T')[0],
        'actual_orders': completedOrders.length,
        'period_covers_days': 1,
      });

      // Update sync status
      await db.update(
        'tiktok_shop_connection',
        {'last_synced_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [connectionId],
      );
    }
  }

  Future<String> _refreshToken(String id, String refreshToken) async {
    // Call TikTok refresh endpoint...
    // Update DB with new tokens...
    return 'NEW_ACCESS_TOKEN'; // Mocked
  }
}
