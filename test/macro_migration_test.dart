import 'package:flutter_test/flutter_test.dart';
import 'package:finmatrix_flutter/services/deposit_rate_service.dart';
import 'package:finmatrix_flutter/services/cpi_service.dart';

void main() {
  test('DepositRateService parses WIFEED group data', () {
    final service = DepositRateService.instance;
    final json = {
      "data": [
        {
          "ngay": "2026-06-30",
          "lai_suat_huy_dong_3m_sobs": 5.15,
          "lai_suat_huy_dong_13m_nhom_mbb_acb_tcb": 8.375
        }
      ]
    };

    final points = service.parseResponse(json);
    expect(points.length, 2);
    
    final p3m = points.firstWhere((p) => p.durationMonths == 3);
    expect(p3m.valuePct, 5.15);
    expect(p3m.organizationId, 1001);

    final p13m = points.firstWhere((p) => p.durationMonths == 13);
    expect(p13m.valuePct, 8.375);
    expect(p13m.organizationId, 1002);
  });

  test('CpiService parses WIFEED CPI data', () {
    final service = CpiService.instance;
    final json = {
      "data": [
        {
          "ngay": "2026-06-01",
          "cpi": 105.5,
          "cpi_yoy": 3.8,
          "cpi_mom": 0.2
        }
      ]
    };

    final points = service.parseResponse(json);
    expect(points.length, 1);
    expect(points.first.cpiYoY, 3.8);
    expect(points.first.date, "2026-06-01");
  });
}
