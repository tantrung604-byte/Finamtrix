import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/competitor_ad.dart';

class FacebookCompetitorService {
  static final FacebookCompetitorService instance = FacebookCompetitorService._init();
  FacebookCompetitorService._init();

  // Using Apify for global Facebook Ad Library scraping as a reliable alternative to restricted official API
  static const String _apifyBaseUrl = 'https://api.apify.com/v2/acts/apify~facebook-ads-scraper/run-sync-get-dataset-items';

  Future<List<CompetitorAd>> searchCompetitorAds(String keyword) async {
    final prefs = await SharedPreferences.getInstance();
    final apifyToken = prefs.getString('apify_api_token');

    if (apifyToken == null || apifyToken.isEmpty) {
      print('Apify Token not configured. Please add it in settings.');
      return [];
    }

    try {
      final response = await http.post(
        Uri.parse('$_apifyBaseUrl?token=$apifyToken'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "searchQuery": keyword,
          "activeStatus": "active",
          "limit": 10,
          "viewAllAds": true
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((item) => CompetitorAd.fromJson(item)).toList();
      } else {
        print('Apify Error: ${response.body}');
        return [];
      }
    } catch (e) {
      print('Exception in FacebookCompetitorService: $e');
      return [];
    }
  }
}
