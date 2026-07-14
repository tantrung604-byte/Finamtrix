import 'package:sqflite/sqflite.dart';

import 'database_platform_stub.dart'
    if (dart.library.io) 'database_platform_io.dart'
    if (dart.library.html) 'database_platform_web.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static bool _useInMemory = false;
  static const String _dbFileName = 'finmatrix.db';

  DatabaseHelper._init();

  /// Call before first DB access (required on Web for WASM factory setup).
  static Future<void> ensureInitialized() async {
    await initDatabasePlatform();
  }

  /// Resets the singleton and opens an in-memory DB for integration tests.
  static Future<Database> openForTesting() async {
    await initDatabasePlatformForTesting();
    await closeDatabase();
    _useInMemory = true;
    _database = await instance._openDatabase();
    return _database!;
  }

  static Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _useInMemory = false;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;

    await initDatabasePlatform();
    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    if (_useInMemory) {
      return openDatabase(
        inMemoryDatabasePath,
        version: 8,
        onCreate: _createDB,
        onUpgrade: _onUpgrade,
      );
    }

    final path = await resolveDatabasePath(_dbFileName);

    return openDatabase(
      path,
      version: 8,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  /// Schema migrations.
  ///  - v2 adds market_index_daily (stock indices).
  ///  - v3 adds usd_rate_daily (USD/VND exchange rate, Vietcombank).
  ///  - v4 adds deposit_interest_rate (bank deposit rates).
  ///  - v5 adds cpi_history and updates gold_price_daily for world gold.
  ///  - v6 adds fastmoss_category_trend (TikTok Shop category product trends).
  ///  - v7 adds fastmoss_creator_trend (TikTok creator/video trends).
  ///  - v8 adds period_days to FastMoss tables (7/30-day windows).
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createMarketIndexTable(db);
    }
    if (oldVersion < 3) {
      await _createUsdRateTable(db);
    }
    if (oldVersion < 4) {
      await _createDepositRateTable(db);
    }
    if (oldVersion < 5) {
      await _createCpiTable(db);
      await _upgradeGoldPriceTable(db);
    }
    if (oldVersion < 6) {
      await _createFastmossTable(db);
    }
    if (oldVersion < 7) {
      await _createFastmossCreatorTable(db);
    }
    if (oldVersion < 8) {
      // FastMoss tables hold disposable cache; rebuild with the period column.
      await db.execute('DROP TABLE IF EXISTS fastmoss_category_trend');
      await db.execute('DROP TABLE IF EXISTS fastmoss_creator_trend');
      await _createFastmossTable(db);
      await _createFastmossCreatorTable(db);
    }
  }

  /// TikTok Shop category product trends (FastMoss).
  /// One row per product × category × period × snapshot date.
  Future _createFastmossTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fastmoss_category_trend (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        product_name TEXT NOT NULL,
        shop_name TEXT,
        gmv_vnd REAL NOT NULL DEFAULT 0,
        sales INTEGER NOT NULL DEFAULT 0,
        price_vnd REAL NOT NULL DEFAULT 0,
        growth_pct REAL NOT NULL DEFAULT 0,
        commission_pct REAL NOT NULL DEFAULT 0,
        period_days INTEGER NOT NULL DEFAULT 7,
        snapshot_date TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'fastmoss',
        fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(category, product_name, period_days, snapshot_date)
      )
    ''');
  }

  /// TikTok creator/video trends per category (FastMoss).
  /// One row per creator × category × period × snapshot date.
  Future _createFastmossCreatorTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fastmoss_creator_trend (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        creator_name TEXT NOT NULL,
        handle TEXT,
        followers INTEGER NOT NULL DEFAULT 0,
        video_title TEXT,
        views INTEGER NOT NULL DEFAULT 0,
        gmv_vnd REAL NOT NULL DEFAULT 0,
        engagement_pct REAL NOT NULL DEFAULT 0,
        period_days INTEGER NOT NULL DEFAULT 7,
        snapshot_date TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'fastmoss',
        fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(category, creator_name, period_days, snapshot_date)
      )
    ''');
  }


  Future _createCpiTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cpi_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        cpi REAL,
        cpi_yoy REAL,
        cpi_mom REAL,
        fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(date)
      )
    ''');
  }

  Future _upgradeGoldPriceTable(Database db) async {
    // Check if type column already exists to avoid errors on partial upgrades
    final columns = await db.rawQuery('PRAGMA table_info(gold_price_daily)');
    final hasType = columns.any((c) => c['name'] == 'type');
    if (hasType) return;

    await db.execute('ALTER TABLE gold_price_daily RENAME TO gold_price_daily_old');
    await db.execute('''
      CREATE TABLE gold_price_daily (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'domestic',
        price_buy REAL NOT NULL,
        price_sell REAL NOT NULL,
        source TEXT NOT NULL,
        fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(date, type)
      )
    ''');
    await db.execute('''
      INSERT INTO gold_price_daily (date, type, price_buy, price_sell, source, fetched_at)
      SELECT date, 'domestic', price_buy, price_sell, source, fetched_at
      FROM gold_price_daily_old
    ''');
    await db.execute('DROP TABLE gold_price_daily_old');
  }

  Future _createMarketIndexTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS market_index_daily (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        symbol TEXT NOT NULL,
        date TEXT NOT NULL,
        open REAL NOT NULL,
        high REAL NOT NULL,
        low REAL NOT NULL,
        close REAL NOT NULL,
        volume REAL,
        source TEXT NOT NULL,
        fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(symbol, date)
      )
    ''');
  }

  Future _createUsdRateTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS usd_rate_daily (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT UNIQUE NOT NULL,
        cash REAL,
        transfer REAL NOT NULL,
        sell REAL NOT NULL,
        source TEXT NOT NULL,
        fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  /// Bank deposit interest rates (e.g. WIFEED group averages).
  /// One row per bank/group × duration × rate-type × effective date.
  Future _createDepositRateTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS deposit_interest_rate (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        organization_id INTEGER,
        duration_id INTEGER,
        duration_months INTEGER,
        type_id INTEGER,
        type_name TEXT,
        is_individual INTEGER NOT NULL DEFAULT 0,
        effective_date TEXT NOT NULL,
        value REAL NOT NULL,
        source TEXT NOT NULL,
        fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(organization_id, duration_months, type_id, is_individual, effective_date)
      )
    ''');
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const boolType = 'BOOLEAN NOT NULL';
    const intType = 'INTEGER NOT NULL';
    const decimalType = 'REAL NOT NULL';
    const decimalNullable = 'REAL';
    const timestampType = 'TIMESTAMP DEFAULT CURRENT_TIMESTAMP';

    // 1. users table
    await db.execute('''
      CREATE TABLE users (
        user_id TEXT PRIMARY KEY,
        phone_or_email TEXT UNIQUE NOT NULL,
        display_name TEXT NOT NULL,
        business_type TEXT,
        reminder_frequency_days INTEGER,
        subscription_tier TEXT NOT NULL DEFAULT 'free',
        created_at $timestampType
      )
    ''');

    // 2. gold_price_daily table
    await db.execute('''
      CREATE TABLE gold_price_daily (
        id $idType,
        date TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'domestic',
        price_buy $decimalType,
        price_sell $decimalType,
        source TEXT NOT NULL,
        fetched_at $timestampType,
        UNIQUE(date, type)
      )
    ''');

    // 2b. cpi_history table
    await _createCpiTable(db);

    // 3. fomo_score_daily table
    await db.execute('''
      CREATE TABLE fomo_score_daily (
        id $idType,
        date TEXT NOT NULL,
        asset_type TEXT NOT NULL,
        fomo_score $decimalNullable,
        zone TEXT,
        calculation_mode TEXT NOT NULL,
        days_of_data $intType,
        change_7d_pct $decimalNullable,
        data_anomaly_flagged $boolType,
        UNIQUE(date, asset_type)
      )
    ''');

    // 3b. market_index_daily table (stock indices: VNINDEX, HNXINDEX, ...)
    await _createMarketIndexTable(db);

    // 3c. usd_rate_daily table (USD/VND exchange rate, Vietcombank)
    await _createUsdRateTable(db);

    // 3d. deposit_interest_rate table (bank deposit rates)
    await _createDepositRateTable(db);

    // 4. business_profile table
    await db.execute('''
      CREATE TABLE business_profile (
        id $idType,
        user_id TEXT NOT NULL,
        effective_from TEXT NOT NULL,
        gross_margin_pct $decimalType,
        fixed_operating_cost $decimalNullable,
        created_at $timestampType,
        FOREIGN KEY (user_id) REFERENCES users (user_id)
      )
    ''');

    // 5. monthly_target table
    await db.execute('''
      CREATE TABLE monthly_target (
        id $idType,
        user_id TEXT NOT NULL,
        year_month TEXT NOT NULL,
        target_revenue $decimalType,
        created_at $timestampType,
        UNIQUE(user_id, year_month),
        FOREIGN KEY (user_id) REFERENCES users (user_id)
      )
    ''');

    // 6. sales_channel table
    await db.execute('''
      CREATE TABLE sales_channel (
        channel_key TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        channel_type TEXT NOT NULL,
        has_benchmark $boolType,
        is_system_default $boolType
      )
    ''');

    // 7. user_channel_config table
    await db.execute('''
      CREATE TABLE user_channel_config (
        channel_config_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        channel_key TEXT NOT NULL,
        custom_label TEXT,
        custom_channel_type TEXT,
        effective_from TEXT NOT NULL,
        revenue_share_pct $decimalType,
        user_aov $decimalType,
        user_ad_cost_ratio $decimalNullable,
        is_active $boolType DEFAULT 1,
        FOREIGN KEY (user_id) REFERENCES users (user_id),
        FOREIGN KEY (channel_key) REFERENCES sales_channel (channel_key)
      )
    ''');

    // 8. channel_actual_performance table
    await db.execute('''
      CREATE TABLE channel_actual_performance (
        id $idType,
        channel_config_id TEXT NOT NULL,
        record_date TEXT NOT NULL,
        actual_orders $intType,
        actual_ad_spend $decimalNullable,
        period_covers_days $intType,
        created_at $timestampType,
        FOREIGN KEY (channel_config_id) REFERENCES user_channel_config (channel_config_id)
      )
    ''');

    // 9. cmo_suggestion_log table
    await db.execute('''
      CREATE TABLE cmo_suggestion_log (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        rule_id TEXT NOT NULL,
        generated_date TEXT NOT NULL,
        content_snapshot TEXT NOT NULL,
        raw_data_snapshot TEXT NOT NULL,
        status TEXT NOT NULL,
        status_updated_at TEXT,
        FOREIGN KEY (user_id) REFERENCES users (user_id)
      )
    ''');

    // 10. capital_intent table
    await db.execute('''
      CREATE TABLE capital_intent (
        user_id TEXT NOT NULL,
        asset_type TEXT NOT NULL,
        planned_action TEXT NOT NULL,
        updated_at $timestampType,
        PRIMARY KEY (user_id, asset_type),
        FOREIGN KEY (user_id) REFERENCES users (user_id)
      )
    ''');

    // 11. tiktok_shop_connection table
    await db.execute('''
      CREATE TABLE tiktok_shop_connection (
        id TEXT PRIMARY KEY,
        channel_config_id TEXT NOT NULL,
        tiktok_shop_id TEXT NOT NULL,
        access_token TEXT NOT NULL,
        refresh_token TEXT NOT NULL,
        token_expires_at TEXT NOT NULL,
        authorized_at $timestampType,
        last_synced_at TEXT,
        sync_status TEXT NOT NULL,
        FOREIGN KEY (channel_config_id) REFERENCES user_channel_config (channel_config_id)
      )
    ''');

    // Seed default sales channels
    await db.insert('sales_channel', {
      'channel_key': 'tiktok_ads',
      'display_name': 'TikTok Ads',
      'channel_type': 'paid_channel',
      'has_benchmark': 1,
      'is_system_default': 1,
    });
    await db.insert('sales_channel', {
      'channel_key': 'facebook_ads',
      'display_name': 'Facebook Ads',
      'channel_type': 'paid_channel',
      'has_benchmark': 1,
      'is_system_default': 1,
    });
    await db.insert('sales_channel', {
      'channel_key': 'google_ads',
      'display_name': 'Google Ads',
      'channel_type': 'paid_channel',
      'has_benchmark': 1,
      'is_system_default': 1,
    });
    await db.insert('sales_channel', {
      'channel_key': 'shopee',
      'display_name': 'Shopee',
      'channel_type': 'organic_channel',
      'has_benchmark': 0,
      'is_system_default': 1,
    });
    await db.insert('sales_channel', {
      'channel_key': 'custom',
      'display_name': 'Kênh tùy chỉnh',
      'channel_type': 'organic_channel',
      'has_benchmark': 0,
      'is_system_default': 1,
    });

    // 12. fastmoss_category_trend table (TikTok Shop category trends)
    await _createFastmossTable(db);

    // 13. fastmoss_creator_trend table (TikTok creator/video trends)
    await _createFastmossCreatorTable(db);
  }

  Future close() async {
    await closeDatabase();
  }
}
