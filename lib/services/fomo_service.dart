import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class FomoService {
  static final FomoService instance = FomoService._init();
  FomoService._init();

  /// Calculates the FOMO score based on the price history.
  /// Follows the logic from 01_fomo_score_spec.md
  ///
  /// Supports multiple assets:
  ///  - 'gold'  → gold_price_daily.price_sell (domestic only)
  ///  - 'stock' → market_index_daily.close (default symbol VNINDEX)
  ///  - 'rate'  → deposit_interest_rate.value (average 12m/13m)
  Future<void> calculateAndSaveFomoScore(
    String assetType, {
    String indexSymbol = 'VNINDEX',
  }) async {
    final db = await DatabaseHelper.instance.database;

    // 1. Get price history (last 90 days for z-score), newest first.
    List<double> series;
    if (assetType == 'stock') {
      final rows = await db.query(
        'market_index_daily',
        columns: ['close'],
        where: 'symbol = ?',
        whereArgs: [indexSymbol],
        orderBy: 'date DESC',
        limit: 90,
      );
      series = rows.map((r) => (r['close'] as num).toDouble()).toList();
    } else if (assetType == 'rate') {
      final rows = await db.rawQuery(
        'SELECT AVG(value) as avg_value FROM deposit_interest_rate '
        'WHERE duration_months = 12 OR duration_months = 13 '
        'GROUP BY effective_date ORDER BY effective_date DESC LIMIT 90'
      );
      series = rows.map((r) => (r['avg_value'] as num).toDouble()).toList();
    } else {
      final rows = await db.query(
        'gold_price_daily',
        columns: ['price_sell'],
        where: 'type = ?',
        whereArgs: ['domestic'],
        orderBy: 'date DESC',
        limit: 90,
      );
      series = rows.map((r) => (r['price_sell'] as num).toDouble()).toList();
    }

    if (series.isEmpty) return;

    final daysOfData = series.length;
    double? fomoScore;
    String calculationMode;
    String? zone;
    double? change7dPct;

    // Calculate 7-day change for R1
    if (daysOfData >= 7) {
      final currentPrice = series[0];
      final price7dAgo = series[6];
      change7dPct = ((currentPrice - price7dAgo) / price7dAgo) * 100;
    }

    // 2. Determine calculation mode
    if (daysOfData < 7) {
      // Phase 1: Not enough data
      calculationMode = 'insufficient_data';
    } else if (daysOfData < 30) {
      // Phase 2: Simple growth calculation (Cold Start)
      calculationMode = 'simple';
      fomoScore = _calculateSimpleScore(change7dPct!);
    } else {
      // Phase 3: Z-score calculation
      calculationMode = 'zscore';
      fomoScore = _calculateZScore(series);
    }

    if (fomoScore != null) {
      zone = _determineZone(fomoScore);
    }

    // 3. Save to database
    await db.insert(
      'fomo_score_daily',
      {
        'date': DateTime.now().toIso8601String().split('T')[0],
        'asset_type': assetType,
        'fomo_score': fomoScore,
        'zone': zone,
        'calculation_mode': calculationMode,
        'days_of_data': daysOfData,
        'change_7d_pct': change7dPct,
        'data_anomaly_flagged': 0, // Simplified for MVP
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  double _calculateSimpleScore(double change7dPct) {
    // Simple mapping: 1% change ~ 10 points
    // Base 50 + (change * 10)
    double score = 50 + (change7dPct * 10);
    return score.clamp(0, 100);
  }

  double _calculateZScore(List<double> prices) {
    // Current price is index 0
    final currentPrice = prices[0];
    
    // Mean of previous days (excluding today)
    final historicalPrices = prices.sublist(1);
    final mean = historicalPrices.reduce((a, b) => a + b) / historicalPrices.length;
    
    // Standard deviation
    final sumOfSquares = historicalPrices.map((p) => pow(p - mean, 2)).reduce((a, b) => a + b);
    final stdDev = sqrt(sumOfSquares / historicalPrices.length);
    
    if (stdDev == 0) return 50.0;

    final z = (currentPrice - mean) / stdDev;
    
    // Map Z-score to 0-100 scale
    // Z = 0 -> 50
    // Z = 2 -> 90 (Greed)
    // Z = -2 -> 10 (Fear)
    double score = 50 + (z * 20);
    return score.clamp(0, 100);
  }

  String _determineZone(double score) {
    if (score < 30) return 'safe';
    if (score < 60) return 'warm';
    if (score < 85) return 'danger';
    return 'extreme'; // As per spec "hot/danger"
  }
}
