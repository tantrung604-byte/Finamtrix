import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/main_navigation.dart';
import 'services/database_helper.dart';
import 'services/database_seed_service.dart';
import 'services/supabase_service.dart';
import 'services/background_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Show the real error on-screen (even in release) instead of a blank grey box,
  // so build-time exceptions are diagnosable on a physical device.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF0A0E1A),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '⚠️ Lỗi hiển thị màn hình',
                style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              SelectableText(
                details.exceptionAsString(),
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              SelectableText(
                details.stack?.toString() ?? 'no stack',
                style: const TextStyle(color: Color(0xFF9AA4B2), fontSize: 10, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  };

  await DatabaseHelper.ensureInitialized();
  await SupabaseService.instance.initialize();
  await DatabaseSeedService.ensureMvpData();
  await BackgroundSyncService.instance.initialize();

  runApp(const FinMatrixApp());
}

class FinMatrixApp extends StatelessWidget {
  const FinMatrixApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinMatrix',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      // Clamp the system text scale so large accessibility font settings
      // can't break the dense, data-heavy layouts.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clamped = mq.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.2,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: clamped),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const MainNavigation(),
    );
  }
}
