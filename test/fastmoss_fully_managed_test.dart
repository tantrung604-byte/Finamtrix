import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finmatrix_flutter/services/fastmoss_service.dart';

/// Uses the exact response examples from the official FastMoss Open API docs:
///   - /product/v1/rank/fullyManaged
///   - /shop/v1/rank/fullyManaged
void main() {
  final fm = FastmossService.instance;

  const productResponse = '''
  {
    "code": 0, "msg": "success",
    "data": {
      "total": 500,
      "list": [
        {
          "product_id": "1732235069991130057",
          "units_sold": 3543,
          "gmv": 29265.18,
          "units_sold_growth_rate": 59335,
          "off_shelves": 0,
          "launch_time": 1773016184,
          "title": "Women's Short Sleeve Casual Sporty Set",
          "cover": "https://example/cover.jpeg",
          "region": "US",
          "currency": "USD",
          "real_price": "\$21.24",
          "commission_rate": 800,
          "category": { "l1": { "id": 2, "name": "Womenswear & Underwear" } },
          "shop": { "seller_id": "8646927642708317129", "name": "Verve Fashion", "total_units_sold": 130881 }
        }
      ]
    }
  }
  ''';

  const shopResponse = '''
  {
    "code": 0,
    "data": {
      "list": [
        {
          "shop_info": {
            "seller_id": 8647778611395402618,
            "name": "Selected by the clouds",
            "region": "GB",
            "currency": "GBP"
          },
          "units_sold": 278,
          "gmv": 789.87,
          "usd_gmv": 979.44,
          "units_sold_inc_rate": "-13.93%",
          "gmv_inc_rate": "-11.26%",
          "currency": "GBP",
          "total_affiliate_count": 128,
          "sale_product_count": 5
        }
      ],
      "total": 500
    }
  }
  ''';

  test('parses fully-managed product ranking', () {
    final products =
        fm.parseFullyManagedProducts(jsonDecode(productResponse), region: 'US');
    expect(products, hasLength(1));
    final p = products.first;
    expect(p.productId, '1732235069991130057');
    expect(p.unitsSold, 3543);
    expect(p.gmv, closeTo(29265.18, 0.001));
    expect(p.commissionRateRaw, 800);
    expect(p.commissionFraction, closeTo(0.08, 1e-9)); // 800 → 8%
    expect(p.realPrice, closeTo(21.24, 0.001));
    expect(p.categoryName, 'Womenswear & Underwear');
    expect(p.shopName, 'Verve Fashion');
  });

  test('maps products into CMO metrics with real fields + documented proxies', () {
    final products =
        fm.parseFullyManagedProducts(jsonDecode(productResponse), region: 'US');
    final metrics = fm.buildCmoMetricsFromProducts(products, usdToVnd: 25000);

    expect(metrics.videos, hasLength(1));
    final v = metrics.videos.first;
    // revenue = gmv * usdToVnd
    expect(v.revenue, closeTo(29265.18 * 25000, 1));
    // cost = revenue * commission fraction (8%)
    expect(v.cost, closeTo(29265.18 * 25000 * 0.08, 1));
    // sales-as-performance proxy
    expect(v.conversions, 3543);
    expect(v.engagements, 3543); // likes proxy → best/worst by sales
    expect(metrics.totalRevenue, closeTo(29265.18 * 25000, 1));
  });

  test('parses fully-managed shop ranking', () {
    final shops = fm.parseFullyManagedShops(jsonDecode(shopResponse));
    expect(shops, hasLength(1));
    final s = shops.first;
    expect(s.name, 'Selected by the clouds');
    expect(s.region, 'GB');
    expect(s.unitsSold, 278);
    expect(s.gmv, closeTo(789.87, 0.001));
    expect(s.usdGmv, closeTo(979.44, 0.001));
    expect(s.unitsSoldIncRate, '-13.93%');
    expect(s.totalAffiliateCount, 128);
  });

  test('buildDateInfo picks day/week/month by window', () {
    final day = fm.buildDateInfo(1, DateTime(2026, 2, 1));
    expect(day['type'], 'day');
    expect(day['value'], '2026-02-01');

    final month = fm.buildDateInfo(30, DateTime(2026, 3, 15));
    expect(month['type'], 'month');
    expect(month['value'], '2026-03');

    final week = fm.buildDateInfo(7, DateTime(2026, 4, 30));
    expect(week['type'], 'week');
    expect(week['value'], matches(r'^\d{4}-\d{2}$'));
  });

  // --- Top Selling (VN-capable) shares the same schema as Fully Managed ---
  const topSellingVnResponse = '''
  {
    "code": 0, "msg": "success",
    "data": {
      "total": 500,
      "list": [
        {
          "product_id": "1729537665891078575",
          "title": "Ly thủy tinh có nắp và ống hút",
          "cover": "https://example/cover.jpeg",
          "real_price": "159000",
          "region": "VN",
          "commission_rate": 1500,
          "category": { "l1": { "id": 123, "name": "Nhà cửa & Đời sống" } },
          "units_sold": 4200,
          "gmv": 668000000,
          "total_units_sold": 15000,
          "total_gmv": 2100000000,
          "growth_rate": 42,
          "shop": { "seller_id": "123", "name": "Home VN", "total_units_sold": 15000 }
        }
      ]
    }
  }
  ''';

  test('VN Top Selling: parses and keeps GMV in VND (factor 1)', () {
    final products =
        fm.parseFullyManagedProducts(jsonDecode(topSellingVnResponse), region: 'VN');
    expect(products, hasLength(1));
    final p = products.first;
    expect(p.region, 'VN');
    expect(p.unitsSold, 4200);
    expect(p.gmv, 668000000);
    expect(p.commissionPct, closeTo(15.0, 1e-9)); // 1500 → 15%

    // VN GMV is already VND → factor must be 1 (no USD conversion).
    expect(FastmossService.regionGmvToVnd('VN'), 1.0);
    final metrics = fm.buildCmoMetricsFromProducts(products,
        region: 'VN', usdToVnd: FastmossService.regionGmvToVnd('VN'));
    expect(metrics.videos.first.revenue, 668000000); // unchanged
    expect(metrics.videos.first.cost, closeTo(668000000 * 0.15, 1));
  });

  test('topSellingRegions includes VN; fullyManaged does not', () {
    expect(FastmossService.topSellingRegions, contains('VN'));
    expect(FastmossService.fullyManagedRegions, isNot(contains('VN')));
  });

  test('openApiL1CategoryIds maps all 5 app categories to verified L1 ids', () {
    expect(FastmossService.openApiL1CategoryIds, {
      'Thời trang': 2,
      'Ăn uống': 24,
      'Tiêu dùng': 13,
      'Điện tử': 16,
      'Du lịch': 7,
    });
    // Same category keys the Micro screen taxonomy uses.
    expect(FastmossService.openApiL1CategoryIds.keys.toSet(),
        FastmossService.categoryTaxonomy.keys.toSet());
  });

  test('proxy is disabled by default (no FASTMOSS_PROXY_URL define)', () {
    // In tests no dart-define is set → direct openapi.fastmoss.com calls.
    expect(FastmossService.proxyUrl, isEmpty);
    expect(FastmossService.usesProxy, isFalse);
  });

  group('Open API signature (App ID + App Secret)', () {
    test('sign is deterministic md5(appId+nonce+timestamp+secret)', () {
      final sign = fm.signOpenApi(
        appId: 'finmatrix',
        secret: 'top-secret',
        timestamp: '1720000000000',
        nonce: 'abcd1234',
      );
      final expected =
          md5.convert(utf8.encode('finmatrixabcd12341720000000000top-secret'))
              .toString();
      expect(sign, expected);
      // 32-char lowercase hex.
      expect(sign, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('different nonce/timestamp yields a different signature', () {
      final a = fm.signOpenApi(
          appId: 'finmatrix', secret: 's', timestamp: '1', nonce: 'x');
      final b = fm.signOpenApi(
          appId: 'finmatrix', secret: 's', timestamp: '2', nonce: 'x');
      final c = fm.signOpenApi(
          appId: 'finmatrix', secret: 's', timestamp: '1', nonce: 'y');
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
    });

    test('a changed secret changes the signature', () {
      final a = fm.signOpenApi(
          appId: 'finmatrix', secret: 'one', timestamp: '1', nonce: 'x');
      final b = fm.signOpenApi(
          appId: 'finmatrix', secret: 'two', timestamp: '1', nonce: 'x');
      expect(a, isNot(equals(b)));
    });
  });
}

