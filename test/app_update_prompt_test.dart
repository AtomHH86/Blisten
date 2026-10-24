import 'dart:async';

import 'package:blisten/core/app_meta.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/services/app_update.dart';
import 'package:blisten/widgets/app_update_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _url =
    'https://github.com/AtomHH86/Blisten/releases/download/v9.0.0/Blisten-v9.0.0-universal.apk';
const _newer = UpdateResult(
  configured: true,
  latestVersion: '9.0.0',
  latestName: 'B听测试新版本',
  changelog: '仅供本地测试的发布信息，不存在对应公开 Release。',
  apkUrl: _url,
);
final _now = DateTime.utc(2026, 10, 24, 12);

Widget _host(
  Future<UpdateResult> Function() checker, {
  DateTime? now,
  Future<bool> Function(String)? openUrl,
  ThemeMode mode = ThemeMode.light,
  double scale = 1,
}) => MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: mode,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: AppUpdatePrompt(
    checkForUpdate: checker,
    now: () => now ?? _now,
    openUrl: openUrl,
    child: KeyedSubtree(
      key: ValueKey(mode),
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Column(
              children: [
                const Text('首页已可使用'),
                TextButton(
                  onPressed: () => AppUpdatePrompt.checkManually(context),
                  child: const Text('检查更新'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('其他页面')),
                    ),
                  ),
                  child: const Text('打开其他页面'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'automatic check does not block home and theme rebuild never repeats the prompt',
    (tester) async {
      final pending = Completer<UpdateResult>();
      var checks = 0;
      Future<UpdateResult> check() {
        checks++;
        return pending.future;
      }

      await tester.pumpWidget(_host(check));
      await tester.pump();
      expect(find.text('首页已可使用'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      pending.complete(_newer);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('下载更新'), findsOneWidget);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(check, mode: ThemeMode.dark));
      await tester.pumpAndSettle();
      expect(checks, 1);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'cold start one minute after a successful check prompts for a new release',
    (tester) async {
      var checks = 0;
      var available = const UpdateResult(
        configured: true,
        latestVersion: AppMeta.version,
      );
      Future<UpdateResult> check() async {
        checks++;
        return available;
      }

      await tester.pumpWidget(_host(check));
      await tester.pumpAndSettle();
      expect(checks, 1);
      expect(find.byType(AlertDialog), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('blisten_update_last_success_ms'),
        _now.millisecondsSinceEpoch,
      );
      await tester.pumpWidget(const SizedBox());
      available = _newer;
      await tester.pumpWidget(
        _host(check, now: _now.add(const Duration(minutes: 1))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('最新 9.0.0'), findsOneWidget);
      expect(checks, 2);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      available = const UpdateResult(
        configured: true,
        latestVersion: AppMeta.version,
      );
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(checks, 3);
      expect(find.text('已是最新版本 ${AppMeta.version}'), findsOneWidget);
    },
  );

  testWidgets(
    'automatic failure is silent and manual retry coalesces rapid clicks',
    (tester) async {
      var checks = 0;
      final retry = Completer<UpdateResult>();
      Future<UpdateResult> check() async {
        checks++;
        if (checks == 1) {
          return const UpdateResult(configured: true, error: '检查更新失败，请稍后重试');
        }
        return retry.future;
      }

      await tester.pumpWidget(_host(check));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      expect(find.text('正在检查更新…'), findsOneWidget);
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      expect(checks, 2);
      retry.complete(
        const UpdateResult(configured: true, error: '检查更新失败，请稍后重试'),
      );
      await tester.pumpAndSettle();
      expect(find.text('检查更新失败，请稍后重试'), findsOneWidget);
      expect(find.text('正在检查更新…'), findsNothing);
    },
  );

  testWidgets(
    'manual and automatic overlap produces one request and one update dialog',
    (tester) async {
      final pending = Completer<UpdateResult>();
      var checks = 0;
      await tester.pumpWidget(
        _host(() {
          checks++;
          return pending.future;
        }),
      );
      await tester.pump();
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      pending.complete(_newer);
      await tester.pumpAndSettle();
      expect(checks, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('正在检查更新…'), findsNothing);
    },
  );

  testWidgets(
    'background result waits until foreground before showing update',
    (tester) async {
      final pending = Completer<UpdateResult>();
      await tester.pumpWidget(_host(() => pending.future));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(_newer);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets('automatic update waits until the home route becomes current', (
    tester,
  ) async {
    final pending = Completer<UpdateResult>();
    await tester.pumpWidget(_host(() => pending.future));
    await tester.pump();
    await tester.tap(find.text('打开其他页面'));
    await tester.pumpAndSettle();
    pending.complete(_newer);
    await tester.pumpAndSettle();
    expect(find.text('其他页面'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'update dialog remains usable on small screen and large text: $theme',
      (tester) async {
        tester.view.physicalSize = const Size(640, 960);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _host(() async => _newer, mode: theme, scale: 2),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('下载更新').hitTestable(), findsOneWidget);
        await tester.tap(find.text('稍后'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }

  testWidgets(
    'download opens the selected universal APK and failed opening copies it',
    (tester) async {
      String? opened;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        _host(
          () async => _newer,
          openUrl: (url) async {
            opened = url;
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      expect(opened, _url);
      expect(copied, _url);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('下载链接已复制'), findsOneWidget);
    },
  );
}
