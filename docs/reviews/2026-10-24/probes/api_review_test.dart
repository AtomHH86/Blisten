// Standalone review tests live outside test/ to keep known-failing probes out of daily checks.
// ignore_for_file: invalid_use_of_visible_for_testing_member
// Review-only regression probes. These assert intended behavior and currently
// fail on the reviewed baseline. They are deliberately outside test/.
// Every credential below is synthetic. HTTP is redirected to loopback only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/network/api_config.dart';
import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/network/cookie_jar.dart';
import 'package:blisten/models/up_user.dart';
import 'package:blisten/services/auth_store.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingClient implements BiliClient {
  final calls = <String>[];

  @override
  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? query,
    bool useWbi = false,
    Map<String, String>? headers,
  }) async {
    calls.add(url);
    throw BiliApiException(-1, 'synthetic offline');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoopbackApi extends HttpOverrides {
  late final HttpServer server;
  bool isLogin = false;
  Completer<void>? navEntered;
  Completer<void>? navRelease;
  final requestTimes = <DateTime>[];
  final clients = <HttpClient>[];

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestTimes.add(DateTime.now());
      if (request.uri.path == '/x/web-interface/nav') {
        final entered = navEntered;
        if (entered != null && !entered.isCompleted) entered.complete();
        await navRelease?.future;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': 0,
          'data': {
            'isLogin': isLogin,
            'uname': isLogin ? 'Synthetic review user' : '',
            'face': '',
            'wbi_img': {
              'img_url':
                  'https://example.invalid/0123456789abcdef0123456789abcdef.png',
              'sub_url':
                  'https://example.invalid/fedcba9876543210fedcba9876543210.png',
            },
          },
        }),
      );
      await request.response.close();
    });
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    clients.add(client);
    return _RedirectClient(client, server.port);
  }

  Future<void> close() async {
    final release = navRelease;
    if (release != null && !release.isCompleted) release.complete();
    for (final client in clients) {
      client.close(force: true);
    }
    await server.close(force: true);
  }
}

class _RedirectClient implements HttpClient {
  _RedirectClient(this.delegate, this.port);
  final HttpClient delegate;
  final int port;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    if (!{'www.bilibili.com', 'api.bilibili.com'}.contains(url.host)) {
      throw StateError('Unexpected host in review probe');
    }
    return delegate.openUrl(
      method,
      url.replace(scheme: 'http', host: '127.0.0.1', port: port),
    );
  }

  @override
  Duration? get connectionTimeout => delegate.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => delegate.connectionTimeout = value;
  @override
  Duration get idleTimeout => delegate.idleTimeout;
  @override
  set idleTimeout(Duration value) => delegate.idleTimeout = value;
  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _syntheticSession = 'REVIEW_ONLY_FAKE_SESSION_NOT_A_REAL_CREDENTIAL';

Future<void> _withApi(Future<void> Function(_LoopbackApi api) body) async {
  final fixture = _LoopbackApi();
  await fixture.start();
  try {
    await HttpOverrides.runZoned(() async {
      CookieJar.instance.clear();
      SharedPreferences.setMockInitialValues({
        'bili_cookie': 'SESSDATA=$_syntheticSession',
        'bili_login_user': jsonEncode({
          'login': true,
          'name': 'Synthetic review user',
          'face': '',
        }),
      });
      await BiliClient.instance.initLocal();
      await LoginStore.instance.load();
      await body(fixture);
    }, createHttpClient: fixture.createHttpClient);
  } finally {
    await fixture.close();
    CookieJar.instance.clear();
    SharedPreferences.setMockInitialValues({});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'review: UP loading must preserve an all-sources network failure',
    () async {
      final client = _FailingClient();
      final api = BiliApi(client: client);
      Object? failure;
      try {
        await api.upAudios(UpUser(mid: 42, name: 'Synthetic UP', face: ''));
      } catch (error) {
        failure = error;
      }
      expect(client.calls, hasLength(3));
      expect(
        failure,
        isA<BiliApiException>(),
        reason:
            'Three failed sources must not become successful empty content.',
      );
    },
  );

  test('review: discovery must preserve a first-page network failure', () async {
    final api = BiliApi(client: _FailingClient());
    await expectLater(
      api.rankHotNovel(),
      throwsA(isA<BiliApiException>()),
      reason:
          'Failed initial discovery must offer retry instead of cached empty content.',
    );
  });

  test('review: server-expired login must not stay authenticated', () async {
    await _withApi((fixture) async {
      fixture.isLogin = false;
      await LoginStore.instance.refreshFromNav();
      expect(
        LoginStore.instance.isLogin,
        isFalse,
        reason:
            'The server says logged out; a stored cookie is not proof of validity.',
      );
    });
  });

  test('review: warmup logs must not include a session credential', () async {
    await _withApi((fixture) async {
      final previousPrint = debugPrint;
      final lines = <String>[];
      try {
        debugPrint = (message, {wrapWidth}) {
          if (message != null) lines.add(message);
        };
        await BiliClient.instance.warmup();
      } finally {
        debugPrint = previousPrint;
      }
      expect(
        lines.join('\n'),
        isNot(contains(_syntheticSession)),
        reason: 'No debug or release log should contain authentication values.',
      );
    });
  });

  test('review: a stale nav response must not reverse explicit logout', () async {
    await _withApi((fixture) async {
      fixture.isLogin = true;
      fixture.navEntered = Completer<void>();
      fixture.navRelease = Completer<void>();
      final pendingRefresh = LoginStore.instance.refreshFromNav();
      await fixture.navEntered!.future.timeout(const Duration(seconds: 5));
      await LoginStore.instance.markLoggedOut();
      fixture.navRelease!.complete();
      await pendingRefresh;
      expect(
        LoginStore.instance.isLogin,
        isFalse,
        reason:
            'A response from the previous session must not log the UI back in.',
      );
    });
  });

  test(
    'review: concurrent calls must respect the advertised request gap',
    () async {
      await _withApi((fixture) async {
        await Future.wait(
          List.generate(3, (_) => BiliClient.instance.get(BiliEndpoints.nav)),
        );
        expect(fixture.requestTimes, hasLength(3));
        final sorted = [...fixture.requestTimes]..sort();
        for (var i = 1; i < sorted.length; i++) {
          expect(
            sorted[i].difference(sorted[i - 1]).inMilliseconds,
            greaterThanOrEqualTo(400),
            reason:
                'Concurrent calls need a serialized 450 ms request reservation.',
          );
        }
      });
    },
  );
}
