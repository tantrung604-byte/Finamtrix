import 'package:flutter_test/flutter_test.dart';
import 'package:finmatrix_flutter/services/forecast_service.dart';
import 'package:finmatrix_flutter/services/macro_micro_link_service.dart';

void main() {
  group('ForecastService.calculateScenarios', () {
    final baseForecast = {
      'target_revenue': 200000000.0,
      'total_orders': 400.0,
      'total_ad_budget': 30000000.0,
      'break_even_orders': 250.0,
    };

    test('returns three scenarios with correct ordering of revenue', () {
      final scenarios = ForecastService.instance.calculateScenarios(
        baseForecast: baseForecast,
        grossMarginPct: 50,
        fixedCost: 20000000,
      );

      expect(scenarios.length, 3);
      final opt = scenarios.firstWhere((s) => s.key == 'optimistic');
      final real = scenarios.firstWhere((s) => s.key == 'realistic');
      final pes = scenarios.firstWhere((s) => s.key == 'pessimistic');

      // Optimistic should beat realistic, which should beat pessimistic.
      expect(opt.revenue, greaterThan(real.revenue));
      expect(real.revenue, greaterThan(pes.revenue));
      expect(opt.deltaPct, greaterThan(pes.deltaPct));
    });

    test('realistic scenario has zero net-profit delta vs base', () {
      final scenarios = ForecastService.instance.calculateScenarios(
        baseForecast: baseForecast,
        grossMarginPct: 50,
        fixedCost: 20000000,
      );
      final real = scenarios.firstWhere((s) => s.key == 'realistic');
      expect(real.deltaPct.abs() < 0.01, isTrue);
    });

    test('break-even gap is positive when orders exceed break-even', () {
      final scenarios = ForecastService.instance.calculateScenarios(
        baseForecast: baseForecast,
        grossMarginPct: 50,
        fixedCost: 20000000,
      );
      final opt = scenarios.firstWhere((s) => s.key == 'optimistic');
      // 400 * 1.35 = 540 orders > 250 break-even.
      expect(opt.breakEvenGap, greaterThan(0));
    });

    test('demandMultiplier dampens all scenario orders', () {
      final full = ForecastService.instance.calculateScenarios(
        baseForecast: baseForecast,
        grossMarginPct: 50,
        fixedCost: 20000000,
        demandMultiplier: 1.0,
      );
      final damped = ForecastService.instance.calculateScenarios(
        baseForecast: baseForecast,
        grossMarginPct: 50,
        fixedCost: 20000000,
        demandMultiplier: 0.9,
      );
      for (final key in ['optimistic', 'realistic', 'pessimistic']) {
        final f = full.firstWhere((s) => s.key == key);
        final d = damped.firstWhere((s) => s.key == key);
        expect(d.orders, lessThan(f.orders));
      }
    });

    test('returns empty list when input data is missing', () {
      final scenarios = ForecastService.instance.calculateScenarios(
        baseForecast: const {'target_revenue': 0.0, 'total_orders': 0.0},
        grossMarginPct: 0,
        fixedCost: 0,
      );
      expect(scenarios, isEmpty);
    });

    test('projection has 6 months and compounds for optimistic', () {
      final scenarios = ForecastService.instance.calculateScenarios(
        baseForecast: baseForecast,
        grossMarginPct: 50,
        fixedCost: 20000000,
      );
      final opt = scenarios.firstWhere((s) => s.key == 'optimistic');
      expect(opt.projection.length, 6);
      expect(opt.projection.last, greaterThan(opt.projection.first));
    });
  });

  group('MacroMicroLinkService.mapSignals', () {
    final svc = MacroMicroLinkService.instance;

    test('safe zone yields no impact', () {
      final impact = svc.mapSignals(fomoScore: 20, change7dPct: 0, zone: 'safe');
      expect(impact.hasImpact, isFalse);
      expect(impact.purchasingPowerFactor, 1.0);
    });

    test('extreme zone reduces purchasing power and flags high severity', () {
      final impact = svc.mapSignals(fomoScore: 90, change7dPct: 1, zone: 'extreme');
      expect(impact.severity, MacroImpactSeverity.high);
      expect(impact.purchasingPowerFactor, lessThan(1.0));
      expect(impact.deltaPct, lessThan(0));
    });

    test('sharp 7-day surge amplifies the drop', () {
      final calm = svc.mapSignals(fomoScore: 70, change7dPct: 0, zone: 'danger');
      final surge = svc.mapSignals(fomoScore: 70, change7dPct: 6, zone: 'danger');
      expect(surge.deltaPct, lessThan(calm.deltaPct));
    });

    test('impact is capped at 15%', () {
      final impact = svc.mapSignals(fomoScore: 100, change7dPct: 20, zone: 'extreme');
      expect(impact.purchasingPowerFactor, greaterThanOrEqualTo(0.85));
    });
  });
}

