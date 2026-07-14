import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../models/usd_rate_point.dart';
import 'database_helper.dart';

/// Connects to the Vietcombank exchange-rate API, persists daily USD/VND
/// snapshots into `usd_rate_daily`, and exposes the latest rate + history for
/// tracking.
///
/// API: GET https://www.vietcombank.com.vn/api/exchangerates?date=<now|YYYY-MM-DD>
/// Response:
/// {
///   "Count": 20, "Date": "2026-06-28T00:00:00",
///   "UpdatedDate": "2026-06-27T23:00:00+07:00",
///   "Data": [
///     { "currencyName": "US DOLLAR", "currencyCode": "USD",
///       "cash": "26084.00", "transfer": "26114.00", "sell": "26454.00" }, ...
///   ]
/// }
class ExchangeRateService {
  static final ExchangeRateService instance = ExchangeRateService._init();
  ExchangeRateService._init();

  static const String _baseUrl =
      'https://www.vietcombank.com.vn/api/exchangerates';

  static const String _source = 'vietcombank';

  static Map<String, String> get _headers => {
        'Accept': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      };

  /// Fetches the USD/VND rate for [date] ("now" or "YYYY-MM-DD").
  /// Returns null if USD is not present in the response.
  Future<UsdRatePoint?> fetchUsdRate({String date = 'now'}) async {
    final uri = Uri.parse('$_baseUrl?date=$date');
    final response =
        await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
          'Vietcombank API error ${response.statusCode}: ${response.body}');
    }

    return parseUsd(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Pure parser (no network) — extracts the USD row. Testable in isolation.
  UsdRatePoint? parseUsd(Map<String, dynamic> json) {
    final data = json['Data'];
    if (data is! List) return null;

    final usd = data.firstWhere(
      (e) => e is Map && e['currencyCode'] == 'USD',
      orElse: () => null,
    );
    if (usd is! Map) return null;

    // "Date" is like "2026-06-28T00:00:00".
    final rawDate = (json['Date'] as String?) ?? '';
    final date = rawDate.contains('T')
        ? rawDate.split('T')[0]
        : DateTime.now().toIso8601String().split('T')[0];

    return UsdRatePoint(
      date: date,
      cash: _toDouble(usd['cash']),
      transfer: _toDouble(usd['transfer']) ?? 0,
      sell: _toDouble(usd['sell']) ?? 0,
    );
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    final s = v.toString().replaceAll(',', '').trim();
    if (s.isEmpty || s == '-') return null;
    return double.tryParse(s);
  }

  /// Fetches today's USD rate and upserts it into `usd_rate_daily`.
  /// Returns the stored point (or null if unavailable). Daily snapshots
  /// accumulate into a history over time.
  Future<UsdRatePoint?> syncTodayRate() async {
    final point = await fetchUsdRate(date: 'now');
    if (point == null) return null;
    await _store(point);
    return point;
  }

  /// Seeds recent history (last [days] days) when the table is empty, so the
  /// rate has immediate context. Skips weekends/holidays gracefully. Capped to
  /// avoid hammering the API.
  Future<int> backfillRecentIfEmpty({int days = 14}) async {
    final db = await DatabaseHelper.instance.database;
    final existing = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM usd_rate_daily'));
    if ((existing ?? 0) > 0) return 0;

    int written = 0;
    final now = DateTime.now();
    for (int i = 0; i < days; i++) {
      final d = now.subtract(Duration(days: i));
      final iso = d.toIso8601String().split('T')[0];
      try {
        final point = await fetchUsdRate(date: iso);
        if (point != null) {
          await _store(point);
          written++;
        }
      } catch (_) {
        // Best-effort backfill; skip failures.
      }
    }
    return written;
  }

  Future<void> _store(UsdRatePoint p) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'usd_rate_daily',
      {
        'date': p.date,
        'cash': p.cash,
        'transfer': p.transfer,
        'sell': p.sell,
        'source': _source,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Latest stored USD rate (or null if none).
  Future<UsdRatePoint?> getLatestStored() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'usd_rate_daily',
      orderBy: 'date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return UsdRatePoint(
      date: r['date'] as String,
      cash: (r['cash'] as num?)?.toDouble(),
      transfer: (r['transfer'] as num).toDouble(),
      sell: (r['sell'] as num).toDouble(),
    );
  }
}

