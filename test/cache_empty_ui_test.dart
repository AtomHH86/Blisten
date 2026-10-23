import 'dart:convert';

import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/cache_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final deleteAll in [false, true]) {
    testWidgets(
      'deleting ${deleteAll ? 'all' : 'the last'} cached concert part leaves an empty sheet',
      (tester) async {
        const entry = CacheEntry(
          bvid: 'BV1xx411c7mD',
          cid: 10,
          bookTitle: '现场测试',
          chapterTitle: '1 · 开场',
          contentMode: ContentMode.concert,
        );
        SharedPreferences.setMockInitialValues({
          'abts_cache_index': jsonEncode([entry.toJson()]),
          'abts_shelf': '[]',
        });
        // This component test exercises the real cache index and deletion UI.
        // Native directories are unavailable in widget tests; no audio is opened.
        final cache = CacheStore.instance;
        await cache.load();
        await ShelfStore.instance.load();
        expect(cache.entries, hasLength(1));

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: cache),
              ChangeNotifierProvider.value(value: ShelfStore.instance),
            ],
            child: const MaterialApp(home: CachePage()),
          ),
        );
        await tester.tap(find.text('现场测试'));
        await tester.pumpAndSettle();
        await tester.tap(deleteAll ? find.text('删除全部') : find.byTooltip('删除'));
        await tester.pumpAndSettle();
        expect(
          find.text(deleteAll ? '删除这 1 段离线缓存？' : '删除这一段的缓存'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, '删除'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(cache.entries, isEmpty);
        expect(find.text('缓存已被清空'), findsOneWidget);
        expect(find.textContaining('已缓存 0 段'), findsOneWidget);
        final prefs = await SharedPreferences.getInstance();
        expect(jsonDecode(prefs.getString('abts_cache_index')!), isEmpty);
      },
    );
  }
}
