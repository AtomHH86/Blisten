import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:blisten/services/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

const _releaseUrl = 'https://github.com/AtomHH86/Blisten/releases/tag/v1.0.1';
const _universalUrl =
    'https://github.com/AtomHH86/Blisten/releases/download/v1.0.1/Blisten-v1.0.1-universal.apk';

Map<String, Object?> _asset(String abi, {String? url}) => {
  'name': 'Blisten-v1.0.1-$abi.apk',
  'browser_download_url':
      url ??
      'https://github.com/AtomHH86/Blisten/releases/download/v1.0.1/Blisten-v1.0.1-$abi.apk',
};

Map<String, Object?> _release(List<Map<String, Object?>> assets) => {
  'tag_name': 'v1.0.1',
  'name': 'B听 1.0.1',
  'body': '  修复播放问题  ',
  'html_url': _releaseUrl,
  'assets': assets,
};

class _ReleaseAdapter implements HttpClientAdapter {
  _ReleaseAdapter(this.body, {this.fail = false});
  final Object body;
  final bool fail;
  bool closed = false;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    if (fail) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

// A stalled transport never resolves or supplies an adapter-level timeout.
// The updater must enforce its own deadline and force-close this connection.
class _StalledAdapter implements HttpClientAdapter {
  final pending = Completer<ResponseBody>();
  bool started = false;
  bool? forceClosed;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    started = true;
    return pending.future;
  }

  @override
  void close({bool force = false}) {
    forceClosed = force;
  }
}

void main() {
  testWidgets('stalled transport is bounded by the real 15 second deadline', (
    tester,
  ) async {
    final adapter = _StalledAdapter();
    UpdateResult? result;
    unawaited(
      AppUpdate.check(
        createClient: () => Dio()..httpClientAdapter = adapter,
      ).then((value) {
        result = value;
      }),
    );
    // Dio starts its interceptor chain with Future(), a zero-delay event.
    // pump() only flushes microtasks; elapse zero to dispatch that event without
    // consuming any of the 15-second deadline.
    await tester.pump(Duration.zero);
    expect(adapter.started, isTrue);
    await tester.pump(const Duration(seconds: 14, milliseconds: 999));
    expect(
      result,
      isNull,
      reason: 'No premature timeout before the overall deadline',
    );
    expect(adapter.forceClosed, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      result,
      isNotNull,
      reason: 'The updater must finish without transport cooperation',
    );
    expect(result!.error, isNotNull);
    expect(result!.hasNewer, isFalse);
    expect(adapter.forceClosed, isTrue);
  });

  for (final sample in [
    ('1.0.0', '1.1.0', true),
    ('1.1.0', '1.1.0', false),
    ('1.1.0', '1.0.9', false),
    ('1.9.0', '1.10.0', true),
    ('1.1.0', 'v2.0.0', true),
    ('1.1.0', '1.1.0-beta.1', false),
    ('invalid', '9.0.0', false),
  ]) {
    test('stable release comparison ${sample.$1} to ${sample.$2}', () {
      final result = UpdateResult(configured: true, latestVersion: sample.$2);
      expect(result.isNewerThan(sample.$1), sample.$3);
    });
  }

  test('real Dio request parses release and releases its client', () async {
    final adapter = _ReleaseAdapter(
      _release([_asset('universal', url: _universalUrl)]),
    );
    final result = await AppUpdate.check(
      createClient: () => Dio()..httpClientAdapter = adapter,
    );
    expect(result.apkUrl, _universalUrl);
    expect(
      adapter.request!.uri.toString(),
      'https://api.github.com/repos/AtomHH86/Blisten/releases/latest',
    );
    expect(adapter.request!.headers['Accept'], 'application/vnd.github+json');
    expect(adapter.request!.connectTimeout, const Duration(seconds: 10));
    expect(adapter.request!.receiveTimeout, const Duration(seconds: 10));
    expect(adapter.closed, isTrue);
  });

  test(
    'request timeout returns a retryable result and closes the client',
    () async {
      final adapter = _ReleaseAdapter({}, fail: true);
      final result = await AppUpdate.check(
        createClient: () => Dio()..httpClientAdapter = adapter,
      );
      expect(result.error, isNotNull);
      expect(result.hasNewer, isFalse);
      expect(adapter.closed, isTrue);
    },
  );

  test(
    'custom repository request keeps fallback and downloads inside that repository',
    () async {
      final adapter = _ReleaseAdapter({
        'tag_name': 'v1.1.0',
        'assets': [
          {
            'name': 'Blisten-v1.1.0-universal.apk',
            'browser_download_url':
                'https://github.com/example/Fork/releases/download/v1.1.0/Blisten-v1.1.0-universal.apk',
          },
        ],
      });
      final result = await AppUpdate.check(
        owner: 'example',
        repo: 'Fork',
        createClient: () => Dio()..httpClientAdapter = adapter,
      );
      expect(result.htmlUrl, 'https://github.com/example/Fork/releases/latest');
      expect(result.apkUrl, contains('/example/Fork/'));
    },
  );

  for (final tag in [
    'v9.0.0-beta.1',
    'v9.0.0+2',
    'release-9.0.0',
    '9.0',
    '',
    'v01.2.3',
  ]) {
    test('invalid or non-stable release never offers an update: $tag', () {
      final result = AppUpdate.parseRelease({..._release([]), 'tag_name': tag});
      expect(result.hasNewer, isFalse);
      expect(result.error, isNotNull);
    });
  }

  for (final field in ['draft', 'prerelease']) {
    test('$field release is not offered as an update', () {
      final result = AppUpdate.parseRelease({
        ..._release([_asset('universal', url: _universalUrl)]),
        'tag_name': 'v9.0.0',
        field: true,
      });
      expect(result.hasNewer, isFalse);
      expect(result.apkUrl, isNull);
      expect(result.error, isNotNull);
    });
  }

  for (final url in [
    'http://github.com/AtomHH86/Blisten/releases/download/v1.0.1/Blisten-v1.0.1-universal.apk',
    'https://example.invalid/Blisten-v1.0.1-universal.apk',
    'https://github.com/other/Blisten/releases/download/v1.0.1/Blisten-v1.0.1-universal.apk',
    'https://user@github.com/AtomHH86/Blisten/releases/download/v1.0.1/Blisten-v1.0.1-universal.apk',
    'intent://universal.apk',
  ]) {
    test('untrusted asset cannot become the download action: $url', () {
      final result = AppUpdate.parseRelease(
        _release([_asset('universal', url: url)]),
      );
      expect(result.apkUrl, isNull);
      expect(result.htmlUrl, _releaseUrl);
    });
  }

  test('untrusted release URL falls back to the configured repository', () {
    final result = AppUpdate.parseRelease({
      ..._release([]),
      'html_url': 'intent://other-app',
    });
    expect(
      result.htmlUrl,
      'https://github.com/AtomHH86/Blisten/releases/latest',
    );
  });

  for (var universalIndex = 0; universalIndex < 4; universalIndex++) {
    test('four APKs choose universal at asset index $universalIndex', () {
      final assets = [
        _asset('arm64-v8a'),
        _asset('armeabi-v7a'),
        _asset('x86_64'),
      ]..insert(universalIndex, _asset('universal', url: _universalUrl));

      final result = AppUpdate.parseRelease(_release(assets));

      expect(result.apkUrl, _universalUrl);
      expect(result.htmlUrl, _releaseUrl);
    });
  }

  test('ABI-specific APKs leave the release page as the download target', () {
    final result = AppUpdate.parseRelease(
      _release([_asset('arm64-v8a'), _asset('armeabi-v7a'), _asset('x86_64')]),
    );

    expect(result.apkUrl, isNull);
    expect(result.htmlUrl, _releaseUrl);
  });

  for (final url in [null, '', '   ']) {
    test(
      'universal APK without a usable URL falls back to release page: $url',
      () {
        final result = AppUpdate.parseRelease(
          _release([
            {
              'name': 'Blisten-v1.0.1-universal.apk',
              'browser_download_url': ?url,
            },
            _asset('arm64-v8a'),
          ]),
        );

        expect(result.apkUrl, isNull);
        expect(result.htmlUrl, _releaseUrl);
      },
    );
  }

  test('empty universal URL does not hide a later usable universal APK', () {
    final result = AppUpdate.parseRelease(
      _release([
        _asset('universal', url: ''),
        _asset('arm64-v8a'),
        _asset('universal', url: _universalUrl),
      ]),
    );

    expect(result.apkUrl, _universalUrl);
  });

  test('release metadata is retained when choosing the universal APK', () {
    final result = AppUpdate.parseRelease(
      _release([_asset('universal', url: _universalUrl)]),
    );

    expect(result.configured, isTrue);
    expect(result.error, isNull);
    expect(result.latestVersion, '1.0.1');
    expect(result.latestName, 'B听 1.0.1');
    expect(result.changelog, '修复播放问题');
  });

  test(
    'missing release URL falls back to the independent Blisten repository',
    () {
      final result = AppUpdate.parseRelease({
        'tag_name': 'v1.0.1',
        'assets': [],
      });

      expect(
        result.htmlUrl,
        'https://github.com/AtomHH86/Blisten/releases/latest',
      );
      expect(result.htmlUrl, isNot(contains('fengqiao57/abts')));
    },
  );

  test(
    'an explicit release fallback is retained when metadata omits its URL',
    () {
      final result = AppUpdate.parseRelease({
        'tag_name': 'v1.0.1',
        'assets': [],
      }, fallbackUrl: _releaseUrl);

      expect(result.htmlUrl, _releaseUrl);
    },
  );

  for (final (owner, repo) in [
    ('', ''),
    ('', AppUpdate.githubRepo),
    (AppUpdate.githubOwner, ''),
  ]) {
    test(
      'incomplete updater configuration never accesses the network: $owner/$repo',
      () async {
        var clientsCreated = 0;
        final result = await HttpOverrides.runZoned(
          () => AppUpdate.check(owner: owner, repo: repo),
          createHttpClient: (context) {
            clientsCreated++;
            throw StateError(
              'Unconfigured updates must not access the network',
            );
          },
        );

        expect(clientsCreated, 0);
        expect(result.configured, isFalse);
        expect(result.hasNewer, isFalse);
        expect(result.error, isNull);
        expect(result.apkUrl, isNull);
      },
    );
  }
}
