// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

// Basic smoke test: verifies the full app boots and renders its shell.
//
// The app renders all five screens at once via an IndexedStack and several of
// them load data asynchronously from SQLite, so the test initializes an
// in-memory database and uses a large surface to lay everything out without
// overflow before asserting on the brand shell.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finmatrix_flutter/main.dart';
import 'package:finmatrix_flutter/services/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // ProfileScreen reads config via SharedPreferences in initState; provide a
    // mock store so it doesn't throw MissingPluginException in the test host.
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // Open an empty in-memory DB (schema only). We intentionally skip seeding so
    // the AI CMO rule engine produces no suggestions and triggers no network
    // (Ollama/Apify) calls that would leave timers pending in the test.
    await DatabaseHelper.openForTesting();
  });

  testWidgets('FinMatrix app renders successfully', (WidgetTester tester) async {
    // Use a tall surface so the off-stage screens in the IndexedStack lay out
    // without triggering RenderFlex overflow during the test.
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Let the screens' real SQLite (FFI) loads complete inside runAsync so no
    // timers remain pending at teardown. The loaders are guarded with `mounted`
    // checks, so they apply state safely while the tree is alive.
    await tester.runAsync(() async {
      await tester.pumpWidget(const FinMatrixApp());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(find.text('FINMATRIX'), findsOneWidget);
    expect(find.text('Trang chủ'), findsOneWidget);
  });
}
