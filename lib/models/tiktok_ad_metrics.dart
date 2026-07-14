/// Raw metrics returned from the TikTok Ads / Shop API for a given period.
///
/// In production this is populated from a real API call; the demo uses
/// hardcoded data. The shape is intentionally flat so it can be serialized
/// to JSON and handed to the (deterministic) Rule Engine and then to Claude.
class TikTokVideoMetrics {
  final String videoId;
  final String title;
  final int impressions;
  final int likes;
  final int comments;
  final int shares;
  final int clicks;
  final int conversions;

  /// Ad spend on this video, in VND.
  final double cost;

  /// Revenue attributed to this video, in VND.
  final double revenue;

  const TikTokVideoMetrics({
    required this.videoId,
    required this.title,
    required this.impressions,
    required this.likes,
    required this.comments,
    required this.shares,
    required this.clicks,
    required this.conversions,
    required this.cost,
    required this.revenue,
  });

  /// Total engagement actions (likes + comments + shares).
  int get engagements => likes + comments + shares;

  factory TikTokVideoMetrics.fromJson(Map<String, dynamic> json) {
    return TikTokVideoMetrics(
      videoId: json['video_id'] as String,
      title: json['title'] as String? ?? '',
      impressions: (json['impressions'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      comments: (json['comments'] as num?)?.toInt() ?? 0,
      shares: (json['shares'] as num?)?.toInt() ?? 0,
      clicks: (json['clicks'] as num?)?.toInt() ?? 0,
      conversions: (json['conversions'] as num?)?.toInt() ?? 0,
      cost: (json['cost'] as num?)?.toDouble() ?? 0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'video_id': videoId,
        'title': title,
        'impressions': impressions,
        'likes': likes,
        'comments': comments,
        'shares': shares,
        'clicks': clicks,
        'conversions': conversions,
        'cost': cost,
        'revenue': revenue,
      };
}

/// Aggregated account-level metrics for a reporting period plus the per-video
/// breakdown used by the Rule Engine.
class TikTokAdMetrics {
  final String shopId;
  final String periodStart;
  final String periodEnd;

  /// Cost of goods sold ratio (0..1). gross_margin = revenue * (1 - cogsRatio).
  final double cogsRatio;

  final List<TikTokVideoMetrics> videos;

  const TikTokAdMetrics({
    required this.shopId,
    required this.periodStart,
    required this.periodEnd,
    required this.cogsRatio,
    required this.videos,
  });

  int get totalImpressions =>
      videos.fold(0, (sum, v) => sum + v.impressions);
  int get totalEngagements =>
      videos.fold(0, (sum, v) => sum + v.engagements);
  double get totalCost => videos.fold(0.0, (sum, v) => sum + v.cost);
  double get totalRevenue => videos.fold(0.0, (sum, v) => sum + v.revenue);

  /// Gross margin in VND = revenue minus cost of goods sold.
  double get grossMargin => totalRevenue * (1 - cogsRatio);

  factory TikTokAdMetrics.fromJson(Map<String, dynamic> json) {
    return TikTokAdMetrics(
      shopId: json['shop_id'] as String? ?? '',
      periodStart: json['period_start'] as String? ?? '',
      periodEnd: json['period_end'] as String? ?? '',
      cogsRatio: (json['cogs_ratio'] as num?)?.toDouble() ?? 0,
      videos: (json['videos'] as List? ?? [])
          .map((v) => TikTokVideoMetrics.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'shop_id': shopId,
        'period_start': periodStart,
        'period_end': periodEnd,
        'cogs_ratio': cogsRatio,
        'videos': videos.map((v) => v.toJson()).toList(),
      };
}

