import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:finmatrix_flutter/services/stock_index_service.dart';

void main() {
  final service = StockIndexService.instance;

  // Real response shape from VCI OHLCChart/gap (used by vnstock).
  // t values are unix seconds (as strings).
  const vciJson = '''
  [{
    "symbol": "VNINDEX",
    "o": [1857.24, 1867.44, 1845.32],
    "h": [1873.91, 1871.09, 1858.76],
    "l": [1854.94, 1840.40, 1822.32],
    "c": [1871.91, 1844.54, 1826.47],
    "v": [533612987, 506972140, 727018675],
    "t": ["1782432000", "1782345600", "1782259200"]
  }]
  ''';

  test('parses VCI OHLC into points sorted oldest → newest', () {
    final points = service.parseOhlc(jsonDecode(vciJson), 'VNINDEX');

    expect(points.length, 3);
    // Sorted ascending by date.
    expect(points.first.date.compareTo(points.last.date) < 0, isTrue);
    // Newest row (t=1782432000) has close 1871.91.
    expect(points.last.close, 1871.91);
    expect(points.last.high, 1873.91);
    expect(points.last.low, 1854.94);
    expect(points.last.open, 1857.24);
    expect(points.last.volume, 533612987);
  });

  test('returns empty for non-list / empty input', () {
    expect(service.parseOhlc(null, 'VNINDEX'), isEmpty);
    expect(service.parseOhlc(<dynamic>[], 'VNINDEX'), isEmpty);
    expect(service.parseOhlc({'symbol': 'VNINDEX'}, 'VNINDEX'), isEmpty);
  });

  test('maps unix timestamp to ISO date', () {
    final points = service.parseOhlc(jsonDecode(vciJson), 'VNINDEX');
    // 1782259200 (UTC midnight) → 2026-06-24.
    expect(points.first.date, '2026-06-24');
  });
}

