import 'dart:convert';

import 'package:abts/core/storage/cache_store.dart';
import 'package:abts/core/storage/shelf_store.dart';
import 'package:abts/models/book.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cache entries keep their mode after persistence for offline playback',
    () {
      final restored = CacheEntry.fromJson({
        'bvid': 'BV1xx411c7mD',
        'cid': 10,
        'bookTitle': '现场',
        'chapterTitle': '1 · 开场',
        'contentMode': 'concert',
      });
      expect(restored.toJson()['contentMode'], 'concert');
    },
  );

  test('old cache entries remain audiobooks', () {
    final restored = CacheEntry.fromJson({
      'bvid': 'BV1xx411c7mD',
      'cid': 10,
      'bookTitle': '听书',
      'chapterTitle': '第一章',
    });
    expect(restored.toJson()['contentMode'], 'audiobook');
  });

  test(
    'refreshing shelf metadata retains the saved content mode and position',
    () async {
      SharedPreferences.setMockInitialValues({
        'abts_shelf': jsonEncode([
          {
            'book': {
              'bvid': 'BV1xx411c7mD',
              'title': '原题',
              'contentMode': 'music',
            },
            'positionMs': 12000,
            'lastCid': 10,
          },
        ]),
      });
      final shelf = ShelfStore.instance;
      await shelf.load();
      await shelf.add(
        Book(bvid: 'BV1xx411c7mD', aid: 0, title: '更新后的标题', pic: ''),
      );
      final stored = shelf.byBvid('BV1xx411c7mD')!;
      expect(stored.book.cleanTitle, '更新后的标题');
      expect(stored.book.toJson()['contentMode'], 'music');
      expect(stored.positionMs, 12000);
    },
  );
}
