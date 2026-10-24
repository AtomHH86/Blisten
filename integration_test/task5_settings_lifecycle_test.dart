// Android integration regression: DeviceService uses Platform.isAndroid, so a
// desktop widget test cannot observe this existing method-channel boundary.
import 'dart:async';

import 'package:blisten/pages/settings_page.dart';
import 'package:blisten/services/auth_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var queries = 0;
  var requests = 0;
  var ignoring = false;
  Completer<bool>? pendingQuery;

  setUp(() async {
    queries = 0;
    requests = 0;
    ignoring = false;
    pendingQuery = null;
    SharedPreferences.setMockInitialValues({});
    await LoginStore.instance.load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('abts/battery'), (call) async {
      if (call.method == 'isIgnoring') {
        queries++;
        return pendingQuery?.future ?? ignoring;
      }
      if (call.method == 'requestIgnore') {
        requests++;
        return null;
      }
      throw PlatformException(code: 'unexpected_method');
    });
  });

  tearDown(() {
    final pending = pendingQuery;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('abts/battery'), null);
  });

  Future<void> showSettings(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: LoginStore.instance,
      child: MaterialApp(theme: AppTheme.light(), home: const SettingsPage()),
    ));
    await tester.pumpAndSettle();
    expect(queries, 1);
    expect(find.textContaining('未开启'), findsOneWidget);
  }

  testWidgets('settings rereads actual battery protection on resumed', (tester) async {
    await showSettings(tester);
    ignoring = true;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(queries, 2);
    expect(find.textContaining('已豁免电池优化'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    await tester.pumpWidget(const SizedBox());
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(queries, 2, reason: 'Disposed settings must unregister its lifecycle observer.');
  });

  testWidgets('late battery query cannot overwrite a newer resumed result', (tester) async {
    await showSettings(tester);
    final older = Completer<bool>();
    pendingQuery = older;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(queries, 2);
    pendingQuery = null;
    ignoring = true;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(queries, 3);
    older.complete(false);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('repeated battery prompt taps submit only once while pending', (tester) async {
    final requested = Completer<void>();
    await showSettings(tester);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('abts/battery'), (call) async {
      if (call.method == 'isIgnoring') return false;
      requests++;
      await requested.future;
      return null;
    });
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(requests, 1);
    requested.complete();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
