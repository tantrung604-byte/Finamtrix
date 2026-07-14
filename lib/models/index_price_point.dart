/// A single day's OHLC point for a market index (e.g. VNINDEX), parsed from
/// the VCI (Vietcap) data source used by vnstock.
class IndexPricePoint {
  /// ISO date, e.g. "2026-06-28".
  final String date;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const IndexPricePoint({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        'volume': volume,
      };
}

/// Tracking windows for index history: 7 ngày, 30 ngày, 3 tháng, 1 năm.
enum IndexRange {
  week(7, '7 ngày'),
  month(30, '30 ngày'),
  quarter(90, '3 tháng'),
  year(365, '1 năm');

  const IndexRange(this.days, this.label);

  final int days;
  final String label;
}

