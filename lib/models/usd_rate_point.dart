/// A single day's USD/VND exchange-rate snapshot from Vietcombank.
class UsdRatePoint {
  /// ISO date, e.g. "2026-06-28".
  final String date;

  /// Cash (tiền mặt) buy rate in VND. May be null if not quoted.
  final double? cash;

  /// Transfer (chuyển khoản) buy rate in VND.
  final double transfer;

  /// Sell (bán ra) rate in VND.
  final double sell;

  const UsdRatePoint({
    required this.date,
    required this.cash,
    required this.transfer,
    required this.sell,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'cash': cash,
        'transfer': transfer,
        'sell': sell,
      };
}

