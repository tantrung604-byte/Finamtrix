import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:finmatrix_flutter/services/exchange_rate_service.dart';

void main() {
  final service = ExchangeRateService.instance;

  // Real response shape from Vietcombank /api/exchangerates.
  const vcbJson = '''
  {
    "Count": 3,
    "Date": "2026-06-28T00:00:00",
    "UpdatedDate": "2026-06-27T23:00:00+07:00",
    "Data": [
      { "currencyName": "US DOLLAR", "currencyCode": "USD",
        "cash": "26084.00", "transfer": "26114.00", "sell": "26454.00" },
      { "currencyName": "EURO", "currencyCode": "EUR",
        "cash": "29204.46", "transfer": "29499.46", "sell": "30744.13" }
    ]
  }
  ''';

  test('parses USD row from Vietcombank response', () {
    final p = service.parseUsd(jsonDecode(vcbJson) as Map<String, dynamic>);

    expect(p, isNotNull);
    expect(p!.date, '2026-06-28');
    expect(p.cash, 26084.0);
    expect(p.transfer, 26114.0);
    expect(p.sell, 26454.0);
  });

  test('handles missing/dash cash values', () {
    const json = '''
    { "Date": "2026-06-28T00:00:00", "Data": [
      { "currencyCode": "USD", "cash": "-", "transfer": "26114.00", "sell": "26454.00" } ] }
    ''';
    final p = service.parseUsd(jsonDecode(json) as Map<String, dynamic>);
    expect(p, isNotNull);
    expect(p!.cash, isNull);
    expect(p.transfer, 26114.0);
  });

  test('returns null when USD not present', () {
    const json = '''
    { "Date": "2026-06-28T00:00:00", "Data": [
      { "currencyCode": "EUR", "transfer": "29499.46", "sell": "30744.13" } ] }
    ''';
    expect(service.parseUsd(jsonDecode(json) as Map<String, dynamic>), isNull);
  });
}

