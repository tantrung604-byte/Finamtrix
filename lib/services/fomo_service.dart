import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class FomoService {
  static final FomoService instance = FomoService._init();
  FomoService._init();

  /// Calculates the FOMO score based on the price history.
  /// Follows the logic from 01_fomo_score_spec.md
  Future<void> calculateAndSaveFomoScore(String assetType) async {
    final db = await DatabaseHelper.instance.database;
    
    // 1. Get price history (last 90 days for z-score)
    final prices = await db.query(
      'gold_price_daily',
      columns: ['price_sell'],
      orderBy: 'date DESC',
      limit: 90,
    );

    if (prices.isEmpty) return;

    final daysOfData = prices.length;
    double? fomoScore;
    String calculationMode;
    String? zone;
    double? change7dPct;

    // Calculate 7-day change for R1
    if (daysOfData >= 7) {
      final currentPrice = (prices[0]['price_sell'] as num).toDouble();
      final price7dAgo = (prices[6]['price_sell'] as num).toDouble();
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
      fomoScore = _calculateZScore(prices.map((p) => (p['price_sell'] as num).toDouble()).toList());
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
