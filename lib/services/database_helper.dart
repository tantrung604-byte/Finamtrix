import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('finmatrix.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textNullable = 'TEXT';
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
        date TEXT UNIQUE NOT NULL,
        price_buy $decimalType,
        price_sell $decimalType,
        source TEXT NOT NULL,
        fetched_at $timestampType
      )
    ''');

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
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
