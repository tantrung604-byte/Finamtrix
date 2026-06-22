class CompetitorAd {
  final String adId;
  final String pageName;
  final String adCopy;
  final String? imageUrl;
  final String? videoUrl;
  final DateTime? startDate;
  final bool isActive;
  final String platform; // facebook, instagram, etc.

  CompetitorAd({
    required this.adId,
    required this.pageName,
    required this.adCopy,
    this.imageUrl,
    this.videoUrl,
    this.startDate,
    required this.isActive,
    required this.platform,
  });

  Map<String, dynamic> toJson() => {
    'adId': adId,
    'pageName': pageName,
    'adCopy': adCopy,
    'imageUrl': imageUrl,
    'videoUrl': videoUrl,
    'startDate': startDate?.toIso8601String(),
    'isActive': isActive,
    'platform': platform,
  };

  factory CompetitorAd.fromJson(Map<String, dynamic> json) {
    return CompetitorAd(
      adId: json['id'] ?? '',
      pageName: json['page_name'] ?? '',
      adCopy: json['ad_snapshot_text'] ?? '',
      imageUrl: json['ad_snapshot_url'],
      videoUrl: json['video_url'],
      startDate: json['ad_delivery_start_time'] != null ? DateTime.parse(json['ad_delivery_start_time']) : null,
      isActive: json['is_active'] ?? true,
      platform: (json['publisher_platforms'] as List?)?.join(', ') ?? 'facebook',
    );
  }
}
