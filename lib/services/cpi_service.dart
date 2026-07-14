import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/cpi_point.dart';
import 'database_helper.dart';

/// Service for fetching Consumer Price Index (CPI) from WIFEED.
class CpiService {
  static final CpiService instance = CpiService._init();
  CpiService._init();

  static const String prefsApiKey = 'wifeed_apikey';
  static const String _baseUrl = 'https://wifeed.vn/api/kinh-te-vi-mo/tieu-dung/gia-tieu-dung-cpi';

  Future<String?> _getApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(prefsApiKey)?.trim() ?? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MTQ0MywiZW1haWwiOiJ0YW50cnVuZzYwNEBnbWFpbC5jb20iLCJuYW1lIjoiVsWpIE5ndXnhu4VuIFThuqVuIFRydW5nIiwicGhvbmUiOiIrODQ5MTg3Mjg1OTUiLCJjb21wYW55IjoiT2x5bXBpYSBUcmF2ZWwiLCJyb2xlIjoidXNlciIsImlhdCI6MTc4MjY5MTYzOX0.5p9tCW3qvyrKVPOvK4tompI__Qnime11YIFcb9c1KWo';
    } catch (e) {
      return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MTQ0MywiZW1haWwiOiJ0YW50cnVuZzYwNEBnbWFpbC5jb20iLCJuYW1lIjoiVsWpIE5ndXnhu4VuIFThuqVuIFRydW5nIiwicGhvbmUiOiIrODQ5MTg3Mjg1OTUiLCJjb21wYW55IjoiT2x5bXBpYSBUcmF2ZWwiLCJyb2xlIjoidXNlciIsImlhdCI6MTc4MjY5MTYzOX0.5p9tCW3qvyrKVPOvK4tompI__Qnime11YIFcb9c1KWo';
    }
  }

  /// Fetches latest CPI history records from WIFEED.
  Future<List<CpiPoint>> fetchCpiHistory() async {
    final apiKey = await _getApiKey();
    final url = '$_baseUrl?page=1&limit=12&apikey=$apiKey';

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        print('CPI API error ${response.statusCode}: ${response.body}');
        return [];
      }
      return parseResponse(jsonDecode(response.body));
    } catch (e) {
      print('CPI fetch exception: $e');
      return [];
    }
  }

  /// Pure parser for CPI response.
  List<CpiPoint> parseResponse(dynamic json) {
    if (json is! Map || json['data'] is! List) return [];
    final List data = json['data'];
    return data.map((e) => CpiPoint.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Fetches and syncs CPI data to SQLite.
  Future<int> syncCpiHistory() async {
    final points = await fetchCpiHistory();
    if (points.isEmpty) return 0;

    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (final p in points) {
      batch.insert(
        'cpi_history',
        {
          'date': p.date,
          'cpi': p.cpi,
          'cpi_yoy': p.cpiYoY,
          'cpi_mom': p.cpiMoM,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    return points.length;
  }

  /// Returns the latest stored CPI record.
  Future<CpiPoint?> getLatestCpi() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'cpi_history',
      orderBy: 'date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    
    final r = rows.first;
    return CpiPoint(
      date: r['date'] as String,
      cpi: (r['cpi'] as num?)?.toDouble(),
      cpiYoY: (r['cpi_yoy'] as num?)?.toDouble(),
      cpiMoM: (r['cpi_mom'] as num?)?.toDouble(),
    );
  }
}
