/// A single bank deposit interest-rate record.
///
/// Field mapping from the API schema:
///   - [effectiveDate]   ← EffectiveDateId   (ngày có hiệu lực, ISO yyyy-MM-dd)
///   - [valuePct]        ← Value × 100        (API trả 0.0415 → 4.15%)
///   - [durationMonths]  ← parsed từ DurationName ("60 tháng" → 60)
///   - [organizationId]  ← OrganizationId    (ngân hàng)
///   - [typeId]/[typeName] ← DepositInterestRateVNTypeId / ...TypeName
///   - [isIndividual]    ← IsIndividual      (cá nhân vs tổ chức)
class DepositRatePoint {
  /// ISO date "yyyy-MM-dd" (EffectiveDateId).
  final String effectiveDate;

  /// Lãi suất theo phần trăm/năm, e.g. 4.15 (đã nhân 100 từ giá trị thô 0.0415).
  final double valuePct;

  /// Kỳ hạn theo tháng, suy ra từ DurationName. Null nếu không phải kỳ hạn tháng.
  final int? durationMonths;

  /// OrganizationId or Bank Group ID.
  final int? organizationId;

  /// Loại lãi suất (DepositInterestRateVNTypeId).
  final int? typeId;

  /// Tên loại lãi suất, vd "Trả lãi định kỳ hàng tháng".
  final String? typeName;

  /// true: lãi suất cá nhân; false: tổ chức.
  final bool isIndividual;

  const DepositRatePoint({
    required this.effectiveDate,
    required this.valuePct,
    this.durationMonths,
    this.organizationId,
    this.typeId,
    this.typeName,
    this.isIndividual = false,
  });

  Map<String, dynamic> toJson() => {
        'effective_date': effectiveDate,
        'value_pct': valuePct,
        'duration_months': durationMonths,
        'organization_id': organizationId,
        'type_id': typeId,
        'type_name': typeName,
        'is_individual': isIndividual,
      };
}

/// Latest deposit rate for one commercial-bank (NHTM) group at a given term.
///
/// Produced by [DepositRateService.getBankGroupRates] for the Macro "Lãi suất"
/// breakdown and the home ticker.
class BankGroupRate {
  /// Group organization id (1001 SOBS, 1002 MBB/ACB/TCB, 1003 khác).
  final int groupId;

  /// Human-friendly Vietnamese label, e.g. "NHTM Nhà nước".
  final String name;

  /// Short example banks, e.g. "VCB · BIDV · CTG".
  final String banks;

  /// Kỳ hạn (tháng).
  final int durationMonths;

  /// Lãi suất %/năm.
  final double ratePct;

  /// ISO effective date "yyyy-MM-dd".
  final String effectiveDate;

  const BankGroupRate({
    required this.groupId,
    required this.name,
    required this.banks,
    required this.durationMonths,
    required this.ratePct,
    required this.effectiveDate,
  });
}

