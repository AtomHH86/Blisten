import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/player/playback_preferences.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/checked_hooks.dart';
import 'support/local_bili_fixture.dart';

// Regression cases migrated from the full-project review.
// Only loopback fixture data is used. No real account or Bilibili media is read.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final fixture = LocalBiliFixture();
  final shelf = ShelfStore.instance;
  final cache = CacheStore.instance;
  late BookPlayer player;
  late SharedPreferences prefs;
  Future<Object?>? pending;

  setUpAll(
    () => guardedHook('playback review setup', () async {
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
    }, timeout: const Duration(seconds: 60)),
  );

  setUp(
    () => guardedHook('playback review case setup', () async {
      fixture.releaseGates();
      fixture.apiAvailable = true;
      fixture.mediaAvailable = true;
      fixture.audioGeneration = 0;
      fixture.minimumAudioGeneration = 0;
      player.cancelSleepTimer();
      player.setStopAtChapterEnd(false);
      await player.stop();
      // Let any old debounced save settle before clearing test-only data.
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      await prefs.clear();
      await shelf.load();
      await cache.clearAll();
      cache.clearFinishedTasks();
      for (final mode in ContentMode.values) {
        await PlaybackPreferences().saveRate(mode, 1);
      }
    }),
  );

  tearDown(
    () => guardedHook('playback review case cleanup', () async {
      fixture.releaseGates();
      await player.stop();
      final outstanding = pending;
      pending = null;
      if (outstanding != null) {
        await outstanding.timeout(const Duration(seconds: 30));
      }
      expect(fixture.unexpectedRequests, isEmpty);
    }, timeout: const Duration(seconds: 40)),
  );

  tearDownAll(
    () => guardedHook('playback review cleanup', () async {
      await fixture.close();
      HttpOverrides.global = null;
    }),
  );

  for (final sample in [
    (LocalBiliFixture.audiobook, ContentMode.audiobook),
    (LocalBiliFixture.music, ContentMode.music),
    (LocalBiliFixture.concert, ContentMode.concert),
    (LocalBiliFixture.children, ContentMode.children),
  ]) {
    testWidgets(
      'manual collection only after real minute ${sample.$2.name}',
      (tester) async {
        final book = await BiliApi.instance.detail(sample.$1, mode: sample.$2);
        expect(await player.playBook(book, resume: false), isTrue);
        await player.setRate(1);
        await _until(
          tester,
          () => player.isPlaying && player.currentDuration.inSeconds >= 89,
          'native starts',
        );
        final clock = Stopwatch()..start();
        while (player.currentPosition.inSeconds < 61 ||
            clock.elapsed.inSeconds < 60) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 500)),
          );
          await tester.pump();
          expect(player.error, isNull);
          expect(clock.elapsed.inSeconds, lessThan(100));
        }
        expect(shelf.books, isEmpty);
        expect(shelf.recentBooks.single.book.bvid, book.bvid);
        await player.pause();
        await prefs.reload();
        expect(jsonDecode(prefs.getString('abts_shelf') ?? '[]'), isEmpty);
        await shelf.add(book);
        expect(shelf.isOnShelf(book.bvid), isTrue);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
  testWidgets(
    'part advance completion move removal and clear retain independent identities',
    (tester) async {
      final book = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
      expect(await player.playBook(book, resume: false), isTrue);
      await _until(
        tester,
        () => player.currentPosition.inSeconds >= 2,
        'heard first part',
      );
      await shelf.add(book);
      await shelf.moveToMode(book.bvid, ContentMode.music);
      expect(player.book!.contentMode, ContentMode.audiobook);
      expect(player.isPlaying, isTrue);
      await player.playChapterIndex(1);
      await _until(
        tester,
        () => player.currentPosition.inSeconds >= 2,
        'heard next part',
      );
      expect(
        shelf.progressByBvid(book.bvid)!.book.contentMode,
        ContentMode.music,
      );
      await player.removeFromShelf(book.bvid);
      expect(player.isPlaying, isTrue);
      expect(shelf.books, isEmpty);
      // Completion probe is separate from the real-minute cases above.
      await player.playChapterIndex(2);
      await _until(
        tester,
        () => player.currentDuration.inSeconds >= 89,
        'last part duration',
      );
      await player.seek(const Duration(seconds: 88));
      await _until(
        tester,
        () =>
            shelf.isChapterDone(book.bvid, LocalBiliFixture.cid(book.bvid, 3)),
        'completion marker',
      );
      await _until(tester, () => !player.isPlaying, 'native final part completes');
      expect(shelf.recentBooks.single.book.bvid, book.bvid);
      expect(shelf.books, isEmpty);
      await player.clearListeningRecord(book.bvid);
      expect(player.loaded, isFalse);
      expect(shelf.recentBooks, isEmpty);
    },
  );
  for (final sample in [
    (LocalBiliFixture.audiobook, ContentMode.audiobook),
    (LocalBiliFixture.music, ContentMode.music),
    (LocalBiliFixture.concert, ContentMode.concert),
    (LocalBiliFixture.children, ContentMode.children),
  ]) {
    testWidgets('cache playback never collects ${sample.$2.name}', (
      tester,
    ) async {
      final book = await BiliApi.instance.detail(sample.$1, mode: sample.$2);
      final chapter = book.chapters!.first;
      await cache.enqueue(
        bvid: book.bvid,
        bookTitle: book.cleanTitle,
        cover: '',
        contentMode: sample.$2,
        items: [
          (
            cid: chapter.cid,
            chapterTitle: chapter.part,
            durationSec: 90,
            page: 1,
            part: chapter.part,
            order: 1,
          ),
        ],
        resolveUrl: player.resolveUrlFor,
        headers: player.downloadHeaders,
      );
      await _until(
        tester,
        () => cache.isCached(book.bvid, chapter.cid) && !cache.busy,
        'cached media',
      );
      expect(shelf.books, isEmpty);
      fixture.apiAvailable = false;
      fixture.mediaAvailable = false;
      await player.playCachedEntry(book.bvid, chapter.cid, book);
      await _until(
        tester,
        () => player.currentPosition.inSeconds >= 2,
        'offline advances',
      );
      expect(player.isOffline, isTrue);
      expect(shelf.recentBooks.single.book.bvid, book.bvid);
      expect(shelf.books, isEmpty);
    });
  }
}

Future<void> _until(
  WidgetTester tester,
  bool Function() condition,
  String label,
) async {
  final clock = Stopwatch()..start();
  while (!condition() && clock.elapsed < const Duration(seconds: 30)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: label);
}
