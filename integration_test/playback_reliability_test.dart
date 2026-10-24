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

  testWidgets(
    'R-PLAY-01 continuous playback persists without pause or flush',
    (tester) async {
      final book = await BiliApi.instance.detail(
        LocalBiliFixture.concert,
        mode: ContentMode.concert,
      );
      expect(await player.playBook(book, resume: false), isTrue);
      await _until(
        tester,
        () => player.currentPosition.inMilliseconds >= 1000,
        'native playback begins',
      );
      final before = player.currentPosition;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 6)),
      );
      await tester.pump();
      expect(
        player.currentPosition - before,
        greaterThan(const Duration(seconds: 5)),
        reason: 'The native player must actually advance during this probe.',
      );
      final rows =
          jsonDecode(prefs.getString('abts_recent_progress') ?? '[]') as List;
      final matching = rows.where((row) => row['book']['bvid'] == book.bvid);
      final persistedMs = matching.isEmpty
          ? 0
          : (matching.single['positionMs'] as num).toInt();
      // Do not pause/flush before this assertion: that hides the periodic-save bug.
      expect(
        persistedMs,
        greaterThanOrEqualTo(2000),
        reason: 'A continuous position stream must not defer every save.',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'R-PLAY-02 pause while URL lookup is pending remains paused after load',
    (tester) async {
      final book = await BiliApi.instance.detail(
        LocalBiliFixture.music,
        mode: ContentMode.music,
      );
      final gate = fixture.gatePlayUrl(LocalBiliFixture.cid(book.bvid, 2));
      final load = player.playBook(book, resumeIndex: 1);
      pending = load;
      await gate.entered.future.timeout(const Duration(seconds: 15));
      await player.pause();
      gate.release();
      await load.timeout(const Duration(seconds: 30));
      pending = null;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump();
      expect(
        player.isPlaying,
        isFalse,
        reason: 'The latest user pause must win over an older load request.',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'sleep expiry while loading stays paused, explicit resume can override it',
    (tester) async {
      final book = await BiliApi.instance.detail(
        LocalBiliFixture.music,
        mode: ContentMode.music,
      );
      final gate = fixture.gatePlayUrl(LocalBiliFixture.cid(book.bvid, 3));
      final load = player.playBook(book, resumeIndex: 2, resumeMs: 12000);
      pending = load;
      await gate.entered.future.timeout(const Duration(seconds: 15));
      player.setSleepTimer(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      expect(player.sleepRemaining, Duration.zero);
      gate.release();
      expect(await load, isTrue);
      pending = null;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      expect(player.isPlaying, isFalse);
      expect(player.currentPosition.inMilliseconds, closeTo(12000, 1500));
      await player.resume();
      await _until(tester, () => player.isPlaying, 'explicit resume');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'switching resources saves the previous position before native reset',
    (tester) async {
      final first = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
      final second = await BiliApi.instance.detail(
        LocalBiliFixture.music,
        mode: ContentMode.music,
      );
      expect(await player.playBook(first, resumeMs: 26000), isTrue);
      expect(await player.playBook(second), isTrue);
      await prefs.reload();
      final rows =
          jsonDecode(prefs.getString('abts_recent_progress') ?? '[]') as List;
      final saved = rows.where((row) => row['book']['bvid'] == first.bvid);
      expect(saved, hasLength(1));
      expect(saved.single['positionMs'], greaterThanOrEqualTo(25000));
      expect(saved.single['lastCid'], LocalBiliFixture.cid(first.bvid, 1));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'R-PLAY-05 stop preserves a previously saved nonzero resume point',
    (tester) async {
      final book = await BiliApi.instance.detail(
        LocalBiliFixture.retryUrl,
        mode: ContentMode.concert,
      );
      expect(await player.playBook(book, resumeMs: 20000), isTrue);
      await player.pause();
      await _until(
        tester,
        () => (shelf.progressByBvid(book.bvid)?.positionMs ?? 0) >= 19000,
        'nonzero progress is saved',
      );
      await player.stop();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 3)),
      );
      await tester.pump();
      expect(
        shelf.progressByBvid(book.bvid)?.positionMs,
        greaterThanOrEqualTo(19000),
        reason:
            'Native position reset during stop must not overwrite progress.',
      );
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
