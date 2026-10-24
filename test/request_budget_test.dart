import 'dart:convert';
import 'package:blisten/core/network/api_config.dart';
import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/network/request_scheduler.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Clock {
  Duration time = Duration.zero;
  bool oversleep = false;
  late final scheduler = RequestScheduler(now: () => time, delay: (duration) async {
    await Future<void>.delayed(Duration.zero);
    time += oversleep ? const Duration(seconds: 1) : duration;
    oversleep = false;
  });
}

BiliClient _client(_Clock clock, Object Function(RequestOptions) response,
    {List<Duration>? sends}) {
  final dio = Dio()..httpClientAdapter = _Adapter((options) {
    sends?.add(clock.time);
    return response(options);
  });
  return BiliClient.forTesting(dio, clock.scheduler);
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.response);
  final Object Function(RequestOptions) response;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async => ResponseBody.fromString(
        jsonEncode(response(options)), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('abts/credentials'), (call) async => call.method == 'write' ? true : null);
  });

  for (final oversleep in [false, true]) {
    test('concurrent sends have distinct grants, oversleep=$oversleep', () async {
      final clock = _Clock()..oversleep = oversleep;
      final sends = <Duration>[];
      final client = _client(clock, (_) => {'code': 0}, sends: sends);
      await Future.wait(List.generate(3, (_) => client.get('https://example.invalid/read')));
      expect(sends.map((t) => t.inMilliseconds), oversleep ? [0, 1000, 1450] : [0, 450, 900]);
    });
  }

  test('risk retries are bounded to four actual sends', () async {
    final sends = <Duration>[];
    final client = _client(_Clock(), (_) => {'code': -412}, sends: sends);
    await expectLater(client.get('https://example.invalid/read'), throwsA(isA<BiliApiException>()));
    expect(sends, hasLength(4));
  });

  test('logical fallback shares maximum twelve sends across endpoints', () async {
    final clock = _Clock();
    var count = 0;
    final client = _client(clock, (_) { count++; return {'code': -412}; });
    await BiliClient.withRequestBudget(() async {
      for (var i = 0; i < 5; i++) {
        try { await client.get('https://example.invalid/source$i'); } on BiliApiException { /* try another source */ }
      }
    });
    expect(count, 12);
    expect(clock.time, lessThan(const Duration(seconds: 45)));
  });

  test('elapsed operation deadline prevents fallback from obtaining a new budget', () async {
    final clock = _Clock();
    var count = 0;
    final client = _client(clock, (_) { count++; return {'code': 0}; });
    await BiliClient.withRequestBudget(() async {
      await client.get('https://example.invalid/first');
      clock.time += const Duration(seconds: 46);
      await expectLater(client.get('https://example.invalid/fallback'), throwsA(isA<BiliApiException>()));
    });
    expect(count, 1);
  });

  testWidgets('deadline does not cancel reusable caller token', (tester) async {
    final token = CancelToken();
    final clock = _Clock();
    final budget = RequestBudget(clock.scheduler, cancelToken: token,
        timeout: const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 21));
    expect(budget.token.isCancelled, isTrue);
    expect(token.isCancelled, isFalse);
    budget.close();
    final next = RequestBudget(clock.scheduler, cancelToken: token);
    expect(next.check, returnsNormally);
    next.close();
  });

  test('cancelled queued request does not send or prevent later work', () async {
    final clock = _Clock();
    var count = 0;
    final client = _client(clock, (_) { count++; return {'code': 0}; });
    final token = CancelToken()..cancel();
    await expectLater(client.get('https://example.invalid/cancelled', cancelToken: token),
        throwsA(isA<DioException>()));
    await client.get('https://example.invalid/next');
    expect(count, 1);
  });

  test('guest nav with WBI keys permits signed search but not authenticated nav', () async {
    final calls = <RequestOptions>[];
    final client = _client(_Clock(), (request) {
      calls.add(request);
      if (request.path.startsWith(BiliEndpoints.nav)) {
        return {'code': -101, 'data': {'isLogin': false, 'wbi_img': {
          'img_url': 'https://example.invalid/0123456789abcdef0123456789abcdef.png',
          'sub_url': 'https://example.invalid/fedcba9876543210fedcba9876543210.png',
        }}};
      }
      return {'code': 0, 'data': {'result': [], 'numResults': 0}};
    });
    final api = BiliApi(client: client);
    expect(await api.search('song', mode: ContentMode.music), isEmpty);
    expect(Uri.parse(calls.last.path).queryParameters['w_rid'], isNotEmpty);
    await expectLater(api.currentUser(), throwsA(isA<BiliApiException>().having((e) => e.code, 'code', -101)));
  });

  test('malformed nav is transient rather than confirmed logout', () async {
    final api = BiliApi(client: _client(_Clock(), (_) => {'code': 0}));
    await expectLater(api.currentUser(), throwsA(isA<BiliApiException>().having((e) => e.code, 'code', -1)));
  });
}
