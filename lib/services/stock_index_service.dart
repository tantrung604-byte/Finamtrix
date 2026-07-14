import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../models/index_price_point.dart';
import 'database_helper.dart';
import 'fomo_service.dart';

/// Connects to the VCI (Vietcap) market-data source that vnstock uses, fetches
/// stock index OHLC history (VNINDEX, HNXINDEX, ...), persists it into
/// `market_index_daily`, and exposes range queries (7 ngày / 30 ngày / 3 tháng
/// / 1 năm) for tracking.
///
/// Endpoint: POST https://trading.vietcap.com.vn/api/chart/OHLCChart/gap
/// Body: { "timeFrame": "ONE_DAY", "symbols": ["VNINDEX"], "from": <unix>, "to": <unix> }
/// Response: [ { "symbol": "VNINDEX",
///   "o": [...], "h": [...], "l": [...], "c": [...], "v": [...],
///   "t": ["<unix>", ...] } ]
class StockIndexService {
  static final StockIndexService instance = StockIndexService._init();
  StockIndexService._init();

  static const String _ohlcUrl =
      'https://trading.vietcap.com.vn/api/chart/OHLCChart/gap';

  /// Default index: VN-Index.
  static const String defaultSymbol = 'VNINDEX';

  static const String _source = 'VCI';

  /// VCI rejects requests without browser-like headers.
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
        'Referer': 'https://trading.vietcap.com.vn/',
        'Origin': 'https://trading.vietcap.com.vn',
      };

  /// Fetches up to [days] of daily OHLC history for [symbol] from VCI.
  /// Returns points oldest → newest.
  Future<List<IndexPricePoint>> fetchIndexHistory({
    String symbol = defaultSymbol,
    int days = 365,
  }) async {
    final now = DateTime.now();
    final to = now.millisecondsSinceEpoch ~/ 1000;
    // Pad the window so non-trading days don't shrink the result.
    final from = now
            .subtract(Duration(days: (days * 1.6).ceil() + 5))
            .millisecondsSinceEpoch ~/
        1000;

    final response = await http
        .post(
          Uri.parse(_ohlcUrl),
          headers: _headers,
          body: jsonEncode({
            'timeFrame': 'ONE_DAY',
            'symbols': [symbol],
            'from': from,
            'to': to,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('VCI API error ${response.statusCode}: ${response.body}');
    }

    final points = parseOhlc(jsonDecode(response.body), symbol);
    // Keep only the most recent [days] calendar days.
    final cutoff = now.subtract(Duration(days: days - 1));
    return points
        .where((p) => !DateTime.parse(p.date).isBefore(
              DateTime(cutoff.year, cutoff.month, cutoff.day),
            ))
        .toList();
  }

  /// Pure parser (no network) — testable. Accepts the decoded VCI response.
  List<IndexPricePoint> parseOhlc(dynamic decoded, String symbol) {
    if (decoded is! List || decoded.isEmpty) return [];

    final series = decoded.firstWhere(
      (e) => e is Map && e['symbol'] == symbol,
      orElse: () => decoded.first,
    );
    if (series is! Map) return [];

    final t = (series['t'] as List?) ?? const [];
    final o = (series['o'] as List?) ?? const [];
    final h = (series['h'] as List?) ?? const [];
    final l = (series['l'] as List?) ?? const [];
    final c = (series['c'] as List?) ?? const [];
    final v = (series['v'] as List?) ?? const [];

    final out = <IndexPricePoint>[];
    for (int i = 0; i < t.length; i++) {
      final epoch = int.tryParse('${t[i]}');
      if (epoch == null) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true)
          .toIso8601String()
          .split('T')[0];
      out.add(IndexPricePoint(
        date: date,
        open: _num(o, i),
        high: _num(h, i),
        low: _num(l, i),
        close: _num(c, i),
        volume: _num(v, i),
      ));
    }

    out.sort((a, b) => a.date.compareTo(b.date)); // oldest → newest
    return out;
  }

  double _num(List list, int i) =>
      (i < list.length ? (list[i] as num?)?.toDouble() : null) ?? 0;

  /// Fetches [days] of history and upserts it into `market_index_daily`.
  /// A single 365-day sync covers the 7/30/90-day windows too.
  /// Returns the number of rows written.
  Future<int> syncIndexHistory({
    String symbol = defaultSymbol,
    int days = 365,
  }) async {
    final points = await fetchIndexHistory(symbol: symbol, days: days);
    final db = await DatabaseHelper.instance.database;

    final batch = db.batch();
    for (final p in points) {
      batch.insert(
        'market_index_daily',
        {
          'symbol': symbol,
          'date': p.date,
          'open': p.open,
          'high': p.high,
          'low': p.low,
          'close': p.close,
          'volume': p.volume,
          'source': _source,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    // Refresh the stock FOMO score from the freshly stored index history.
    if (symbol == defaultSymbol) {
      try {
        await FomoService.instance
            .calculateAndSaveFomoScore('stock', indexSymbol: symbol);
      } catch (_) {
        // FOMO is best-effort; price history is the primary goal.
      }
    }

    return points.length;
  }

  /// Reads stored index history for a tracking window (oldest → newest).
  Future<List<IndexPricePoint>> getStoredHistory(
    IndexRange range, {
    String symbol = defaultSymbol,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: range.days - 1))
        .toIso8601String()
        .split('T')[0];

    final rows = await db.query(
      'market_index_daily',
      where: 'symbol = ? AND date >= ?',
      whereArgs: [symbol, cutoff],
      orderBy: 'date ASC',
    );

    return rows
        .map((r) => IndexPricePoint(
              date: r['date'] as String,
              open: (r['open'] as num).toDouble(),
              high: (r['high'] as num).toDouble(),
              low: (r['low'] as num).toDouble(),
              close: (r['close'] as num).toDouble(),
              volume: (r['volume'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
  }
}

