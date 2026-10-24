import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/recent_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:blisten/widgets/shelf_common.dart';
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
  Future<bool>? pending;

  Widget host(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: shelf),
      ChangeNotifierProvider<BookPlayer>.value(value: player),
      ChangeNotifierProvider.value(value: cache),
    ],
    child: MaterialApp(theme: AppTheme.dark(), home: child),
  );

  setUpAll(() => guardedHook('cache cleanup setup', () async {
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

  setUp(() => guardedHook('cache cleanup case setup', () async {
    fixture.releaseGates();
    fixture.apiAvailable = true;
    fixture.mediaAvailable = true;
    await player.stop();
    await prefs.clear();
    await shelf.load();
    await cache.clearAll();
    await player.setRate(1);
  }));

  tearDown(() => guardedHook('cache cleanup case cleanup', () async {
    fixture.releaseGates();
    if (pending != null) await pending;
    pending = null;
    await player.stop();
    expect(fixture.unexpectedRequests, isEmpty);
  }));

  tearDownAll(() => guardedHook('cache cleanup shutdown', () async {
    await fixture.close();
    HttpOverrides.global = null;
  }));

  testWidgets('offline P3 keeps CID and offset through same-resource entry and persisted online resume', (tester) async {
    final book = Book(bvid: LocalBiliFixture.cached, aid: 1, title: '离线第三段', pic: '',
        pages: 3, contentMode: ContentMode.concert);
    final cid = LocalBiliFixture.cid(book.bvid, 3);
    expect(await cache.download(bvid: book.bvid, cid: cid,
        url: fixture.audioUrl(cid), bookTitle: book.title, chapterTitle: '第三段',
        cover: '', durationSec: 90, headers: player.downloadHeaders,
        contentMode: book.contentMode, page: 3, part: '第三段', order: 3), isTrue);
    fixture.apiAvailable = false;
    expect(await player.playCachedEntry(book.bvid, cid, book), CachePlayOutcome.okOffline);
    expect(player.chapters, hasLength(1));
    await player.seek(const Duration(seconds: 12));
    await _until(tester, () => player.currentPosition.inMilliseconds >= 11500, 'native seek position');
    final observed = player.currentPosition;
    final sought = observed > const Duration(seconds: 12)
        ? observed : const Duration(seconds: 12);
    await _until(tester, () => player.isPlaying && !player.buffering &&
        player.currentPosition > sought + const Duration(seconds: 1),
        'offline playback advances before saving history');
    await player.pause();
    await _until(tester, () {
      final saved = jsonDecode(prefs.getString('abts_recent_progress') ?? '[]') as List;
      return saved.any((entry) => entry['book']['bvid'] == book.bvid &&
          entry['lastCid'] == cid && (entry['positionMs'] as num) >= 11500);
    }, 'paused progress persisted before simulating reload');
    await shelf.load();
    expect(shelf.progressByBvid(book.bvid)!.toJson()['chaptersComplete'], isFalse);
    fixture.apiAvailable = true;
    expect(await player.playBookWithFallback(shelf.progressByBvid(book.bvid)!), ShelfPlayOutcome.ok);
    expect(player.chapters, hasLength(3));
    expect(player.currentChapter?.cid, cid);
    expect(player.currentPosition.inMilliseconds, closeTo(12000, 2500));
    await player.pause();
    final other = await BiliApi.instance.detail(LocalBiliFixture.retryBook);
    expect(await player.playBook(other), isTrue);
    await shelf.load();
    expect(shelf.progressByBvid(book.bvid)!.toJson()['chaptersComplete'], isTrue);
    expect(await player.resumeShelf(shelf.progressByBvid(book.bvid)!), isTrue);
    expect(player.currentChapter?.cid, cid);
    expect(player.currentPosition.inMilliseconds, closeTo(12000, 2500));
  }, timeout: const Timeout(Duration(minutes: 2)));

  for (final cachedEntry in [false, true]) {
    testWidgets('persisted removal prevents automatic favorite on ${cachedEntry ? 'cached entry' : 'one minute playback'}', (tester) async {
      final book = await BiliApi.instance.detail(LocalBiliFixture.retryBook);
      final chapter = book.chapters!.first;
      if (cachedEntry) {
        expect(await cache.download(bvid: book.bvid, cid: chapter.cid,
            url: fixture.audioUrl(chapter.cid), bookTitle: book.title,
            chapterTitle: chapter.part, cover: '', durationSec: chapter.duration,
            headers: player.downloadHeaders, page: 1, part: chapter.part, order: 1), isTrue);
      }
      // A cold process reads this recent record without ever receiving the
      // removeFromShelf call. No in-memory suppression can satisfy this case.
      await prefs.setString('abts_recent_progress', jsonEncode([{
        ...ShelfBook(book: book).toJson(),
        'autoAddSuppressed': true,
      }]));
      await shelf.load();
      if (cachedEntry) {
        expect(await player.playCachedEntry(book.bvid, chapter.cid, book), CachePlayOutcome.okOffline);
      } else {
        // Switch away first so this scenario gets a fresh native play tally.
        final other = await BiliApi.instance.detail(LocalBiliFixture.concert,
            mode: ContentMode.concert);
        expect(await player.playBook(other), isTrue);
        expect(await player.playBook(book), isTrue);
        await player.setRate(3);
        await _until(tester, () => player.currentPosition.inSeconds >= 65,
            'persisted removal crosses automatic collection threshold');
      }
      expect(shelf.isOnShelf(book.bvid), isFalse);
      await shelf.add(book);
      expect(shelf.isOnShelf(book.bvid), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  testWidgets('removing a favorite keeps playback and suppresses both automatic add paths', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
    final chapter = book.chapters!.first;
    expect(await cache.download(bvid: book.bvid, cid: chapter.cid,
        url: fixture.audioUrl(chapter.cid), bookTitle: book.title,
        chapterTitle: chapter.part, cover: '', durationSec: chapter.duration,
        headers: player.downloadHeaders, page: 1, part: chapter.part, order: 1), isTrue);
    await shelf.add(book);
    expect(await player.playBook(book), isTrue);
    await _until(tester, () => player.currentPosition.inMilliseconds > 500, 'initial playback');
    player.flushProgress();
    await tester.pumpWidget(host(Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => confirmRemoveFromShelf(context, shelf.byBvid(book.bvid)!),
      child: const Text('移出测试收藏'),
    )))));
    await tester.tap(find.text('移出测试收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出'));
    await tester.pumpAndSettle();
    expect(player.isPlaying, isTrue);
    expect(shelf.isOnShelf(book.bvid), isFalse);
    expect(shelf.progressByBvid(book.bvid), isNotNull);
    // Real native playback at the supported rate crosses the existing tally
    // threshold without injecting position events or replacing player code.
    await player.setRate(3);
    await _until(tester, () => player.currentPosition.inSeconds >= 65, 'automatic collection threshold');
    expect(player.isPlaying, isTrue);
    expect(shelf.isOnShelf(book.bvid), isFalse);
    await player.pause();
    // pause flushes a serialized async snapshot; simulate restart only after
    // that snapshot is observable, rather than reading the prior timer save.
    await _until(tester, () {
      final saved = jsonDecode(prefs.getString('abts_recent_progress') ?? '[]') as List;
      return saved.any((entry) => entry['book']['bvid'] == book.bvid &&
          entry['lastCid'] == chapter.cid && (entry['positionMs'] as num) >= 64000);
    }, 'removed favorite progress persisted before reload');
    await shelf.load();
    expect(shelf.progressByBvid(book.bvid)!.lastCid, chapter.cid);
    expect(shelf.progressByBvid(book.bvid)!.positionMs, greaterThanOrEqualTo(64000));
    expect(await player.playCachedEntry(book.bvid, chapter.cid, book), CachePlayOutcome.okOffline);
    expect(shelf.isOnShelf(book.bvid), isFalse);
    await shelf.add(book);
    expect(shelf.isOnShelf(book.bvid), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('clear listening record cancels its pending load and keeps the favorite reset', (tester) async {
    final book = Book(bvid: LocalBiliFixture.retryUrl, aid: 1, title: '待加载记录', pic: '',
        contentMode: ContentMode.concert);
    await shelf.add(book);
    await shelf.updateProgress(book.bvid, book: book,
        cid: LocalBiliFixture.cid(book.bvid, 3), chapterIndex: 2,
        positionMs: 12000, chapterDurationMs: 90000);
    final gate = fixture.gatePageList(book.bvid);
    pending = player.resumeShelf(shelf.byBvid(book.bvid)!);
    await gate.entered.future.timeout(const Duration(seconds: 15));
    await tester.pumpWidget(host(const RecentPage()));
    expect(find.byTooltip('清除收听记录'), findsOneWidget);
    await tester.tap(find.byTooltip('清除收听记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    gate.release();
    expect(await pending, isFalse);
    pending = null;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2300)));
    await shelf.load();
    final retained = shelf.byBvid(book.bvid)!;
    expect(retained.positionMs, 0);
    expect(retained.lastCid, 0);
    expect(retained.doneCids, isEmpty);
    expect(retained.chapterProgress, isEmpty);
    expect(player.isPlaying, isFalse);
    expect(shelf.recentBooks.where((b) => b.hasProgress), isEmpty);
  });

  testWidgets('clearing another resource record leaves current playback advancing', (tester) async {
    final old = Book(bvid: LocalBiliFixture.imported, aid: 1, title: '旧记录', pic: '',
        contentMode: ContentMode.concert);
    await shelf.updateProgress(old.bvid, book: old,
        cid: LocalBiliFixture.cid(old.bvid, 1), chapterIndex: 0,
        positionMs: 12000, chapterDurationMs: 90000);
    final current = await BiliApi.instance.detail(LocalBiliFixture.concert, mode: ContentMode.concert);
    expect(await player.playBook(current), isTrue);
    await tester.pumpWidget(host(const RecentPage()));
    final row = find.ancestor(of: find.text('旧记录'), matching: find.byType(InkWell)).first;
    final clear = find.descendant(of: row, matching: find.byTooltip('清除收听记录'));
    expect(clear, findsOneWidget);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    final position = player.currentPosition;
    await _until(tester, () => player.currentPosition > position + const Duration(milliseconds: 500), 'unrelated playback continues');
    expect(player.book?.bvid, current.bvid);
    expect(shelf.progressByBvid(old.bvid), isNull);
  });

  for (final clearPending in [false, true]) {
    testWidgets('clearing ${clearPending ? 'pending' : 'active'} A preserves unrelated B during a directory lookup', (tester) async {
      final active = await BiliApi.instance.detail(LocalBiliFixture.imported, mode: ContentMode.concert);
      final loading = Book(bvid: LocalBiliFixture.retryMusic, aid: 1, title: '另一条待加载记录',
          pic: '', contentMode: ContentMode.concert);
      expect(await player.playBook(active), isTrue);
      await player.seek(const Duration(seconds: 12));
      await _until(tester,
          () => player.currentPosition >= const Duration(seconds: 12),
          'active native seek position settles');
      // RecentPage can only clear an active item that was actually heard.
      final observed = player.currentPosition;
      final sought = observed > const Duration(seconds: 12)
          ? observed : const Duration(seconds: 12);
      await _until(tester, () => player.isPlaying && !player.buffering &&
          player.currentPosition > sought + const Duration(seconds: 1),
          'active playback establishes the record to clear');
      player.flushProgress();
      await shelf.updateProgress(loading.bvid, book: loading,
          cid: LocalBiliFixture.cid(loading.bvid, 1), chapterIndex: 0,
          positionMs: 12000, chapterDurationMs: 90000);
      final gate = fixture.gatePageList(loading.bvid);
      pending = player.resumeShelf(shelf.progressByBvid(loading.bvid)!);
      await gate.entered.future.timeout(const Duration(seconds: 15));
      await tester.pumpWidget(host(const RecentPage()));
      final cleared = clearPending ? loading : active;
      final row = find.ancestor(of: find.text(cleared.cleanTitle), matching: find.byType(InkWell)).first;
      await tester.tap(find.descendant(of: row, matching: find.byTooltip('清除收听记录')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      gate.release();
      expect(await pending, !clearPending);
      pending = null;
      final expected = clearPending ? active : loading;
      expect(player.book?.bvid, expected.bvid);
      expect(player.isPlaying, isTrue);
      final position = player.currentPosition;
      await _until(tester, () => player.currentPosition > position + const Duration(milliseconds: 500),
          'unrelated selection keeps advancing');
      expect(shelf.progressByBvid(cleared.bvid), isNull);
    });
  }
}

Future<void> _until(WidgetTester tester, bool Function() condition, String label) async {
  final clock = Stopwatch()..start();
  while (!condition() && clock.elapsed < const Duration(seconds: 35)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: label);
}
