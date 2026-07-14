/// A single trending TikTok Shop product for a business category,
/// sourced from FastMoss (fastmoss.com) analytics.
///
/// Used by the Micro (Vi Mô) "ngành hàng" section to show what is selling in
/// the user's category so budget/funnel decisions are grounded in market data.
class FastmossProductTrend {
  /// App business category this product belongs to (e.g. "Thời trang").
  final String category;

  /// Product / listing title.
  final String productName;

  /// Selling shop name (nullable when the source hides it).
  final String? shopName;

  /// Gross merchandise value over the tracking window, in VND.
  final double gmvVnd;

  /// Units sold over the tracking window.
  final int sales;

  /// Unit price in VND.
  final double priceVnd;

  /// Sales growth over the window, percent (e.g. 32.5 = +32.5%).
  final double growthPct;

  /// Commission rate offered to affiliates, percent (0 if unknown).
  final double commissionPct;

  /// Tracking window in days (7 or 30).
  final int periodDays;

  /// ISO date "yyyy-MM-dd" of the snapshot.
  final String snapshotDate;

  const FastmossProductTrend({
    required this.category,
    required this.productName,
    this.shopName,
    required this.gmvVnd,
    required this.sales,
    required this.priceVnd,
    required this.growthPct,
    this.commissionPct = 0,
    this.periodDays = 7,
    required this.snapshotDate,
  });

  /// Robust parser for one FastMoss product item. Keys are matched
  /// defensively because the internal API is undocumented and may vary.
  factory FastmossProductTrend.fromApi(
    Map<String, dynamic> json, {
    required String category,
    required String snapshotDate,
    int periodDays = 7,
  }) {
    double toD(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
      return 0;
    }

    int toI(dynamic v) => toD(v).round();

    return FastmossProductTrend(
      category: category,
      productName: (json['title'] ?? json['goods_title'] ?? json['name'] ?? 'Sản phẩm').toString(),
      shopName: (json['shop_name'] ?? json['seller_name'] ?? json['shop'])?.toString(),
      gmvVnd: toD(json['gmv'] ?? json['sale_amount'] ?? json['amount']),
      sales: toI(json['sales'] ?? json['sale_count'] ?? json['sold']),
      priceVnd: toD(json['price'] ?? json['avg_price']),
      growthPct: toD(json['growth'] ?? json['growth_rate'] ?? json['increase_rate']),
      commissionPct: toD(json['commission'] ?? json['commission_rate']),
      periodDays: periodDays,
      snapshotDate: snapshotDate,
    );
  }

  Map<String, dynamic> toDbMap() => {
        'category': category,
        'product_name': productName,
        'shop_name': shopName,
        'gmv_vnd': gmvVnd,
        'sales': sales,
        'price_vnd': priceVnd,
        'growth_pct': growthPct,
        'commission_pct': commissionPct,
        'period_days': periodDays,
        'snapshot_date': snapshotDate,
      };

  factory FastmossProductTrend.fromDbMap(Map<String, dynamic> r) => FastmossProductTrend(
        category: r['category'] as String,
        productName: r['product_name'] as String,
        shopName: r['shop_name'] as String?,
        gmvVnd: (r['gmv_vnd'] as num?)?.toDouble() ?? 0,
        sales: (r['sales'] as num?)?.toInt() ?? 0,
        priceVnd: (r['price_vnd'] as num?)?.toDouble() ?? 0,
        growthPct: (r['growth_pct'] as num?)?.toDouble() ?? 0,
        commissionPct: (r['commission_pct'] as num?)?.toDouble() ?? 0,
        periodDays: (r['period_days'] as num?)?.toInt() ?? 7,
        snapshotDate: r['snapshot_date'] as String,
      );
}

/// A trending TikTok creator (and their hottest video) for a business
/// category, sourced from FastMoss. Feeds the Micro "ngành hàng" section so
/// the user knows which KOC/KOL styles are driving sales.
class FastmossCreatorTrend {
  final String category;

  /// Creator display name.
  final String creatorName;

  /// @handle (nullable).
  final String? handle;

  /// Follower count.
  final int followers;

  /// Title of the creator's trending video.
  final String? videoTitle;

  /// Views on the trending video.
  final int views;

  /// Estimated GMV driven by the creator over the window, in VND.
  final double gmvVnd;

  /// Engagement rate percent (likes+comments+shares / views).
  final double engagementPct;

  /// Tracking window in days (7 or 30).
  final int periodDays;

  /// ISO date "yyyy-MM-dd" of the snapshot.
  final String snapshotDate;

  const FastmossCreatorTrend({
    required this.category,
    required this.creatorName,
    this.handle,
    required this.followers,
    this.videoTitle,
    required this.views,
    required this.gmvVnd,
    required this.engagementPct,
    this.periodDays = 7,
    required this.snapshotDate,
  });

  factory FastmossCreatorTrend.fromApi(
    Map<String, dynamic> json, {
    required String category,
    required String snapshotDate,
    int periodDays = 7,
  }) {
    double toD(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
      return 0;
    }

    int toI(dynamic v) => toD(v).round();

    return FastmossCreatorTrend(
      category: category,
      creatorName: (json['nickname'] ?? json['creator_name'] ?? json['name'] ?? 'Creator').toString(),
      handle: (json['unique_id'] ?? json['handle'] ?? json['username'])?.toString(),
      followers: toI(json['follower_count'] ?? json['followers'] ?? json['fans']),
      videoTitle: (json['video_title'] ?? json['desc'] ?? json['title'])?.toString(),
      views: toI(json['play_count'] ?? json['views'] ?? json['vv']),
      gmvVnd: toD(json['gmv'] ?? json['sale_amount'] ?? json['amount']),
      engagementPct: toD(json['engagement'] ?? json['engagement_rate'] ?? json['interaction_rate']),
      periodDays: periodDays,
      snapshotDate: snapshotDate,
    );
  }

  Map<String, dynamic> toDbMap() => {
        'category': category,
        'creator_name': creatorName,
        'handle': handle,
        'followers': followers,
        'video_title': videoTitle,
        'views': views,
        'gmv_vnd': gmvVnd,
        'engagement_pct': engagementPct,
        'period_days': periodDays,
        'snapshot_date': snapshotDate,
      };

  factory FastmossCreatorTrend.fromDbMap(Map<String, dynamic> r) => FastmossCreatorTrend(
        category: r['category'] as String,
        creatorName: r['creator_name'] as String,
        handle: r['handle'] as String?,
        followers: (r['followers'] as num?)?.toInt() ?? 0,
        videoTitle: r['video_title'] as String?,
        views: (r['views'] as num?)?.toInt() ?? 0,
        gmvVnd: (r['gmv_vnd'] as num?)?.toDouble() ?? 0,
        engagementPct: (r['engagement_pct'] as num?)?.toDouble() ?? 0,
        periodDays: (r['period_days'] as num?)?.toInt() ?? 7,
        snapshotDate: r['snapshot_date'] as String,
      );
}

/// Aggregated market snapshot for a category, computed from stored product
/// trends. Used to size the funnel/ad budget in the Micro screen.
class FastmossCategorySummary {
  final String category;

  /// Sum of product GMV in the tracked top list, VND.
  final double totalGmvVnd;

  /// Sum of units sold across the top list.
  final int totalSales;

  /// Average unit price, VND.
  final double avgPriceVnd;

  /// Average affiliate commission, percent.
  final double avgCommissionPct;

  /// Average sales growth of the top list, percent.
  final double avgGrowthPct;

  /// Number of products in the aggregation.
  final int productCount;

  /// Tracking window in days (7 or 30) the totals cover.
  final int periodDays;

  const FastmossCategorySummary({
    required this.category,
    required this.totalGmvVnd,
    required this.totalSales,
    required this.avgPriceVnd,
    required this.avgCommissionPct,
    required this.avgGrowthPct,
    required this.productCount,
    this.periodDays = 7,
  });

  bool get hasData => productCount > 0;

  /// Total GMV normalized to a 30-day month (for revenue-target sizing).
  double get monthlyGmvVnd => periodDays <= 0 ? totalGmvVnd : totalGmvVnd * (30.0 / periodDays);

  static const empty = FastmossCategorySummary(
    category: '',
    totalGmvVnd: 0,
    totalSales: 0,
    avgPriceVnd: 0,
    avgCommissionPct: 0,
    avgGrowthPct: 0,
    productCount: 0,
  );

  factory FastmossCategorySummary.fromProducts(
    String category,
    List<FastmossProductTrend> items, {
    int periodDays = 7,
  }) {
    if (items.isEmpty) return empty;
    double gmv = 0, price = 0, commission = 0, growth = 0;
    int sales = 0;
    for (final p in items) {
      gmv += p.gmvVnd;
      sales += p.sales;
      price += p.priceVnd;
      commission += p.commissionPct;
      growth += p.growthPct;
    }
    final n = items.length;
    return FastmossCategorySummary(
      category: category,
      totalGmvVnd: gmv,
      totalSales: sales,
      avgPriceVnd: price / n,
      avgCommissionPct: commission / n,
      avgGrowthPct: growth / n,
      productCount: n,
      periodDays: periodDays,
    );
  }
}

