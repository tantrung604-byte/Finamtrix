// Probes FastMoss topSelling VN category_id 1..30 and prints id -> L1 name.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final secret = Platform.environment['FASTMOSS_APP_SECRET'] ?? '';
  if (secret.isEmpty) {
    stdout.writeln('Set FASTMOSS_APP_SECRET first.');
    return;
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final d = DateTime.now().subtract(const Duration(days: 3));
  String pad(int n) => n.toString().padLeft(2, '0');
  final day = '${d.year}-${pad(d.month)}-${pad(d.day)}';

  for (var id = 1; id <= 30; id++) {
    try {
      final req = await client
          .postUrl(Uri.parse('https://openapi.fastmoss.com/product/v1/rank/topSelling'));
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Authorization', 'Bearer $secret');
      req.headers.set('access-key', 'finmatrix');
      req.add(utf8.encode(jsonEncode({
        'filter': {
          'region': 'VN',
          'category_id': id,
          'date_info': {'type': 'day', 'value': day},
        },
        'orderby': [
          {'field': 'gmv', 'order': 'desc'}
        ],
        'page': 1,
        'pagesize': 1,
      })));
      final resp = await req.close().timeout(const Duration(seconds: 30));
      final text = await resp.transform(utf8.decoder).join();
      final m = RegExp(r'"l1":\{"id":(\d+),"name":"([^"]+)"').firstMatch(text);
      if (m != null) {
        stdout.writeln('id=$id -> ${m.group(2)}');
      } else {
        final code = RegExp(r'"code":(-?\d+)').firstMatch(text)?.group(1);
        stdout.writeln('id=$id -> (empty, code=$code)');
      }
    } catch (e) {
      stdout.writeln('id=$id -> ERROR $e');
    }
    await Future.delayed(const Duration(milliseconds: 800));
  }
  client.close(force: true);
}

