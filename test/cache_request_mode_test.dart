import 'dart:convert';

import 'package:abts/core/storage/cache_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
