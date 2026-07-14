import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/gold_price_point.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._init();
  SupabaseService._init();

  static const String _supabaseUrl = 'https://your-project.supabase.co';
  static const String _supabaseAnonKey = 'your-anon-key';

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        publishableKey: _supabaseAnonKey,
      );
      _isInitialized = true;
    } catch (e) {
      print('Supabase initialization failed: $e');
    }
  }

  SupabaseClient get client => Supabase.instance.client;

  /// Upserts a gold price point into the 'gold_prices' table.
  Future<void> upsertGoldPrice(GoldPricePoint point) async {
    if (!_isInitialized) return;
    try {
      await client.from('gold_prices').upsert(
        point.toJson(),
        onConflict: 'date',
      );
    } catch (e) {
      print('Supabase upsert failed: $e');
    }
  }

  /// Fetches the latest gold prices from the 'gold_prices' table.
  Future<List<GoldPricePoint>> getLatestGoldPrices({int limit = 365}) async {
    if (!_isInitialized) return [];
    try {
      final response = await client
          .from('gold_prices')
          .select()
          .order('date', ascending: false)
          .limit(limit);
      
      return (response as List)
          .map((data) => GoldPricePoint.fromJson(data as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Supabase fetch failed: $e');
      return [];
    }
  }
}
