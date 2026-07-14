import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:finmatrix_flutter/services/gold_price_service.dart';

void main() {
  final service = GoldPriceService.instance;

  // Real response shape from https://www.vang.today/api/prices?type=SJL1L10&days=N
  const historyJson = '''
  {
    "success": true,
    "days": 3,
    "type": "SJL1L10",
    "history": [
      { "date": "2026-06-28",
        "prices": { "SJL1L10": { "name": "SJC 9999", "buy": 145500000, "sell": 148500000, "day_change_buy": 0, "day_change_sell": 0, "updates": 1 } } },
      { "date": "2026-06-27",
        "prices": { "SJL1L10": { "name": "SJC 9999", "buy": 145500000, "sell": 148500000, "day_change_buy": 1500000, "day_change_sell": 1500000, "updates": 2 } } },
      { "date": "2026-06-26",
        "prices": { "SJL1L10": { "name": "SJC 9999", "buy": 144000000, "sell": 147000000, "day_change_buy": 800000, "day_change_sell": 800000, "updates": 5 } } }
    ]
  }
  ''';

  const latestJson = '''
  {
    "success": true, "timestamp": 1782606606, "time": "07:30", "date": "2026-06-28",
    "type": "SJL1L10", "name": "SJC 9999", "buy": 145500000, "sell": 148500000,
    "change_buy": 0, "change_sell": 0
  }
  ''';

  test('parses history response into ordered points', () {
    final points = service.parseHistory(
      jsonDecode(historyJson) as Map<String, dynamic>,
      'SJL1L10',
    );

    expect(points.length, 3);
    expect(points.first.date, '2026-06-28');
    expect(points.first.buy, 145500000);
    expect(points.first.sell, 148500000);
    expect(points.first.name, 'SJC 9999');
    expect(points[2].sell, 147000000);
    expect(points[1].dayChangeSell, 1500000);
  });

  test('parses single latest response', () {
    final points = service.parseHistory(
      jsonDecode(latestJson) as Map<String, dynamic>,
      'SJL1L10',
    );

    expect(points.length, 1);
    expect(points.first.date, '2026-06-28');
    expect(points.first.sell, 148500000);
  });

  test('returns empty when success is false', () {
    final points = service.parseHistory({'success': false}, 'SJL1L10');
    expect(points, isEmpty);
  });
}

