// ignore_for_file: invalid_use_of_visible_for_testing_member
// Every credential below is synthetic. HTTP is redirected to loopback only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/network/api_config.dart';
import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/network/cookie_jar.dart';
import 'package:blisten/services/auth_store.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LoopbackApi extends HttpOverrides {
  late final HttpServer server;
  bool isLogin = false;
  bool returnSession = false;
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
      if (returnSession) {
        request.response.headers.add(
          'set-cookie',
          'SESSDATA=${request.uri.path.contains('qrcode') ? 'NEW_SYNTHETIC' : 'STALE_SYNTHETIC'}; Path=/',
        );
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': 0,
          'data': {
            'code': 0,
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
    if (!{
      'www.bilibili.com',
      'api.bilibili.com',
      'passport.bilibili.com',
    }.contains(url.host)) {
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
  String? storedCookie;
  setUp(() {
    storedCookie = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('abts/credentials'), (
          call,
        ) async {
          if (call.method == 'read') return storedCookie;
          if (call.method == 'write') storedCookie = call.arguments as String?;
          return true;
        });
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
    'a stale Set-Cookie response cannot restore a logged out session',
    () async {
      await _withApi((fixture) async {
        fixture.returnSession = true;
        fixture.navEntered = Completer<void>();
        fixture.navRelease = Completer<void>();
        final pending = BiliClient.instance.get(BiliEndpoints.nav);
        await fixture.navEntered!.future;
        await LoginStore.instance.markLoggedOut();
        fixture.navRelease!.complete();
        await pending;
        expect(BiliClient.instance.isLoggedIn, isFalse);
      });
    },
  );

  test('cached profile is not server verification at startup', () async {
    await _withApi((fixture) async {
      expect(LoginStore.instance.isLogin, isFalse);
    });
  });
  test('cookie migration removes legacy only after durable write', () async {
    await _withApi((fixture) async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('bili_cookie'), isFalse);
      expect(storedCookie, contains(_syntheticSession));
      await BiliClient.instance.logout();
      expect(storedCookie, isNull);
    });
  });
  test('migration failure preserves the only durable legacy cookie', () async {
    SharedPreferences.setMockInitialValues({
      'bili_cookie': 'SESSDATA=SYNTHETIC_KEEP',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('abts/credentials'), (
          call,
        ) async {
          if (call.method == 'read') return null;
          throw PlatformException(code: 'storage');
        });
    try {
      await BiliClient.instance.initLocal();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bili_cookie'), 'SESSDATA=SYNTHETIC_KEEP');
  });

  test(
    'offline verification keeps credentials but does not claim login',
    () async {
      await _withApi((fixture) async {
        for (final client in fixture.clients) {
          client.close(force: true);
        }
        await fixture.server.close(force: true);
        await LoginStore.instance.refreshFromNav();
        expect(LoginStore.instance.isLogin, isFalse);
        expect(BiliClient.instance.isLoggedIn, isTrue);
        expect(LoginStore.instance.status, LoginStatus.unverified);
      });
    },
  );
  test(
    'cancelled or replaced login attempt rejects pending response cookies',
    () async {
      await _withApi((fixture) async {
        await BiliClient.instance.logout();
        fixture.returnSession = true;
        fixture.navEntered = Completer<void>();
        fixture.navRelease = Completer<void>();
        final pending = BiliClient.instance.get(BiliEndpoints.nav);
        await fixture.navEntered!.future;
        BiliClient.instance.invalidateSessionRequests();
        fixture.navRelease!.complete();
        await pending;
        expect(BiliClient.instance.isLoggedIn, isFalse);
        expect(storedCookie, isNull);
      });
    },
  );

  test('verified nav and expired nav remain distinct from offline', () async {
    await _withApi((fixture) async {
      fixture.isLogin = true;
      await LoginStore.instance.refreshFromNav();
      expect(LoginStore.instance.status, LoginStatus.verified);
      fixture.isLogin = false;
      await LoginStore.instance.refreshFromNav();
      expect(LoginStore.instance.status, LoginStatus.expired);
      expect(BiliClient.instance.isLoggedIn, isFalse);
    });
  });
  test(
    'successful QR login invalidates older competing response cookies',
    () async {
      await _withApi((fixture) async {
        fixture.returnSession = true;
        fixture.navEntered = Completer<void>();
        fixture.navRelease = Completer<void>();
        final old = BiliClient.instance.get(BiliEndpoints.nav);
        await fixture.navEntered!.future;
        await BiliApi.instance.qrPoll('SYNTHETIC_QR_KEY');
        fixture.navRelease!.complete();
        await old;
        expect(CookieJar.instance.get('SESSDATA'), 'NEW_SYNTHETIC');
      });
    },
  );
  test('guest nav is logged out rather than an expired login', () async {
    await _withApi((fixture) async {
      await LoginStore.instance.markLoggedOut();
      await LoginStore.instance.refreshFromNav();
      expect(LoginStore.instance.status, LoginStatus.loggedOut);
    });
  });
}
