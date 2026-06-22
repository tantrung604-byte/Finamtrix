import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class TikTokApiService {
  static final TikTokApiService instance = TikTokApiService._init();
  TikTokApiService._init();

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
