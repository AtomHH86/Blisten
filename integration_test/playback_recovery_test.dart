import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/book.dart';
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
      expect(fixture.unexpectedRequests, isEmpty);
    }, timeout: const Duration(seconds: 40)),
  );

  tearDownAll(
    () => guardedHook('playback review cleanup', () async {
      await fixture.close();
      HttpOverrides.global = null;
    }),
  );

  testWidgets(
    'R-PLAY-03 valid directory plus media 503 is not classified as removed',
    (tester) async {
      final book = await BiliApi.instance.detail(
        LocalBiliFixture.imported,
        mode: ContentMode.concert,
      );
      expect(book.chapters, hasLength(3));
      fixture.mediaAvailable = false;
      final outcome = await player
          .playBookWithFallback(ShelfBook(book: book))
          .timeout(const Duration(seconds: 45));
      expect(
        outcome,
        ShelfPlayOutcome.loadFailed,
        reason:
            'A CDN failure cannot prove that an existing video was removed.',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets('explicit missing-directory response is the only removal evidence', (tester) async {
    final missing = Book(bvid: 'BV1missing000', aid: 0, title: '已删除测试', pic: '');
    expect(await player.playBookWithFallback(ShelfBook(book: missing)),
        ShelfPlayOutcome.bookGone);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('directory transport failure remains retryable rather than removed', (tester) async {
    fixture.apiAvailable = false;
    final book = Book(bvid: LocalBiliFixture.retryUrl, aid: 0,
        title: '临时网络失败测试', pic: '');
    expect(await player.playBookWithFallback(ShelfBook(book: book)),
        ShelfPlayOutcome.loadFailed);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets(
    'R-PLAY-04 an offline P3 resume maps by CID after full directory returns',
    (tester) async {
      final book = Book(
        bvid: LocalBiliFixture.cached,
        aid: 1,
        title: '仅缓存第三段的本地测试资源',
        pic: '',
        pages: 3,
        contentMode: ContentMode.concert,
      );
      final cid = LocalBiliFixture.cid(book.bvid, 3);
      await cache.enqueue(
        bvid: book.bvid,
        bookTitle: book.title,
        cover: '',
        contentMode: book.contentMode,
        items: [
          (
            cid: cid,
            chapterTitle: '3 · 第三段',
            durationSec: 90,
            page: 3,
            part: '第三段',
            order: 3,
          ),
        ],
        resolveUrl: (_, value) async => fixture.audioUrl(value),
        headers: player.downloadHeaders,
      );
      await _until(
        tester,
        () => cache.isCached(book.bvid, cid) && !cache.busy,
        'P3 fixture download',
      );
      fixture.apiAvailable = false;
      expect(
        await player.playCachedEntry(book.bvid, cid, book),
        CachePlayOutcome.okOffline,
      );
      expect(player.currentChapter?.cid, cid);
      expect(player.chapters, hasLength(1));
      await player.seek(const Duration(seconds: 12));
      await _until(
        tester,
        () => player.currentPosition.inSeconds >= 11,
        'offline P3 seek',
      );
      final observed = player.currentPosition;
      final sought = observed > const Duration(seconds: 12)
          ? observed : const Duration(seconds: 12);
      await _until(
        tester,
        () =>
            player.isPlaying && !player.buffering &&
            player.currentPosition > sought + const Duration(seconds: 1),
        'offline P3 actually advances before saving',
      );
      await player.pause();
      await _until(
        tester,
        () => (shelf.progressByBvid(book.bvid)?.positionMs ?? 0) >= 11000,
        'offline P3 progress',
      );
      // Roundtrip in-memory metadata through its storage JSON format, then
      // switch sessions to discard the partial directory. This does not reload
      // SharedPreferences or restart the process; it isolates CID/index mapping.
      final restored = ShelfBook.fromJson(
        jsonDecode(jsonEncode(shelf.progressByBvid(book.bvid)!.toJson()))
            as Map<String, dynamic>,
      );
      fixture.apiAvailable = true;
      final other = await BiliApi.instance.detail(
        LocalBiliFixture.retryBook,
        mode: ContentMode.audiobook,
      );
      expect(await player.playBook(other), isTrue);
      expect(await player.playBookWithFallback(restored), ShelfPlayOutcome.ok);
      expect(
        player.currentChapter?.cid,
        cid,
        reason: 'Index 0 in an offline subset is P3, not P1 in the full list.',
      );
      expect(player.currentPosition.inMilliseconds, closeTo(12000, 3000));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
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
