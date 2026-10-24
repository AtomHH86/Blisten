import 'dart:convert';

import 'package:blisten/core/storage/cache_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('children cache, pending task and failed retry retain their mode', () {
    final data = <String, dynamic>{
      'bvid': 'BV1xx411c7mD', 'cid': 103, 'bookTitle': '儿童故事',
      'chapterTitle': '第三集', 'page': 3, 'contentMode': 'children',
    };
    final entry = CacheEntry.fromJson(CacheEntry.fromJson(data).toJson());
    final request = CacheRequest.fromJson(CacheRequest.fromJson(data).toJson());
    final failure = CacheFailure.fromJson(CacheFailure.fromJson(data).toJson());
    expect(entry.toJson()['contentMode'], 'children');
    expect(request.toJson()['contentMode'], 'children');
    expect(failure.toJson()['contentMode'], 'children');
    expect([entry.cid, request.cid, failure.cid], [103, 103, 103]);
    expect([entry.page, request.page, failure.page], [3, 3, 3]);
  });

  test('pending music download retains its type and part across restart', () {
    final resumed = CacheRequest.fromJson(
      jsonDecode(
            jsonEncode({
              'bvid': 'BV1xx411c7mD',
              'cid': 10,
              'bookTitle': '歌曲合集',
              'chapterTitle': '3 · 曲目',
              'page': 3,
              'part': '曲目',
              'order': 3,
              'contentMode': 'music',
            }),
          )
          as Map<String, dynamic>,
    );
    expect(resumed.toJson()['contentMode'], 'music');
    expect(resumed.toJson()['page'], 3);
    expect(resumed.toJson()['part'], '曲目');
    expect(resumed.toJson()['order'], 3);
  });

  test('legacy pending downloads continue as audiobooks', () {
    final resumed = CacheRequest.fromJson({
      'bvid': 'BV1xx411c7mD',
      'cid': 10,
      'bookTitle': '听书',
      'chapterTitle': '第一章',
    });
    expect(resumed.toJson()['contentMode'], 'audiobook');
  });

  test('failed download keeps concert mode for retry', () {
    final restored = CacheFailure.fromJson({
      'bvid': 'BV1xx411c7mD',
      'cid': 10,
      'bookTitle': '演唱会',
      'chapterTitle': '开场',
      'contentMode': 'concert',
    });
    expect(restored.toJson()['contentMode'], 'concert');
  });
}
