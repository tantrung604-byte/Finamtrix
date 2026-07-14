/// A single Consumer Price Index (CPI) record from WIFEED.
class CpiPoint {
  /// Date "yyyy-MM-dd".
  final String date;

  /// Absolute CPI value.
  final double? cpi;

  /// Year-on-year change (%).
  final double? cpiYoY;

  /// Month-on-month change (%).
  final double? cpiMoM;

  const CpiPoint({
    required this.date,
    this.cpi,
    this.cpiYoY,
    this.cpiMoM,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'cpi': cpi,
        'cpi_yoy': cpiYoY,
        'cpi_mom': cpiMoM,
      };

  factory CpiPoint.fromJson(Map<String, dynamic> json) => CpiPoint(
        date: json['ngay'] ?? json['date'] ?? '',
        cpi: (json['cpi'] as num?)?.toDouble(),
        cpiYoY: (json['cpi_yoy'] as num?)?.toDouble(),
        cpiMoM: (json['cpi_mom'] as num?)?.toDouble(),
      );
}
