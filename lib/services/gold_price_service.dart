import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../models/gold_price_point.dart';
import 'database_helper.dart';
import 'fomo_service.dart';
import 'supabase_service.dart';

/// Connects to the vang.today gold price API, persists daily history into the
/// existing `gold_price_daily` table, and exposes range queries (7 ngày,
/// 30 ngày, 3 tháng, 1 năm) for tracking.
///
/// API: GET https://www.vang.today/api/prices?type=<TYPE>&days=<N>
/// Response (history mode):
/// {
///   "success": true, "days": 7, "type": "SJL1L10",
///   "history": [
///     { "date": "2026-06-28",
///       "prices": { "SJL1L10": { "name": "SJC 9999",
///         "buy": 145500000, "sell": 148500000,
///         "day_change_buy": 0, "day_change_sell": 0, "updates": 1 } } },
///     ...
///   ]
/// }
class GoldPriceService {
  static final GoldPriceService instance = GoldPriceService._init();
  GoldPriceService._init();

  static const String _baseUrl = 'https://www.vang.today/api/prices';

  /// Default gold product: SJC 9999 (1 lượng / 10 chỉ).
  static const String defaultType = 'SJL1L10';

  /// World gold product: XAU/USD.
  static const String worldType = 'XAUUSD';

  /// Source label stored in `gold_price_daily.source`.
  static const String _source = 'vang.today';

  /// Fetches up to [days] of history from the API for [type].
  /// Returns parsed points (newest first, as returned by the API).
  Future<List<GoldPricePoint>> fetchHistory({
    String type = defaultType,
    int days = 365,
  }) async {
    final uri = Uri.parse('$_baseUrl?type=$type&days=$days');
    final response = await http.get(uri).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('vang.today API error ${response.statusCode}: ${response.body}');
    }

    return parseHistory(jsonDecode(response.body) as Map<String, dynamic>, type);
  }

  /// Pure parser (no network) — testable in isolation.
  List<GoldPricePoint> parseHistory(Map<String, dynamic> json, String type) {
    if (json['success'] != true) return [];

    // History mode (days param) → list under "history".
    if (json['history'] is List) {
      final out = <GoldPricePoint>[];
      for (final entry in (json['history'] as List)) {
        final date = entry['date'] as String?;
        final prices = entry['prices'];
        if (date == null || prices is! Map) continue;
        final p = prices[type] ?? prices.values.first;
        if (p is! Map) continue;
        out.add(GoldPricePoint(
          date: date,
          buy: (p['buy'] as num?)?.toDouble() ?? 0,
          sell: (p['sell'] as num?)?.toDouble() ?? 0,
          name: p['name'] as String? ?? type,
          dayChangeSell: (p['day_change_sell'] as num?)?.toDouble() ?? 0,
        ));
      }
      return out;
    }

    // Single (latest) mode → flat object.
    if (json['date'] != null && json['sell'] != null) {
      return [
        GoldPricePoint(
          date: json['date'] as String,
          buy: (json['buy'] as num?)?.toDouble() ?? 0,
          sell: (json['sell'] as num?)?.toDouble() ?? 0,
          name: json['name'] as String? ?? type,
          dayChangeSell: (json['change_sell'] as num?)?.toDouble() ?? 0,
        )
      ];
    }

    return [];
  }

  /// Fetches [days] of history and upserts it into `gold_price_daily`, then
  /// recalculates the gold FOMO score. A single 365-day sync covers the 7/30/90
  /// day windows too. Returns the number of rows written.
  ///
  /// On network failure it throws; callers can ignore to keep using cached data.
  Future<int> syncGoldHistory({
    String type = defaultType,
    int days = 365,
    bool pushToSupabase = true,
  }) async {
    final points = await fetchHistory(type: type, days: days);
    final db = await DatabaseHelper.instance.database;
    final dbType = type == worldType ? 'world' : 'domestic';

    final batch = db.batch();
    for (final p in points) {
      batch.insert(
        'gold_price_daily',
        {
          'date': p.date,
          'type': dbType,
          'price_buy': p.buy,
          'price_sell': p.sell,
          'source': _source,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (pushToSupabase && dbType == 'domestic') {
        // Push only the latest point to Supabase to keep cache fresh
        if (p.date == points.first.date) {
          SupabaseService.instance.upsertGoldPrice(p);
        }
      }
    }
    await batch.commit(noResult: true);

    // Refresh the FOMO score from the freshly stored history.
    try {
      await FomoService.instance.calculateAndSaveFomoScore('gold');
    } catch (_) {
      // FOMO is best-effort; price history is the primary goal.
    }

    return points.length;
  }

  /// Syncs data from Supabase cache to local database.
  Future<void> syncFromSupabase() async {
    final points = await SupabaseService.instance.getLatestGoldPrices();
    if (points.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (final p in points) {
      batch.insert(
        'gold_price_daily',
        {
          'date': p.date,
          'type': 'domestic',
          'price_buy': p.buy,
          'price_sell': p.sell,
          'source': 'supabase_cache',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Reads stored gold history for a tracking window from the DB
  /// (oldest → newest), e.g. [GoldRange.week] for the last 7 days.
  Future<List<GoldPricePoint>> getStoredHistory(GoldRange range, {String dbType = 'domestic'}) async {
    final db = await DatabaseHelper.instance.database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: range.days - 1))
        .toIso8601String()
        .split('T')[0];

    final rows = await db.query(
      'gold_price_daily',
      where: 'date >= ? AND type = ?',
      whereArgs: [cutoff, dbType],
      orderBy: 'date ASC',
    );

    return rows
        .map((r) => GoldPricePoint(
              date: r['date'] as String,
              buy: (r['price_buy'] as num).toDouble(),
              sell: (r['price_sell'] as num).toDouble(),
              name: (r['source'] as String?) ?? _source,
              dayChangeSell: 0,
            ))
        .toList();
  }

  /// Convenience: stored history for all tracking windows in one call.
  Future<Map<GoldRange, List<GoldPricePoint>>> getAllRanges() async {
    final result = <GoldRange, List<GoldPricePoint>>{};
    for (final range in GoldRange.values) {
      result[range] = await getStoredHistory(range);
    }
    return result;
  }
}

