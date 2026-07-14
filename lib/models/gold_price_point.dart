/// A single day's gold price point, parsed from the vang.today API
/// (`https://www.vang.today/api/prices?type=...&days=N`).
class GoldPricePoint {
  /// ISO date, e.g. "2026-06-28".
  final String date;

  /// Buy price in VND.
  final double buy;

  /// Sell price in VND.
  final double sell;

  /// Human-readable product name, e.g. "SJC 9999".
  final String name;

  /// Day-over-day change of the sell price in VND (may be 0).
  final double dayChangeSell;

  const GoldPricePoint({
    required this.date,
    required this.buy,
    required this.sell,
    required this.name,
    required this.dayChangeSell,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'buy': buy,
        'sell': sell,
        'name': name,
        'day_change_sell': dayChangeSell,
      };

  factory GoldPricePoint.fromJson(Map<String, dynamic> json) {
    return GoldPricePoint(
      date: json['date'] as String,
      buy: (json['buy'] as num).toDouble(),
      sell: (json['sell'] as num).toDouble(),
      name: json['name'] as String? ?? '',
      dayChangeSell: (json['day_change_sell'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// The tracking windows requested: 7 ngày, 30 ngày, 3 tháng, 1 năm.
enum GoldRange {
  week(7, '7 ngày'),
  month(30, '30 ngày'),
  quarter(90, '3 tháng'),
  year(365, '1 năm');

  const GoldRange(this.days, this.label);

  /// Number of days the window covers.
  final int days;

  /// Vietnamese label for UI.
  final String label;
}

