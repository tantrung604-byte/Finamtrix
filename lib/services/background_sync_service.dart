import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:workmanager/workmanager.dart';
import 'gold_price_service.dart';
import 'database_helper.dart';
import 'supabase_service.dart';
import 'deposit_rate_service.dart';
import 'exchange_rate_service.dart';
import 'stock_index_service.dart';
import 'cpi_service.dart';
import 'fastmoss_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("Native background task started: $task");
    
    // Initialize services in background isolate
    await DatabaseHelper.ensureInitialized();
    await SupabaseService.instance.initialize();
    
    try {
      if (task == 'syncGoldPrices' || task == 'syncMarketData') {
        await BackgroundSyncService.syncAllMarketData();
      }
      return Future.value(true);
    } catch (e) {
      print("Background task failed: $e");
      return Future.value(false);
    }
  });
}

class BackgroundSyncService {
  static final BackgroundSyncService instance = BackgroundSyncService._init();
  BackgroundSyncService._init();

  Timer? _desktopTimer;

  /// Refreshes every market data source used across the app. Best-effort:
  /// each source is guarded so one failure doesn't block the others.
  static Future<void> syncAllMarketData() async {
    Future<void> guard(String name, Future<void> Function() run) async {
      try {
        await run();
      } catch (e) {
        print('Realtime sync [$name] failed: $e');
      }
    }

    await Future.wait([
      guard('gold', () => GoldPriceService.instance.syncGoldHistory(days: 1)),
      guard('worldGold', () => GoldPriceService.instance.syncGoldHistory(type: GoldPriceService.worldType)),
      guard('stock', () => StockIndexService.instance.syncIndexHistory(days: 1)),
      guard('usd', () => ExchangeRateService.instance.syncTodayRate()),
      guard('deposit', () => DepositRateService.instance.syncDepositRates()),
      guard('cpi', () => CpiService.instance.syncCpiHistory()),
      guard('fastmoss', () => _syncFastmossForCurrentCategory()),
    ]);
  }

  /// Refreshes FastMoss trends for the user's current category (7 & 30 day).
  static Future<void> _syncFastmossForCurrentCategory() async {
    final db = await DatabaseHelper.instance.database;
    String category = 'Thời trang';
    final rows = await db.query('users', columns: ['business_type'], where: 'user_id = ?', whereArgs: ['default_user']);
    if (rows.isNotEmpty && rows.first['business_type'] != null) {
      category = rows.first['business_type'] as String;
    }
    for (final period in const [7, 30]) {
      await FastmossService.instance.syncCategoryTrends(category, periodDays: period);
      await FastmossService.instance.syncCreatorTrends(category, periodDays: period);
    }
  }

  Future<void> initialize() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: true, // Set to false for production
      );
      
      await Workmanager().registerPeriodicTask(
        '1',
        'syncMarketData',
        frequency: const Duration(minutes: 15), // Workmanager min frequency is 15 mins
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );
    } else {
      // Desktop fallback: Timer-based sync every 5 minutes when app is active
      _startDesktopSync();
    }
  }

  void _startDesktopSync() {
    _desktopTimer?.cancel();
    _desktopTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      print("Desktop background sync started");
      await syncAllMarketData();
    });
  }

  void stop() {
    _desktopTimer?.cancel();
  }
}
