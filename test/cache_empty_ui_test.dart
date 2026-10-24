import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/cache_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// Test the store's real filesystem work through the plugin boundary.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  final String path;
  _Paths(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getExternalStoragePath() async => null;
}

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
        // Startup now waits for real filesystem reconciliation. Give the widget
        // test an actual cached fixture and run I/O outside its fake clock.
        final cache = CacheStore.instance;
        final previousPaths = PathProviderPlatform.instance;
        late Directory root;
        late File audio;
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp('blisten-cache-ui-');
          PathProviderPlatform.instance = _Paths(root.path);
          final dir = await Directory('${root.path}/audio_cache').create();
          audio = await File('test/fixtures/cache-silence.m4a').copy('${dir.path}/${entry.fileName}');
          await cache.load();
          await ShelfStore.instance.load();
        });
        addTearDown(() async {
          await tester.runAsync(() async {
            await cache.clearAll();
            await root.delete(recursive: true);
            PathProviderPlatform.instance = previousPaths;
          });
        });
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
        // Each filesystem await resumes the page callback in its fake zone.
        // Alternate frames with real I/O time until the index is updated.
        for (var attempt = 0; attempt < 100 && cache.entries.isNotEmpty; attempt++) {
          await tester.pump();
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        }
        await tester.runAsync(() async {
          expect(await audio.exists(), isFalse);
        });
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
