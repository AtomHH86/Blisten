import 'dart:io';

import 'package:blisten/services/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

const _releaseUrl = 'https://example.invalid/releases/tag/v1.0.1';
const _universalUrl =
    'https://example.invalid/releases/download/v1.0.1/Blisten-v1.0.1-universal.apk';

Map<String, Object?> _asset(String abi, {String? url}) => {
  'name': 'Blisten-v1.0.1-$abi.apk',
  'browser_download_url': url ?? 'https://example.invalid/$abi.apk',
};

Map<String, Object?> _release(List<Map<String, Object?>> assets) => {
  'tag_name': 'v1.0.1',
  'name': 'B听 1.0.1',
  'body': '  修复播放问题  ',
  'html_url': _releaseUrl,
  'assets': assets,
};

void main() {
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
    final result = AppUpdate.parseRelease(_release([
      _asset('arm64-v8a'),
      _asset('armeabi-v7a'),
      _asset('x86_64'),
    ]));

    expect(result.apkUrl, isNull);
    expect(result.htmlUrl, _releaseUrl);
  });

  for (final url in [null, '', '   ']) {
    test('universal APK without a usable URL falls back to release page: $url',
        () {
      final result = AppUpdate.parseRelease(_release([
        {
          'name': 'Blisten-v1.0.1-universal.apk',
          'browser_download_url': ?url,
        },
        _asset('arm64-v8a'),
      ]));

      expect(result.apkUrl, isNull);
      expect(result.htmlUrl, _releaseUrl);
    });
  }

  test('empty universal URL does not hide a later usable universal APK', () {
    final result = AppUpdate.parseRelease(_release([
      _asset('universal', url: ''),
      _asset('arm64-v8a'),
      _asset('universal', url: _universalUrl),
    ]));

    expect(result.apkUrl, _universalUrl);
  });

  test('release metadata is retained when choosing the universal APK', () {
    final result = AppUpdate.parseRelease(_release([
      _asset('universal', url: _universalUrl),
    ]));

    expect(result.configured, isTrue);
    expect(result.error, isNull);
    expect(result.latestVersion, '1.0.1');
    expect(result.latestName, 'B听 1.0.1');
    expect(result.changelog, '修复播放问题');
  });

  test('missing release URL falls back to the independent Blisten repository', () {
    final result = AppUpdate.parseRelease({'tag_name': 'v1.0.1', 'assets': []});

    expect(result.htmlUrl, 'https://github.com/AtomHH86/Blisten/releases/latest');
    expect(result.htmlUrl, isNot(contains('fengqiao57/abts')));
  });

  test('an explicit release fallback is retained when metadata omits its URL', () {
    final result = AppUpdate.parseRelease(
      {'tag_name': 'v1.0.1', 'assets': []},
      fallbackUrl: _releaseUrl,
    );

    expect(result.htmlUrl, _releaseUrl);
  });

  for (final (owner, repo) in [
    ('', ''),
    ('', AppUpdate.githubRepo),
    (AppUpdate.githubOwner, ''),
  ]) {
    test('incomplete updater configuration never accesses the network: $owner/$repo',
        () async {
      var clientsCreated = 0;
      final result = await HttpOverrides.runZoned(
        () => AppUpdate.check(owner: owner, repo: repo),
        createHttpClient: (context) {
          clientsCreated++;
          throw StateError('Unconfigured updates must not access the network');
        },
      );

      expect(clientsCreated, 0);
      expect(result.configured, isFalse);
      expect(result.hasNewer, isFalse);
      expect(result.error, isNull);
      expect(result.apkUrl, isNull);
    });
  }
}
