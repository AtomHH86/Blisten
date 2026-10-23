import 'dart:typed_data';

import 'package:abts/services/bili_resource.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class RedirectAdapter implements HttpClientAdapter {
  final requests = <Uri>[];
  final Map<String, String> locations;
  RedirectAdapter(this.locations);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    final location = locations[options.uri.toString()];
    return ResponseBody.fromString(
      '',
      location == null ? 200 : 302,
      headers: location == null
          ? {}
          : {
              'location': [location],
            },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('bare BV resolves locally', () async {
    final result = await BiliResourceResolver().resolve(' BV1xx411c7mD ');
    expect(result.bvid, 'BV1xx411c7mD');
    expect(result.page, 1);
    expect(result.hasExplicitPage, isFalse);
  });

  test('shared video link keeps its explicit part number', () async {
    final result = await BiliResourceResolver().resolve(
      '【演唱会】 https://www.bilibili.com/video/BV1xx411c7mD/?p=3&share_source=copy_web。',
    );
    expect(result.bvid, 'BV1xx411c7mD');
    expect(result.page, 3);
    expect(result.hasExplicitPage, isTrue);
  });

  test(
    'mobile links work and invalid part numbers default to first part',
    () async {
      final result = await BiliResourceResolver().resolve(
        'https://m.bilibili.com/video/BV1xx411c7mD?p=-1',
      );
      expect(result.page, 1);
      expect(result.hasExplicitPage, isFalse);
    },
  );

  test(
    'an explicit first part overrides saved resume while a plain link does not',
    () async {
      final resolver = BiliResourceResolver();
      final plain = await resolver.resolve(
        'https://www.bilibili.com/video/BV1xx411c7mD',
      );
      final first = await resolver.resolve(
        'https://www.bilibili.com/video/BV1xx411c7mD?p=1',
      );
      expect(plain.hasExplicitPage, isFalse);
      expect(first.hasExplicitPage, isTrue);
      expect(first.page, 1);
    },
  );

  test('short link follows a trusted redirect and keeps part number', () async {
    final adapter = RedirectAdapter({
      'https://b23.tv/abc123':
          'https://www.bilibili.com/video/BV1xx411c7mD?p=2',
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final result = await BiliResourceResolver(
      dio: dio,
    ).resolve('分享 https://b23.tv/abc123');
    expect(result.bvid, 'BV1xx411c7mD');
    expect(result.page, 2);
    expect(adapter.requests.map((u) => u.host), ['b23.tv']);
  });

  test('untrusted links are rejected before network access', () async {
    final adapter = RedirectAdapter({});
    final resolver = BiliResourceResolver(
      dio: Dio()..httpClientAdapter = adapter,
    );
    for (final input in [
      'https://evil.example/video/BV1xx411c7mD',
      'https://www.bilibili.com.evil.example/video/BV1xx411c7mD',
      'https://evil.example/?next=https://www.bilibili.com/video/BV1xx411c7mD',
      'https://user@b23.tv/abc',
      'https://b23.tv:8443/abc',
      'BV123',
      '随便搜首歌',
    ]) {
      await expectLater(resolver.resolve(input), throwsFormatException);
    }
    expect(adapter.requests, isEmpty);
  });

  test('short link cannot redirect to an unrelated host', () async {
    final adapter = RedirectAdapter({
      'https://b23.tv/abc': 'https://evil.example/',
    });
    final resolver = BiliResourceResolver(
      dio: Dio()..httpClientAdapter = adapter,
    );
    await expectLater(
      resolver.resolve('https://b23.tv/abc'),
      throwsFormatException,
    );
    expect(adapter.requests.map((u) => u.host), ['b23.tv']);
  });

  test('redirect loops stop after a bounded number of requests', () async {
    final adapter = RedirectAdapter({'https://b23.tv/abc': '/abc'});
    final resolver = BiliResourceResolver(
      dio: Dio()..httpClientAdapter = adapter,
    );
    await expectLater(
      resolver.resolve('https://b23.tv/abc'),
      throwsFormatException,
    );
    expect(adapter.requests.length, lessThanOrEqualTo(5));
  });
}
