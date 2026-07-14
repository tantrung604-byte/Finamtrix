// Standalone FastMoss Open API connectivity checker.
//
// Usage (PowerShell), pass your real Client Secret + Name:
//   dart run tool/check_fastmoss.dart --secret=YOUR_CLIENT_SECRET --name=finmatrix
//
// Without a secret it still checks that the FastMoss host is REACHABLE
// (network/DNS/TLS) and prints how the server responds to an unauthenticated
// request — so you can tell "connected but unauthorized" apart from "no
// network / wrong endpoint".
import 'dart:convert';
import 'dart:io';

const String openApiBase = 'https://openapi.fastmoss.com';
const String defaultPath = '/product/v1/rank/topSelling';

String? _arg(List<String> args, String key) {
  for (final a in args) {
    if (a.startsWith('--$key=')) return a.substring(key.length + 3);
  }
  return null;
}

Future<void> main(List<String> args) async {
  // Secret resolution order (most secure first):
  //   1. --secret=... CLI arg
  //   2. FASTMOSS_APP_SECRET environment variable
  //   3. a local, git-ignored file: tool/.fastmoss_secret
  var secret = _arg(args, 'secret') ?? '';
  if (secret.isEmpty) {
    secret = Platform.environment['FASTMOSS_APP_SECRET'] ?? '';
  }
  if (secret.isEmpty) {
    final f = File('tool/.fastmoss_secret');
    if (f.existsSync()) secret = f.readAsStringSync().trim();
  }
  final name = _arg(args, 'name') ??
      Platform.environment['FASTMOSS_APP_ID'] ??
      'finmatrix';
  final region = _arg(args, 'region') ?? 'VN';
  final path = _arg(args, 'path') ?? defaultPath;
  final orderField = _arg(args, 'order') ?? 'units_sold';
  // date_info: default a recent past DAY (data usually lags 1-3 days).
  final dateType = _arg(args, 'datetype') ?? 'day';
  final d = DateTime.now().subtract(const Duration(days: 3));
  String isoWeek() {
    final thursday = d.add(Duration(days: 3 - ((d.weekday + 6) % 7)));
    final firstThu = DateTime(thursday.year, 1, 4);
    final week =
        1 + (thursday.difference(firstThu).inDays / 7).round();
    return '${thursday.year}-${week.toString().padLeft(2, '0')}';
  }

  String pad(int n) => n.toString().padLeft(2, '0');
  final dateValue = _arg(args, 'date') ??
      (dateType == 'month'
          ? '${d.year}-${pad(d.month)}'
          : dateType == 'week'
              ? isoWeek()
              : '${d.year}-${pad(d.month)}-${pad(d.day)}');

  final body = jsonEncode({
    'filter': {
      'region': region,
      if (_arg(args, 'category') != null)
        'category_id': int.parse(_arg(args, 'category')!),
      'date_info': {'type': dateType, 'value': dateValue},
    },
    'orderby': [
      {'field': orderField, 'order': 'desc'}
    ],
    'page': 1,
    'pagesize': 3,
  });

  final headers = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (secret.isNotEmpty) 'Authorization': 'Bearer $secret',
    if (secret.isNotEmpty) 'access-key': name,
  };

  stdout.writeln('== FastMoss connectivity check ==');
  stdout.writeln('Endpoint : POST $openApiBase$path');
  stdout.writeln('Region   : $region   Name: $name');
  stdout.writeln('date_info: {type: $dateType, value: $dateValue}   order: $orderField');
  stdout.writeln('Auth     : ${secret.isEmpty ? "NONE (reachability only)" : "Bearer <secret> + access-key"}');
  stdout.writeln('');

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 60);
  try {
    final uri = Uri.parse('$openApiBase$path');
    final req = await client.postUrl(uri);
    headers.forEach(req.headers.set);
    req.add(utf8.encode(body));
    final resp = await req.close().timeout(const Duration(seconds: 60));
    final text = await resp.transform(utf8.decoder).join();

    stdout.writeln('✅ REACHABLE — HTTP ${resp.statusCode}');
    final preview = text.length > 600 ? '${text.substring(0, 600)}…' : text;
    stdout.writeln('Response body:');
    stdout.writeln(preview);
    stdout.writeln('');

    // Interpret the result.
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {}
    final code = decoded is Map ? decoded['code'] : null;

    if (resp.statusCode == 200 && (code == 0 || code == null)) {
      stdout.writeln('🎉 KẾT NỐI THÀNH CÔNG — FastMoss trả dữ liệu hợp lệ.');
    } else if (code == 1002 &&
        text.contains('invalid client_secret')) {
      stdout.writeln('🔑 Client "$name" ĐƯỢC NHẬN DIỆN, nhưng Client Secret SAI. '
          'Header đúng rồi — chỉ cần dán Client Secret THẬT (đầy đủ).');
    } else if (code == 1002) {
      stdout.writeln('🔌 Server chưa nhận diện client (thiếu secret hoặc sai '
          'Name). Truyền --secret=... hoặc đặt FASTMOSS_APP_SECRET.');
    } else if (resp.statusCode == 401 || resp.statusCode == 403 || code == 401) {
      stdout.writeln('🔌 Server REACHABLE nhưng CHƯA XÁC THỰC (sai/thiếu secret '
          'hoặc sai tên header). Mạng OK, chỉ cần credentials đúng.');
    } else {
      stdout.writeln('⚠️ Server phản hồi nhưng khác 200/0 — xem code/msg ở trên '
          'để biết cần chỉnh gì (region, date_info, header...).');
    }
  } on SocketException catch (e) {
    stdout.writeln('❌ KHÔNG kết nối được (mạng/DNS): ${e.message}');
  } on HandshakeException catch (e) {
    stdout.writeln('❌ Lỗi TLS/SSL khi bắt tay: ${e.message}');
  } catch (e) {
    stdout.writeln('❌ Lỗi khác: $e');
  } finally {
    client.close(force: true);
  }
}

