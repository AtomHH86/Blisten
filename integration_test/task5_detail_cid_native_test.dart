// Pair the widget entry contract with actual detail navigation and native audio.
import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/chapter.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/book_detail_page.dart';
import 'package:blisten/pages/player_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/checked_hooks.dart';
import 'support/local_bili_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final fixture = LocalBiliFixture();
  final shelf = ShelfStore.instance;
  final cache = CacheStore.instance;
  late BookPlayer player;
  late SharedPreferences prefs;

  setUpAll(() => guardedHook('detail CID setup', () async {
    expect(Platform.isAndroid, isTrue);
    await fixture.start();
    HttpOverrides.global = fixture;
    MediaKit.ensureInitialized();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await BiliClient.instance.initLocal();
    await shelf.load();
    await cache.load();
    await cache.clearAll();
    player = BookPlayer.instance;
    await fixture.configurePlayer(player.player);
    player.setup();
  }));

  tearDownAll(() => guardedHook('detail CID shutdown', () async {
    await player.stop();
    expect(fixture.unexpectedRequests, isEmpty);
    await fixture.close();
    HttpOverrides.global = null;
  }));

  testWidgets('real full detail opens native P3 at saved partial-directory offset', (tester) async {
    final cid = LocalBiliFixture.cid(LocalBiliFixture.cached, 3);
    final partial = Book(bvid: LocalBiliFixture.cached, aid: 1,
        title: '离线第三段', pic: '', pages: 3, contentMode: ContentMode.concert,
        chapters: [Chapter(cid: cid, page: 3, part: '第三段', duration: 90)]);
    await prefs.setString('abts_recent_progress', jsonEncode([
      ShelfBook(book: partial, lastCid: cid, lastChapterIndex: 0,
          positionMs: 12000, chapterDurationMs: 90000,
          chaptersComplete: false).toJson(),
    ]));
    await shelf.load();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: shelf),
        ChangeNotifierProvider.value(value: cache),
        ChangeNotifierProvider<BookPlayer>.value(value: player),
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: BookDetailPage(
        bvid: partial.bvid, contentMode: ContentMode.concert,
      )),
    ));
    // This is the real detail API/load path, not an initialBook shortcut.
    await _until(tester, () => find.text('目录（3 段）').evaluate().isNotEmpty,
        'full directory visible');
    await tester.tap(find.text('继续收听'));
    await _until(tester, () => find.byType(PlayerPage).evaluate().isNotEmpty && player.loaded,
        'detail completion opens the real player');
    expect(player.chapters, hasLength(3));
    expect(player.currentChapter?.cid, cid);
    expect(player.currentPosition.inMilliseconds, closeTo(12000, 2500));
    expect(player.isPlaying, isTrue);
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 2)));

  final resources = [LocalBiliFixture.imported, LocalBiliFixture.retryMusic,
    LocalBiliFixture.retryBook, LocalBiliFixture.retryUrl];
  var caseIndex = 0;
  for (final missingInOld in [false, true]) {
    for (final explicitPage in [false, true]) {
      final bvid = resources[caseIndex++];
      testWidgets('fresh detail ${explicitPage ? 'page link' : 'chapter row'} selects exact CID with ${missingInOld ? 'new chapter absent from old' : 'reordered old'} directory', (tester) async {
        // Isolate the route even if a previous case failed before its cleanup.
        await tester.pumpWidget(const SizedBox());
        await player.stop();
        await prefs.clear();
        await shelf.load();
        final current = await BiliApi.instance.detail(bvid, mode: ContentMode.concert);
        final complete = current.chapters!;
        final old = missingInOld
            ? Book(bvid: current.bvid, aid: current.aid, title: current.title,
                pic: current.pic, pages: 2, contentMode: current.contentMode,
                chapters: [complete[0], complete[1]])
            : current.withChapters([complete[2], complete[1], complete[0]]);
        // Seed a genuine loaded complete directory through the real player.
        // The fresh detail below still comes from the actual Bili API fixture.
        expect(await player.playBook(old), isTrue);
        expect(player.chapters.map((c) => c.cid).toList(),
            old.chapters!.map((c) => c.cid).toList());
        await player.seek(const Duration(seconds: 12));
        await _until(tester, () => player.currentPosition.inMilliseconds >= 11500,
            'prior chapter position');
        await player.pause();
        final page = missingInOld ? 3 : 1;
        final selectedCid = LocalBiliFixture.cid(bvid, page);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: shelf),
            ChangeNotifierProvider.value(value: cache),
            ChangeNotifierProvider<BookPlayer>.value(value: player),
          ],
          child: MaterialApp(key: ValueKey(bvid), theme: AppTheme.dark(), home: BookDetailPage(
            bvid: bvid, contentMode: ContentMode.concert,
            initialPage: explicitPage ? page : null,
          )),
        ));
        await _until(tester, () => find.text('目录（3 段）').evaluate().isNotEmpty,
            'fresh complete directory visible');
        var started = false;
        var finished = false;
        void observeLoad() {
          if (player.loading) {
            started = true;
          } else if (started) {
            finished = true;
          }
        }
        player.addListener(observeLoad);
        addTearDown(() => player.removeListener(observeLoad));
        final action = find.text(explicitPage ? '播放第 $page 段' : '测试分 P $page');
        if (explicitPage) {
          await tester.ensureVisible(action);
        } else {
          await tester.scrollUntilVisible(action, 180,
              scrollable: find.byType(Scrollable).first);
        }
        await tester.tap(action);
        await _until(tester, () => finished, 'selected chapter load completed');
        if (explicitPage) {
          // Loading becomes false before the awaited UI callback pushes its route.
          await _until(tester, () => find.byType(PlayerPage).evaluate().isNotEmpty,
              'completed page action opens player');
        }
        expect(player.currentChapter?.cid, selectedCid);
        expect(player.currentPosition.inMilliseconds, lessThan(2500),
            reason: 'Explicit page and chapter actions start at zero.');
        expect(player.isPlaying, isTrue);
        if (explicitPage) expect(find.byType(PlayerPage), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  }
}

Future<void> _until(WidgetTester tester, bool Function() condition, String label) async {
  final clock = Stopwatch()..start();
  while (!condition() && clock.elapsed < const Duration(seconds: 35)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: label);
}
