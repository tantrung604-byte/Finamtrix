import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/deposit_rate_point.dart';
import 'database_helper.dart';
import 'fomo_service.dart';

/// Connects to the WIFEED bank deposit interest rate API,
/// persists records into `deposit_interest_rate`, and exposes group averages.
///
/// WIFEED endpoint: `/du-lieu-vimo/lai-suat/huy-dong-theo-nhom-ngan-hang`
/// Response is a JSON object with a `data` array.
class DepositRateService {
  static final DepositRateService instance = DepositRateService._init();
  DepositRateService._init();

  static const String _source = 'wifeed';
  static const String prefsApiKey = 'wifeed_apikey';
  
  static const String _baseUrl = 'https://wifeed.vn/api/du-lieu-vimo/lai-suat/huy-dong-theo-nhom-ngan-hang';

  /// Commercial-bank (NHTM) groups exposed by the WIFEED group endpoint.
  /// [key] matches the WIFEED JSON suffix `lai_suat_huy_dong_{m}m_{key}`.
  static const List<BankGroupDef> bankGroups = [
    BankGroupDef(
      key: 'sobs',
      groupId: 1001,
      name: 'NHTM Nhà nước',
      banks: 'VCB · BIDV · CTG · Agribank',
    ),
    BankGroupDef(
      key: 'nhom_mbb_acb_tcb',
      groupId: 1002,
      name: 'NHTM CP lớn',
      banks: 'MBB · ACB · Techcombank',
    ),
    BankGroupDef(
      key: 'nhom_nhtmcp_khac',
      groupId: 1003,
      name: 'NHTM CP khác',
      banks: 'VPB · VIB · TPB · SHB…',
    ),
  ];


  Future<String?> _getApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(prefsApiKey)?.trim() ?? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MTQ0MywiZW1haWwiOiJ0YW50cnVuZzYwNEBnbWFpbC5jb20iLCJuYW1lIjoiVsWpIE5ndXnhu4VuIFThuqVuIFRydW5nIiwicGhvbmUiOiIrODQ5MTg3Mjg1OTUiLCJjb21wYW55IjoiT2x5bXBpYSBUcmF2ZWwiLCJyb2xlIjoidXNlciIsImlhdCI6MTc4MjY5MTYzOX0.5p9tCW3qvyrKVPOvK4tompI__Qnime11YIFcb9c1KWo';
    } catch (e) {
      print('DepositRate config error: $e');
      return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MTQ0MywiZW1haWwiOiJ0YW50cnVuZzYwNEBnbWFpbC5jb20iLCJuYW1lIjoiVsWpIE5ndXnhu4VuIFThuqVuIFRydW5nIiwicGhvbmUiOiIrODQ5MTg3Mjg1OTUiLCJjb21wYW55IjoiT2x5bXBpYSBUcmF2ZWwiLCJyb2xlIjoidXNlciIsImlhdCI6MTc4MjY5MTYzOX0.5p9tCW3qvyrKVPOvK4tompI__Qnime11YIFcb9c1KWo';
    }
  }

  /// Fetches deposit-rate records from WIFEED.
  Future<List<DepositRatePoint>> fetchDepositRates() async {
    final apiKey = await _getApiKey();
    final url = '$_baseUrl?page=1&limit=10&apikey=$apiKey';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        print('DepositRate API error ${response.statusCode}: ${response.body}');
        return [];
      }
      return parseResponse(jsonDecode(response.body));
    } catch (e) {
      print('DepositRate fetch exception: $e');
      return [];
    }
  }

  /// Pure parser (no network) - handles WIFEED group-based JSON.
  List<DepositRatePoint> parseResponse(dynamic json) {
    if (json is! Map || json['data'] is! List) return [];
    
    final List data = json['data'];
    final out = <DepositRatePoint>[];
    
    // Standard durations we look for in WIFEED keys
    final durations = [1, 3, 6, 9, 12, 13, 18, 24, 36];

    for (final entry in data) {
      if (entry is! Map) continue;
      final date = entry['ngay'] as String?;
      if (date == null) continue;

      for (final duration in durations) {
        for (final group in bankGroups) {
          final key = 'lai_suat_huy_dong_${duration}m_${group.key}';
          final val = entry[key];
          if (val != null) {
            out.add(DepositRatePoint(
              effectiveDate: date,
              valuePct: (val as num).toDouble(),
              durationMonths: duration,
              organizationId: group.groupId,
              typeName: group.key,
              isIndividual: true,
            ));
          }
        }
      }
    }
    return out;
  }

  /// Fetches and upserts records into `deposit_interest_rate`.
  Future<int> syncDepositRates() async {
    final points = await fetchDepositRates();
    if (points.isEmpty) return 0;

    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (final p in points) {
      batch.insert(
        'deposit_interest_rate',
        {
          'organization_id': p.organizationId,
          'duration_id': null,
          'duration_months': p.durationMonths,
          'type_id': p.typeId,
          'type_name': p.typeName,
          'is_individual': p.isIndividual ? 1 : 0,
          'effective_date': p.effectiveDate,
          'value': p.valuePct,
          'source': _source,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    
    // Refresh FOMO score for rates
    try {
      await FomoService.instance.calculateAndSaveFomoScore('rate');
    } catch (_) {}

    return points.length;
  }

  /// Representative deposit rate (%/năm) for the Macro screen.
  /// Averages the latest available group rates for the requested duration.
  Future<double?> getAverageRate({int durationMonths = 12}) async {
    final db = await DatabaseHelper.instance.database;

    // Look for requested duration.
    final latest = await db.query(
      'deposit_interest_rate',
      columns: ['effective_date'],
      where: 'duration_months = ?',
      whereArgs: [durationMonths],
      orderBy: 'effective_date DESC',
      limit: 1,
    );

    if (latest.isNotEmpty) {
      final date = latest.first['effective_date'];
      final rows = await db.rawQuery(
        'SELECT AVG(value) AS avg_value FROM deposit_interest_rate '
        'WHERE duration_months = ? AND effective_date = ?',
        [durationMonths, date],
      );
      final avg = (rows.first['avg_value'] as num?)?.toDouble();
      if (avg != null) return avg;
    }

    // Fallback: Try 13 months if 12 is missing (WIFEED specific).
    if (durationMonths == 12) {
      final fallback13 = await getAverageRate(durationMonths: 13);
      if (fallback13 != null) return fallback13;
    }

    // Ultimate fallback: any latest stored rate.
    final any = await db.query(
      'deposit_interest_rate',
      columns: ['value'],
      orderBy: 'effective_date DESC',
      limit: 1,
    );
    if (any.isEmpty) return null;
    return (any.first['value'] as num?)?.toDouble();
  }

  /// Latest deposit rate per commercial-bank (NHTM) group for [durationMonths].
  ///
  /// Returns one [BankGroupRate] per group that has data, sorted by rate
  /// (highest first). Falls back from 12 → 13 tháng per WIFEED quirks.
  Future<List<BankGroupRate>> getBankGroupRates({int durationMonths = 12}) async {
    final db = await DatabaseHelper.instance.database;
    final out = <BankGroupRate>[];

    for (final g in bankGroups) {
      final rows = await db.query(
        'deposit_interest_rate',
        columns: ['value', 'effective_date', 'duration_months'],
        where: 'organization_id = ? AND (duration_months = ? OR duration_months = ?)',
        whereArgs: [
          g.groupId,
          durationMonths,
          durationMonths == 12 ? 13 : durationMonths,
        ],
        orderBy: 'effective_date DESC, duration_months ASC',
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final r = rows.first;
      out.add(BankGroupRate(
        groupId: g.groupId,
        name: g.name,
        banks: g.banks,
        durationMonths: (r['duration_months'] as num?)?.toInt() ?? durationMonths,
        ratePct: (r['value'] as num).toDouble(),
        effectiveDate: r['effective_date'] as String,
      ));
    }

    out.sort((a, b) => b.ratePct.compareTo(a.ratePct));
    return out;
  }
}

/// Static definition of a commercial-bank group in the WIFEED group endpoint.
class BankGroupDef {
  final String key;
  final int groupId;
  final String name;
  final String banks;

  const BankGroupDef({
    required this.key,
    required this.groupId,
    required this.name,
    required this.banks,
  });
}
