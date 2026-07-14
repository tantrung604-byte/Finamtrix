import 'database_helper.dart';

/// Severity of the macro -> micro impact.
enum MacroImpactSeverity { none, low, medium, high }

/// Result of translating macro market heat (FOMO) into a micro (B2C) impact.
class MacroMicroImpact {
  /// Multiplier applied to expected demand (1.0 = no impact, <1 = weaker purchasing power).
  final double purchasingPowerFactor;

  /// Percentage change in purchasing power (e.g. -8 means demand expected 8% lower).
  final double deltaPct;

  final String zone;
  final double fomoScore;
  final double change7dPct;
  final MacroImpactSeverity severity;
  final String message;

  const MacroMicroImpact({
    required this.purchasingPowerFactor,
    required this.deltaPct,
    required this.zone,
    required this.fomoScore,
    required this.change7dPct,
    required this.severity,
    required this.message,
  });

  bool get hasImpact => severity != MacroImpactSeverity.none;

  factory MacroMicroImpact.neutral() => const MacroMicroImpact(
        purchasingPowerFactor: 1.0,
        deltaPct: 0,
        zone: 'unknown',
        fomoScore: 0,
        change7dPct: 0,
        severity: MacroImpactSeverity.none,
        message: 'Thị trường vĩ mô ổn định, chưa ảnh hưởng đáng kể đến sức mua.',
      );
}

/// Links macro signals (gold FOMO heat) to micro B2C purchasing power.
///
/// Rationale: when safe-haven assets (gold) heat up and prices spike, consumers
/// tend to hoard / shift money out of discretionary B2C spending, so a shop's
/// achievable demand drops. This service quantifies that into a demand factor
/// and a human-readable alert — the core "Macro -> Micro" USP.
class MacroMicroLinkService {
  static final MacroMicroLinkService instance = MacroMicroLinkService._init();
  MacroMicroLinkService._init();

  /// Computes the purchasing-power impact from the latest gold FOMO record.
  Future<MacroMicroImpact> computeImpact({String assetType = 'gold'}) async {
    final db = await DatabaseHelper.instance.database;

    final rows = await db.query(
      'fomo_score_daily',
      where: 'asset_type = ?',
      whereArgs: [assetType],
      orderBy: 'date DESC',
      limit: 1,
    );

    if (rows.isEmpty || rows.first['fomo_score'] == null) {
      return MacroMicroImpact.neutral();
    }

    final double fomoScore = (rows.first['fomo_score'] as num).toDouble();
    final double change7d = ((rows.first['change_7d_pct'] as num?) ?? 0).toDouble();
    final String zone = (rows.first['zone'] as String?) ?? 'warm';

    return _mapToImpact(fomoScore: fomoScore, change7dPct: change7d, zone: zone);
  }

  /// Pure mapping from macro signals to a micro impact (kept separate for testing).
  MacroMicroImpact mapSignals({
    required double fomoScore,
    required double change7dPct,
    required String zone,
  }) {
    return _mapToImpact(fomoScore: fomoScore, change7dPct: change7dPct, zone: zone);
  }

  MacroMicroImpact _mapToImpact({
    required double fomoScore,
    required double change7dPct,
    required String zone,
  }) {
    // Base drop derived from FOMO zone (heat of the safe-haven asset).
    double dropPct; // positive number = reduction in purchasing power
    MacroImpactSeverity severity;

    switch (zone) {
      case 'extreme':
        dropPct = 8.0;
        severity = MacroImpactSeverity.high;
        break;
      case 'danger':
        dropPct = 4.0;
        severity = MacroImpactSeverity.medium;
        break;
      case 'warm':
        dropPct = 1.5;
        severity = MacroImpactSeverity.low;
        break;
      default: // safe
        dropPct = 0.0;
        severity = MacroImpactSeverity.none;
    }

    // Amplify when the 7-day price surge is sharp (stronger hoarding signal).
    if (change7dPct >= 5) {
      dropPct += 3.0;
      if (severity.index < MacroImpactSeverity.high.index) {
        severity = MacroImpactSeverity.values[severity.index + 1];
      }
    } else if (change7dPct >= 2) {
      dropPct += 1.5;
    }

    // Cap the impact so the model stays conservative for MVP.
    dropPct = dropPct.clamp(0.0, 15.0);

    final double factor = 1 - (dropPct / 100.0);
    final String message = _buildMessage(zone, dropPct, change7dPct);

    return MacroMicroImpact(
      purchasingPowerFactor: factor,
      deltaPct: -dropPct,
      zone: zone,
      fomoScore: fomoScore,
      change7dPct: change7dPct,
      severity: severity,
      message: message,
    );
  }

  String _buildMessage(String zone, double dropPct, double change7dPct) {
    if (dropPct <= 0) {
      return 'Thị trường vĩ mô ổn định, chưa ảnh hưởng đáng kể đến sức mua.';
    }
    final String trend = change7dPct >= 2 ? 'Giá Vàng tăng mạnh' : 'Nhiệt độ Vàng đang cao';
    return '$trend → dòng tiền dồn vào trú ẩn → sức mua B2C dự kiến giảm ~${dropPct.round()}%. '
        'Cân nhắc giảm nhập hàng, đẩy khuyến mãi giữ chân khách.';
  }
}

