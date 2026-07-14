import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:finmatrix_flutter/services/gold_price_service.dart';
import 'package:finmatrix_flutter/models/gold_price_point.dart';

void main() {
  final service = GoldPriceService.instance;

  test('parses history with buy and sell rates', () {
    const json = {
      "success": true,
      "history": [
        {
          "date": "2026-06-30",
          "prices": {
            "SJL1L10": {
              "name": "SJC 9999",
              "buy": 147000000,
              "sell": 148500000,
              "day_change_sell": 500000
            }
          }
        }
      ]
    };

    final points = service.parseHistory(json, 'SJL1L10');
    expect(points.length, 1);
    expect(points.first.buy, 147000000);
    expect(points.first.sell, 148500000);
  });

  test('GoldPricePoint toJson/fromJson handles buy/sell', () {
    final point = GoldPricePoint(
      date: '2026-06-30',
      buy: 147000000,
      sell: 148500000,
      name: 'SJC 9999',
      dayChangeSell: 500000,
    );

    final json = point.toJson();
    expect(json['buy'], 147000000);
    expect(json['sell'], 148500000);

    final fromJson = GoldPricePoint.fromJson(json);
    expect(fromJson.buy, 147000000);
    expect(fromJson.sell, 148500000);
  });
}
