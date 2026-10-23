import 'dart:async';
import 'dart:convert';

import 'package:abts/core/storage/cache_store.dart';
import 'package:abts/models/content_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('enqueue persists music mode before resolving a download URL', () async {
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
    final pending = jsonDecode(prefs.getString('abts_cache_pending')!) as List;
    final restored = CacheRequest.fromJson(
      (pending.single as Map).cast<String, dynamic>(),
    );
    expect(restored.contentMode, ContentMode.music);
    expect(restored.cid, 10);
    expect(restored.page, 3);
  });
}
