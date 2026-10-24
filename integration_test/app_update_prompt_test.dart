import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/app_meta.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/services/app_update.dart';
import 'package:blisten/widgets/app_update_prompt.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/checked_hooks.dart';

// Real Android HTTP/storage/rendering with local synthetic Release responses.
// This fixture never creates a public release or changes production endpoints.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late SharedPreferences prefs;
  var requests = 0;
  var completed = 0;
  var status = HttpStatus.ok;
  var version = '9.0.0';
  final requestErrors = <Object>[];
  String? lastError;
  UpdateResult? lastResult;

  setUpAll(
    () => guardedHook('update prompt setUpAll', () async {
      expect(Platform.isAndroid, isTrue);
      prefs = await SharedPreferences.getInstance();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests++;
        debugPrint(
          '[update fixture] HTTP #$requests ${request.method} ${request.uri} status=$status',
        );
        if (request.uri.path != '/release' ||
            request.headers.value('Accept') != 'application/vnd.github+json') {
          requestErrors.add('Unexpected request: ${request.uri}');
        }
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'tag_name': 'v$version',
            'name': 'B听更新测试 $version',
            'draft': false,
            'prerelease': false,
            'body': '本地测试数据：验证自动提醒与手动检查，不对应公开版本。',
            'html_url':
                'https://github.com/AtomHH86/Blisten/releases/tag/v$version',
            'assets': [
              {
                'name': 'Blisten-v$version-universal.apk',
                'browser_download_url':
                    'https://github.com/AtomHH86/Blisten/releases/download/v$version/Blisten-v$version-universal.apk',
              },
            ],
          }),
        );
        await request.response.close();
      });
      if (const bool.fromEnvironment('BLISTEN_CAPTURE_UPDATES')) {
        await binding.convertFlutterSurfaceToImage();
      }
    }),
  );

  setUp(
    () => guardedHook('update prompt setUp', () async {
      requests = 0;
      completed = 0;
      status = HttpStatus.ok;
      version = '9.0.0';
      lastError = null;
      lastResult = null;
      await prefs.remove('blisten_update_last_success_ms');
    }),
  );

  tearDown(
    () => guardedHook('update prompt tearDown', () async {
      expect(requestErrors, isEmpty);
      await prefs.remove('blisten_update_last_success_ms');
    }),
  );

  tearDownAll(
    () => guardedHook('update prompt tearDownAll', () async {
      await server.close(force: true);
    }),
  );

  Future<UpdateResult> check() async {
    debugPrint(
      '[update fixture] check started: lifecycle=${binding.lifecycleState} httpOverride=${HttpOverrides.current.runtimeType}',
    );
    final result = await AppUpdate.check(
      createClient: () {
        final client = Dio();
        client.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              debugPrint('[update fixture] intercept ${options.uri}');
              // This callback can run during tester.pump. Record violations
              // here and assert them in guarded tearDown, outside that guard.
              if (options.uri.toString() !=
                  'https://api.github.com/repos/AtomHH86/Blisten/releases/latest') {
                final message = 'Unexpected update request: ${options.uri}';
                requestErrors.add(message);
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.cancel,
                    error: StateError(message),
                  ),
                );
                return;
              }
              options.path = 'http://127.0.0.1:${server.port}/release';
              handler.next(options);
            },
            onResponse: (response, handler) {
              debugPrint(
                '[update fixture] response status=${response.statusCode} dataType=${response.data.runtimeType}',
              );
              handler.next(response);
            },
            onError: (error, handler) {
              lastError =
                  '${error.type}: ${error.message}; cause=${error.error}';
              debugPrint('[update fixture] transport error $lastError');
              handler.next(error);
            },
          ),
        );
        return client;
      },
    );
    completed++;
    lastResult = result;
    debugPrint(
      '[update fixture] completed=$completed requests=$requests error=${result.error} latest=${result.latestVersion} newer=${result.hasNewer}',
    );
    return result;
  }

  Widget host() => MaterialApp(
    theme: AppTheme.light(),
    home: AppUpdatePrompt(
      checkForUpdate: check,
      child: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => AppUpdatePrompt.checkManually(context),
              child: const Text('检查更新'),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    final watch = Stopwatch()..start();
    while (!ready() && watch.elapsed < const Duration(seconds: 15)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      ready(),
      isTrue,
      reason:
          'Expected update state within 15 seconds; '
          'requests=$requests completed=$completed lastError=$lastError '
          'resultError=${lastResult?.error} latest=${lastResult?.latestVersion} '
          'lifecycle=${binding.lifecycleState}',
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Android real HTTP automatic prompt and manual recheck share the update flow',
    (tester) async {
      await tester.pumpWidget(host());
      await waitFor(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
      );
      expect(requests, 1);
      expect(find.textContaining('最新 9.0.0'), findsOneWidget);
      expect(find.text('下载更新'), findsOneWidget);
      expect(prefs.getInt('blisten_update_last_success_ms'), isNotNull);
      if (const bool.fromEnvironment('BLISTEN_CAPTURE_UPDATES')) {
        // The live Android surface can still contain the previous frame after
        // the widget tree settles. Draw two frames before capturing pixels.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('最新 9.0.0'), findsOneWidget);
        await binding.takeScreenshot('update-automatic-local-fixture');
      }
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查更新'));
      await waitFor(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
      );
      expect(requests, 2);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Android current version stays quiet automatically and confirms latest manually',
    (tester) async {
      version = AppMeta.version;
      await tester.pumpWidget(host());
      await waitFor(
        tester,
        () => prefs.getInt('blisten_update_last_success_ms') != null,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.text('检查更新'));
      await waitFor(
        tester,
        () => find.text('已是最新版本 ${AppMeta.version}').evaluate().isNotEmpty,
      );
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Android failed automatic HTTP check is silent and leaves manual retry available',
    (tester) async {
      status = HttpStatus.serviceUnavailable;
      await tester.pumpWidget(host());
      await waitFor(tester, () => completed == 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(prefs.getInt('blisten_update_last_success_ms'), isNull);
      await tester.tap(find.text('检查更新'));
      await waitFor(
        tester,
        () => find.text('检查更新失败，请稍后重试').evaluate().isNotEmpty,
      );
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
