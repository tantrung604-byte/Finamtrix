/// Typed models for the **official FastMoss Open API** (openapi.fastmoss.com)
/// "Fully Managed" ranking endpoints:
///   - POST /product/v1/rank/fullyManaged
///   - POST /shop/v1/rank/fullyManaged
///
/// These return TikTok Shop *market ranking* data (units sold, GMV, commission)
/// — NOT per-video ad engagement. The CMO pipeline maps a product into the
/// existing [TikTokAdMetrics] "video" shape using real fields plus explicit,
/// documented proxies (sales = performance signal, affiliate commission =
/// marketing-cost proxy).

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) {
    final cleaned = v.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? 0;
  }
  return 0;
}

int _toInt(dynamic v) => _toDouble(v).round();

String _toStr(dynamic v) => v == null ? '' : v.toString();

/// One product row from `/product/v1/rank/fullyManaged`.
class FmFullyManagedProduct {
  final String productId;
  final String title;
  final int unitsSold;

  /// Revenue (GMV) in [currency] over the ranking window.
  final double gmv;

  /// Raw commission rate as returned by FastMoss (e.g. 800 == 8.00%).
  final int commissionRateRaw;

  /// Parsed unit price in [currency] (from e.g. "$21.24").
  final double realPrice;

  final String currency;
  final String region;

  /// Sales-volume growth rate as returned (may be raw/percent depending on
  /// endpoint version); exposed for context only.
  final double unitsSoldGrowthRate;

  final String? categoryName;
  final String? shopName;

  const FmFullyManagedProduct({
    required this.productId,
    required this.title,
    required this.unitsSold,
    required this.gmv,
    required this.commissionRateRaw,
    required this.realPrice,
    required this.currency,
    required this.region,
    this.unitsSoldGrowthRate = 0,
    this.categoryName,
    this.shopName,
  });

  /// Commission as a fraction (800 → 0.08).
  double get commissionFraction => commissionRateRaw / 10000.0;

  /// Commission as a percent (800 → 8.0).
  double get commissionPct => commissionRateRaw / 100.0;

  factory FmFullyManagedProduct.fromApi(
    Map<String, dynamic> json, {
    String fallbackRegion = '',
  }) {
    final category = json['category'];
    String? catName;
    if (category is Map) {
      final l1 = category['l1'];
      if (l1 is Map) catName = _toStr(l1['name']);
      catName ??= _toStr(category['name']);
    }

    final shop = json['shop'];
    String? shopName;
    if (shop is Map) shopName = _toStr(shop['name']);

    return FmFullyManagedProduct(
      productId: _toStr(json['product_id'] ?? json['id']),
      title: _toStr(json['title'] ?? json['name']),
      unitsSold: _toInt(json['units_sold'] ?? json['sales']),
      gmv: _toDouble(json['gmv'] ?? json['sale_amount']),
      commissionRateRaw: _toInt(json['commission_rate']),
      realPrice: _toDouble(json['real_price'] ?? json['price']),
      currency: _toStr(json['currency']).isEmpty ? 'USD' : _toStr(json['currency']),
      region: _toStr(json['region']).isEmpty ? fallbackRegion : _toStr(json['region']),
      unitsSoldGrowthRate: _toDouble(json['units_sold_growth_rate'] ??
          json['growth_rate'] ??
          json['units_sold_inc_rate']),
      categoryName: (catName == null || catName.isEmpty) ? null : catName,
      shopName: (shopName == null || shopName.isEmpty) ? null : shopName,
    );
  }

  /// Maps this product into the CMO's per-"video" JSON (see [TikTokAdMetrics]).
  ///
  /// Fully-managed sales data has no impressions/likes, so:
  ///   - revenue    = gmv (converted to VND)
  ///   - conversions= units_sold (real)
  ///   - cost       = revenue * affiliate commission fraction (real cost proxy)
  ///   - likes      = units_sold  → used only as the engagement RANKING signal
  ///                  so "best/worst video" == best/worst SELLER.
  Map<String, dynamic> toCmoVideoJson({double usdToVnd = 25400}) {
    final gmvVnd = gmv * usdToVnd;
    return {
      'video_id': productId.isEmpty ? title : productId,
      'title': title,
      'impressions': 0,
      'likes': unitsSold, // sales-as-engagement proxy (documented)
      'comments': 0,
      'shares': 0,
      'clicks': 0,
      'conversions': unitsSold,
      'cost': gmvVnd * commissionFraction,
      'revenue': gmvVnd,
    };
  }
}

/// One shop row from `/shop/v1/rank/fullyManaged`.
class FmFullyManagedShop {
  final String sellerId;
  final String name;
  final String region;
  final String currency;
  final int unitsSold;
  final double gmv;
  final double usdGmv;
  final int totalAffiliateCount;
  final int saleProductCount;
  final String unitsSoldIncRate;
  final String gmvIncRate;

  const FmFullyManagedShop({
    required this.sellerId,
    required this.name,
    required this.region,
    required this.currency,
    required this.unitsSold,
    required this.gmv,
    required this.usdGmv,
    this.totalAffiliateCount = 0,
    this.saleProductCount = 0,
    this.unitsSoldIncRate = '',
    this.gmvIncRate = '',
  });

  factory FmFullyManagedShop.fromApi(Map<String, dynamic> json) {
    final info = json['shop_info'];
    final Map<String, dynamic> si =
        info is Map ? Map<String, dynamic>.from(info) : <String, dynamic>{};
    return FmFullyManagedShop(
      sellerId: _toStr(si['seller_id']),
      name: _toStr(si['name']),
      region: _toStr(si['region']),
      currency: _toStr(json['currency'] ?? si['currency']),
      unitsSold: _toInt(json['units_sold']),
      gmv: _toDouble(json['gmv']),
      usdGmv: _toDouble(json['usd_gmv']),
      totalAffiliateCount: _toInt(json['total_affiliate_count']),
      saleProductCount: _toInt(json['sale_product_count']),
      unitsSoldIncRate: _toStr(json['units_sold_inc_rate']),
      gmvIncRate: _toStr(json['gmv_inc_rate']),
    );
  }
}

