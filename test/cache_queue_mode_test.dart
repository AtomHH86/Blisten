import 'dart:async';
import 'dart:convert';

import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'enqueue preserves the active download metadata when adding another item',
    () async {
      SharedPreferences.setMockInitialValues({});
      // Hold only the external URL lookup; enqueue and persistence remain real.
      final urlLookup = Completer<String?>();
      await CacheStore.instance.enqueue(
        bvid: 'BV1xx411c7mD',
        bookTitle: '歌曲合集',
        cover: '',
        contentMode: ContentMode.music,
        items: [
          (
            cid: 10,
            chapterTitle: '3 · 曲目',
            durationSec: 180,
            page: 3,
            part: '曲目',
            order: 3,
          ),
        ],
        resolveUrl: (_, _) => urlLookup.future,
        headers: {},
      );
      final prefs = await SharedPreferences.getInstance();
      final pending =
          jsonDecode(prefs.getString('abts_cache_pending')!) as List;
      final restored = CacheRequest.fromJson(
        (pending.single as Map).cast<String, dynamic>(),
      );
      expect(restored.contentMode, ContentMode.music);
      expect(restored.cid, 10);
      expect(restored.page, 3);

      // A second enqueue persists the first item after it has left the queue.
      await CacheStore.instance.enqueue(
        bvid: 'BV1yy411c7mD',
        bookTitle: '另一场演唱会',
        cover: '',
        contentMode: ContentMode.concert,
        items: [
          (
            cid: 20,
            chapterTitle: '开场',
            durationSec: 240,
            page: 1,
            part: '开场',
            order: 1,
          ),
        ],
        resolveUrl: (_, _) => urlLookup.future,
        headers: {},
      );
      final afterEnqueue =
          (jsonDecode(prefs.getString('abts_cache_pending')!) as List).map(
            (item) =>
                CacheRequest.fromJson((item as Map).cast<String, dynamic>()),
          );
      final active = afterEnqueue.singleWhere((item) => item.cid == 10);
      expect(active.contentMode, ContentMode.music);
      expect(active.bookTitle, '歌曲合集');
      expect(active.durationSec, 180);
      expect(active.page, 3);
      expect(active.part, '曲目');
      expect(active.order, 3);
    },
  );
}
