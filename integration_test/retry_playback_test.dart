import 'dart:io';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/player_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/player/playback_preferences.dart';
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

  setUpAll(
    () => guardedHook('retry setUpAll', () async {
      expect(Platform.isAndroid, isTrue);
      await fixture.start();
      HttpOverrides.global = fixture;
      MediaKit.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await BiliClient.instance.initLocal();
      await shelf.load();
      await cache.load();
      await cache.clearAll();
      player = BookPlayer.instance;
      await fixture.configurePlayer(player.player);
      // Deliberately do not start the automatic reconnect/watchdog listeners.
      // These tests must observe the user's retry rather than an automatic retry.
    }, timeout: const Duration(seconds: 60)),
  );

  setUp(
    () => guardedHook('retry setUp', () async {
      fixture.releaseGates();
      fixture.apiAvailable = true;
      fixture.mediaAvailable = true;
      fixture.audioGeneration = 0;
      fixture.minimumAudioGeneration = 0;
      await player.stop();
      for (final mode in ContentMode.values) {
        await PlaybackPreferences().saveRate(mode, 1);
      }
    }),
  );

  tearDown(
    () => guardedHook('retry tearDown', () async {
      fixture.releaseGates();
      await player.stop();
      expect(fixture.unexpectedRequests, isEmpty);
    }),
  );

  tearDownAll(
    () => guardedHook('retry tearDownAll', () async {
      await fixture.close();
      HttpOverrides.global = null;
    }),
  );

  for (final entry in ['direct', 'shelf', 'cache']) {
    for (final stop in [false, true]) {
      testWidgets(
        'late $entry directory cannot override ${stop ? 'stop' : 'new selection'}',
        (tester) async {
          await PlaybackPreferences().saveRate(ContentMode.music, 0.75);
          final a = _withoutChapters(LocalBiliFixture.imported);
          final b = await _detail(LocalBiliFixture.music, ContentMode.music);
          expect(await player.playBook(b, resumeIndex: 2), isTrue);
          if (entry == 'cache') {
            await _cacheChapter(tester, fixture, player, a);
          }
          final gate = fixture.gatePageList(a.bvid);
          final Future<Object> pending = switch (entry) {
            'direct' => player.playBook(a),
            'shelf' => player.playBookWithFallback(ShelfBook(book: a)),
            _ => player.playCachedEntry(
              a.bvid,
              LocalBiliFixture.cid(a.bvid, 1),
              a,
            ),
          };
          await gate.entered.future.timeout(const Duration(seconds: 15));
          if (stop) {
            await player.stop();
          } else {
            expect(await player.playBook(b, resumeIndex: 1), isTrue);
          }
          gate.release();
          await pending.timeout(const Duration(seconds: 30));
          await tester.pump(const Duration(milliseconds: 300));
          expect(player.book?.bvid, b.bvid);
          expect(player.loaded, !stop);
          if (stop) {
            expect(player.isPlaying, isFalse);
          } else {
            expect(player.index, 1);
            expect(player.playbackUrl, contains('/audio/202.wav'));
            expect(player.rate, closeTo(0.75, 0.01));
            expect(player.player.state.rate, closeTo(0.75, 0.01));
          }
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  }

  testWidgets(
    'invalidated failed shelf load does not write its fallback over new selection',
    (tester) async {
      final a = await _detail(LocalBiliFixture.concert, ContentMode.concert);
      final b = await _detail(LocalBiliFixture.music, ContentMode.music);
      final gate = fixture.gatePlayUrl(LocalBiliFixture.cid(a.bvid, 3))
        ..fail = true;
      final pending = player.playBookWithFallback(
        ShelfBook(book: a, lastChapterIndex: 2),
      );
      await gate.entered.future.timeout(const Duration(seconds: 15));
      expect(await player.playBook(b, resumeIndex: 1), isTrue);
      gate.release();
      await pending.timeout(const Duration(seconds: 30));
      expect(player.book?.bvid, b.bvid);
      expect(player.loaded, isTrue);
      expect(player.index, 1);
      expect(player.error, isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  for (final stop in [false, true]) {
    testWidgets(
      'late reconnect cannot override ${stop ? 'stop' : 'new selection'}',
      (tester) async {
        final a = await _detail(
          LocalBiliFixture.audiobook,
          ContentMode.audiobook,
        );
        final b = await _detail(LocalBiliFixture.music, ContentMode.music);
        final unavailable = await _detail(
          LocalBiliFixture.imported,
          ContentMode.concert,
        );
        final page = stop ? 3 : 1;
        expect(
          await player.playBook(a, resumeIndex: page - 1, resumeMs: 9000),
          isTrue,
        );
        final failed = fixture.gatePlayUrl(
          LocalBiliFixture.cid(unavailable.bvid, 2),
        )..fail = true;
        failed.release();
        expect(await player.playBook(unavailable, resumeIndex: 1), isFalse);
        expect(player.loaded, isTrue); // Last successful A remains the session.
        final gate = fixture.gatePlayUrl(LocalBiliFixture.cid(a.bvid, page));
        final pending = player.resume();
        await gate.entered.future.timeout(const Duration(seconds: 15));
        if (stop) {
          await player.stop();
        } else {
          expect(await player.playBook(b, resumeIndex: 1), isTrue);
        }
        gate.release();
        await pending.timeout(const Duration(seconds: 30));
        await tester.pump(const Duration(milliseconds: 300));
        expect(player.loaded, !stop);
        if (stop) {
          expect(player.isPlaying, isFalse);
        } else {
          expect(player.book?.bvid, b.bvid);
          expect(player.playbackUrl, contains('/audio/202.wav'));
          expect(
            player.player.state.playlist.medias.single.uri,
            contains('/audio/202.wav'),
          );
          expect(player.currentPosition.inMilliseconds, lessThan(5000));
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  for (final sample in [
    (bvid: LocalBiliFixture.retryMusic, mode: ContentMode.music, ms: 0),
    (bvid: LocalBiliFixture.retryBook, mode: ContentMode.audiobook, ms: 17000),
  ]) {
    testWidgets(
      'user retry restores selected ${sample.mode.name} part and offset',
      (tester) async {
        final book = await _detail(sample.bvid, sample.mode);
        fixture.apiAvailable = false;
        expect(
          await player.playBook(book, resumeIndex: 1, resumeMs: sample.ms),
          isFalse,
        );
        expect(player.error, isNotNull);
        fixture.apiAvailable = true;
        await tester.pumpWidget(_host(player));
        final retry = find.text('重试');
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await _until(
          tester,
          () =>
              !player.loading &&
              player.error == null &&
              player.loaded &&
              player.isPlaying &&
              player.currentDuration > Duration.zero,
          'manual retry completes',
        );
        expect(player.book?.bvid, book.bvid);
        expect(player.book?.contentMode, sample.mode);
        expect(player.index, 1);
        expect(player.currentPosition.inMilliseconds, closeTo(sample.ms, 3000));
        expect(player.isPlaying, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  testWidgets(
    'user retry refreshes expired cached URL instead of reopening it',
    (tester) async {
      final book = await _detail(
        LocalBiliFixture.retryUrl,
        ContentMode.concert,
      );
      final cid = LocalBiliFixture.cid(book.bvid, 2);
      // Establish a real failed request before another consumer caches an address.
      // Native open is asynchronous, so a 503 media URL alone cannot establish a
      // synchronous playBook failure. The stale address must be refreshed by retry.
      fixture.apiAvailable = false;
      expect(
        await player.playBook(book, resumeIndex: 1, resumeMs: 13000),
        isFalse,
      );
      fixture.apiAvailable = true;
      final old = await player.resolveUrlFor(book.bvid, cid);
      expect(old, contains('generation=0'));
      fixture.audioGeneration = 1;
      fixture.minimumAudioGeneration = 1;
      final requestsBefore = fixture.playUrlRequests
          .where((value) => value == cid)
          .length;
      await tester.pumpWidget(_host(player));
      final retry = find.text('重试');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await _until(tester, () => !player.loading, 'retry request settles');
      expect(player.error, isNull);
      expect(player.loaded, isTrue);
      expect(
        fixture.playUrlRequests.where((value) => value == cid).length,
        greaterThan(requestsBefore),
      );
      expect(player.playbackUrl, contains('generation=1'));
      expect(player.index, 1);
      expect(player.currentPosition.inMilliseconds, closeTo(13000, 3000));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'failed replacement restores the last successful session rather than a pending target',
    (tester) async {
      final c = await _detail(LocalBiliFixture.music, ContentMode.music);
      final a = await _detail(LocalBiliFixture.concert, ContentMode.concert);
      final b = await _detail(
        LocalBiliFixture.retryBook,
        ContentMode.audiobook,
      );
      expect(await player.playBook(c, resumeIndex: 2, resumeMs: 7000), isTrue);
      final pendingGate = fixture.gatePlayUrl(LocalBiliFixture.cid(a.bvid, 1));
      final pendingA = player.playBook(a);
      await pendingGate.entered.future.timeout(const Duration(seconds: 15));
      final failureGate = fixture.gatePlayUrl(LocalBiliFixture.cid(b.bvid, 3))
        ..fail = true;
      failureGate.release();
      expect(await player.playBook(b, resumeIndex: 2), isFalse);
      pendingGate.release();
      expect(await pendingA.timeout(const Duration(seconds: 30)), isFalse);
      expect(player.book?.bvid, c.bvid);
      expect(player.loaded, isTrue);
      expect(player.index, 2);
      expect(player.playbackUrl, contains('/audio/203.wav'));
      expect(
        player.player.state.playlist.medias.single.uri,
        contains('/audio/203.wav'),
      );
      player.flushProgress();
      expect(
        shelf.progressByBvid(c.bvid)?.lastCid,
        LocalBiliFixture.cid(c.bvid, 3),
      );
      expect(shelf.progressByBvid(a.bvid), isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'native error during a pending directory does not start an old-session reconnect',
    (tester) async {
      // Last case only: enable real production error listeners after the cases
      // that intentionally isolate manual retries from automatic reconnection.
      player.setup();
      final a = await _detail(
        LocalBiliFixture.audiobook,
        ContentMode.audiobook,
      );
      final b = _withoutChapters(LocalBiliFixture.retryMusic);
      expect(await player.playBook(a, resumeIndex: 2), isTrue);
      final directory = fixture.gatePageList(b.bvid);
      final reconnect = fixture.gatePlayUrl(LocalBiliFixture.cid(a.bvid, 3));
      final pendingB = player.playBook(b);
      await directory.entered.future.timeout(const Duration(seconds: 15));
      final nativeError = player.player.stream.error.first;
      // A real native 503 event models A's stream/decoder reporting an error while
      // B's directory request is pending. There is no production test hook.
      final rejected = Uri.parse(
        fixture.audioUrl(LocalBiliFixture.cid(a.bvid, 3)),
      ).replace(queryParameters: {'generation': '-1'});
      await player.player.open(Media(rejected.toString()), play: false);
      expect(
        await nativeError.timeout(const Duration(seconds: 15)),
        isNotEmpty,
      );
      // Allow bounded real HTTP scheduling time before concluding that no
      // reconnect was launched. A single frame pump can miss the async lookup.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump();
      expect(
        reconnect.entered.isCompleted,
        isFalse,
        reason: 'The pending B load must own error recovery and loading state.',
      );
      expect(player.loading, isTrue);
      directory.release();
      expect(await pendingB.timeout(const Duration(seconds: 30)), isTrue);
      expect(player.book?.bvid, b.bvid);
      expect(player.playbackUrl, contains('/audio/601.wav'));
      expect(player.error, isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'native media failure during seek setup is visible and can be retried',
    (tester) async {
      // The previous test enables the real listener. Keep it enabled for a new,
      // uncached CID whose open() can return before the native 503 error arrives.
      player.setup();
      final book = await _detail(
        LocalBiliFixture.retryUrl,
        ContentMode.concert,
      );
      fixture.mediaAvailable = false;
      await tester.pumpWidget(_host(player));
      final ok = await player.playBook(book, resumeIndex: 2, resumeMs: 13000);
      expect(
        ok,
        isFalse,
        reason:
            'An accepted native open command is not proof of playable media.',
      );
      await _until(
        tester,
        () => !player.loading && player.error != null,
        'native failure reaches the visible playback state',
      );
      await tester.pump(); // Render the notifier update after native failure.
      expect(find.text('暂时无法播放'), findsOneWidget);
      final retry = find.text('重试');
      await tester.ensureVisible(retry);
      fixture.mediaAvailable = true;
      await tester.tap(retry);
      await _until(
        tester,
        () =>
            !player.loading &&
            player.error == null &&
            player.loaded &&
            player.book?.bvid == book.bvid &&
            player.index == 2 &&
            player.isPlaying &&
            player.currentDuration > Duration.zero,
        'native media failure recovers after manual retry',
      );
      expect(player.currentPosition.inMilliseconds, closeTo(13000, 3000));
      expect(player.playbackUrl, contains('/audio/803.wav'));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Book _withoutChapters(String bvid) => Book(
  bvid: bvid,
  aid: 1,
  title: '延迟目录 $bvid',
  pic: '',
  contentMode: ContentMode.concert,
);

Future<Book> _detail(String bvid, ContentMode mode) =>
    BiliApi.instance.detail(bvid, mode: mode);

Widget _host(BookPlayer player) => MultiProvider(
  providers: [
    ChangeNotifierProvider<BookPlayer>.value(value: player),
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider.value(value: CacheStore.instance),
  ],
  child: MaterialApp(theme: AppTheme.dark(), home: const PlayerPage()),
);

Future<void> _cacheChapter(
  WidgetTester tester,
  LocalBiliFixture fixture,
  BookPlayer player,
  Book book,
) async {
  final cid = LocalBiliFixture.cid(book.bvid, 1);
  if (CacheStore.instance.isCached(book.bvid, cid)) return;
  await CacheStore.instance.enqueue(
    bvid: book.bvid,
    bookTitle: book.title,
    cover: '',
    contentMode: ContentMode.concert,
    items: [
      (
        cid: cid,
        chapterTitle: '缓存分 P',
        durationSec: 90,
        page: 1,
        part: '缓存分 P',
        order: 1,
      ),
    ],
    resolveUrl: (bvid, cid) async => fixture.audioUrl(cid),
    headers: player.downloadHeaders,
  );
  await _until(
    tester,
    () =>
        CacheStore.instance.isCached(book.bvid, cid) &&
        !CacheStore.instance.busy,
    'native cache fixture downloaded',
  );
}

Future<void> _until(
  WidgetTester tester,
  bool Function() predicate,
  String label,
) async {
  final clock = Stopwatch()..start();
  while (!predicate() && clock.elapsed < const Duration(seconds: 30)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(predicate(), isTrue, reason: label);
}
