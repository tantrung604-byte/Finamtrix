import 'dart:math';
import 'dart:convert';
import 'database_helper.dart';
import 'fomo_service.dart';
import 'forecast_service.dart';
import 'ai_gateway_service.dart';
import 'facebook_competitor_service.dart';

class AiCmoEngine {
  static final AiCmoEngine instance = AiCmoEngine._init();
  AiCmoEngine._init();

  /// Runs the Rule Engine to generate suggestions for a user.
  /// Rules R1-R6 from 04_ai_cmo_spec.md
  Future<List<Map<String, dynamic>>> runRuleEngine(String userId) async {
    final db = await DatabaseHelper.instance.database;
    final today = DateTime.now().toIso8601String().split('T')[0];
    final yearMonth = today.substring(0, 7); // YYYY-MM

    List<Map<String, dynamic>> suggestions = [];

    // --- R1: Underperforming Channel ---
    final forecast = await ForecastService.instance.calculateReverseFunnel(userId, yearMonth);
    if (forecast.isNotEmpty) {
      for (var channel in forecast['channels']) {
        final targetOrders = (channel['orders'] as double);
        
        // Get actual orders for this month
        final actualResult = await db.rawQuery('''
          SELECT SUM(actual_orders) as total
          FROM channel_actual_performance
          WHERE channel_config_id IN (
            SELECT channel_config_id FROM user_channel_config 
            WHERE user_id = ? AND channel_key = ?
          ) AND record_date LIKE ?
        ''', [userId, channel['channel_key'], '$yearMonth%']);

        final actualOrders = (actualResult.first['total'] as num ?? 0).toDouble();
        
        // Progress expected (simplified: 1/30 per day)
        final dayOfMonth = DateTime.now().day;
        final expectedOrders = targetOrders * (dayOfMonth / 30);

        if (actualOrders < expectedOrders * 0.8) {
          suggestions.add({
            'rule_id': 'R1_underperform',
            'priority': 'high',
            'data': {
              'channel': channel['label'],
              'actual': actualOrders,
              'expected': expectedOrders,
              'deviation': ((expectedOrders - actualOrders) / expectedOrders) * 100,
            }
          });
        }
      }
    }

    // --- R4: FOMO vs Intent (Customized) ---
    final fomoResult = await db.query(
      'fomo_score_daily',
      where: 'asset_type = ?',
      whereArgs: ['gold'],
      orderBy: 'date DESC',
      limit: 1,
    );

    if (fomoResult.isNotEmpty) {
      final fomoScore = (fomoResult.first['fomo_score'] as num).toDouble();
      final intentResult = await db.query(
        'capital_intent',
        where: 'user_id = ? AND asset_type = ?',
        whereArgs: [userId, 'gold'],
      );

      if (intentResult.isNotEmpty) {
        final intent = intentResult.first['planned_action'];
        
        if (fomoScore > 80 && intent == 'planning_to_buy') {
          suggestions.add({
            'rule_id': 'R4_fomo_alert',
            'priority': 'extreme',
            'data': {
              'asset': 'Vàng',
              'score': fomoScore,
              'intent': 'Mua',
              'warning': 'Nhiệt độ thị trường quá cao, hãy cẩn thận bẫy tâm lý.',
            }
          });
        }
      }
    }

    // --- R5: Missing Data Reminder ---
    // ... (existing R5 code) ...

    // --- R7: Competitor Strategy Alert (NEW) ---
    // Find keywords based on user business type or channel labels
    final businessType = (await db.query('users', columns: ['business_type'], where: 'user_id = ?', whereArgs: [userId])).first['business_type'] as String? ?? 'E-commerce';
    
    try {
      final competitorAds = await FacebookCompetitorService.instance.searchCompetitorAds(businessType);
      if (competitorAds.isNotEmpty) {
        // Take top 3 competitors for richer context
        final topCompetitors = competitorAds.take(3).map((a) => a.pageName).toSet().join(', ');
        final primaryStrategy = competitorAds.first.adCopy.substring(0, min(competitorAds.first.adCopy.length, 150));

        suggestions.add({
          'rule_id': 'R7_competitor_plan',
          'priority': 'medium',
          'data': {
            'competitor_count': competitorAds.length,
            'competitors': topCompetitors,
            'primary_ad_copy': primaryStrategy,
            'business_context': businessType,
            'insight': 'Phát hiện chiến dịch mới từ $topCompetitors. Cần lên Plan đối ứng ngay.',
          }
        });
      }
    } catch (e) {
      print('Failed R7 Rule: $e');
    }

    // Save and return
    List<Map<String, dynamic>> finalSuggestions = [];
    for (var sug in suggestions) {
      final logEntry = await _saveSuggestionLog(userId, sug);
      finalSuggestions.add({
        ...sug,
        'content': logEntry['content_snapshot'],
      });
    }

    return finalSuggestions;
  }

  Future<Map<String, dynamic>> _saveSuggestionLog(String userId, Map<String, dynamic> sug) async {
    final db = await DatabaseHelper.instance.database;
    
    // Call AI Gateway to handle rephrasing (Backend decides to use Opus 4.8)
    String content = 'Kiểm tra dữ liệu: ${jsonEncode(sug['data'])}'; // Fallback
    try {
      final response = await AiGatewayService.instance.processAiRequest(
        prompt: jsonEncode(sug['data']),
        taskType: 'rephrase',
        context: {
          'rule_id': sug['rule_id'],
          ...sug['data'],
        },
      );
      content = response;
    } catch (e) {
      print('Gateway failed to rephrase: $e');
    }

    final Map<String, dynamic> logEntry = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'user_id': userId,
      'rule_id': sug['rule_id'],
      'generated_date': DateTime.now().toIso8601String().split('T')[0],
      'content_snapshot': content,
      'raw_data_snapshot': jsonEncode(sug['data']),
      'status': 'pending',
    };

    await db.insert('cmo_suggestion_log', logEntry);
    return logEntry;
  }
}
