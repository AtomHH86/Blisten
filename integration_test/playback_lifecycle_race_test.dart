import 'dart:async';
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
  _SeekAcknowledgementGate? seekGate;
  PlatformPlayer? originalPlatform;

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
      seekGate?.unblock();
      if (originalPlatform != null) player.player.platform = originalPlatform;
      originalPlatform = null;
      seekGate = null;
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

  testWidgets('paused initial load and seeks never establish listening', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.concert,
        mode: ContentMode.concert);
    final gate = fixture.gatePlayUrl(LocalBiliFixture.cid(book.bvid, 2));
    final load = player.playBook(book, resumeIndex: 1, resumeMs: 47000);
    pending = load;
    await gate.entered.future.timeout(const Duration(seconds: 15));
    await player.pause();
    gate.release();
    expect(await load, isTrue);
    pending = null;
    expect(player.isPlaying, isFalse);
    await player.seek(const Duration(seconds: 20));
    player.flushProgress();
    await player.seek(Duration.zero);
    player.flushProgress();
    expect(shelf.recentBooks, isEmpty);
    expect(shelf.isOnShelf(book.bvid), isFalse);
    expect(shelf.progressByBvid(book.bvid), isNull);
  });

  testWidgets('failed playback cannot create history or favorites', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.concert,
        mode: ContentMode.concert);
    fixture.mediaAvailable = false;
    expect(await player.playBook(book, resumeIndex: 1, resumeMs: 47000), isFalse);
    player.flushProgress();
    expect(shelf.recentBooks, isEmpty);
    expect(shelf.isOnShelf(book.bvid), isFalse);
  });

  for (final mode in ContentMode.values) {
    testWidgets('$mode playback advancement records listening without favorite', (tester) async {
      final book = await BiliApi.instance.detail(LocalBiliFixture.concert, mode: mode);
      expect(await player.playBook(book, resumeIndex: 1, resumeMs: 12000), isTrue);
      final start = player.currentPosition;
      await _until(tester,
          () => player.currentPosition > start + const Duration(seconds: 1),
          'real native advancement');
      await player.pause();
      player.flushProgress();
      expect(shelf.recentBooks.single.book.bvid, book.bvid);
      expect(shelf.isOnShelf(book.bvid), isFalse);
      await player.seek(Duration.zero);
      player.flushProgress();
      expect(shelf.recentBooks.single.book.bvid, book.bvid);
      await player.clearListeningRecord(book.bvid);
      await tester.pump(const Duration(seconds: 3));
      expect(shelf.recentBooks, isEmpty);
      expect(shelf.progressByBvid(book.bvid), isNull);
    });
  }

  for (final action in ['stop', 'resume']) {
  testWidgets(
    'failed native reconnect followed by $action preserves stable checkpoint',
    (tester) async {
      final book = await BiliApi.instance.detail(LocalBiliFixture.concert,
          mode: ContentMode.concert);
      expect(await player.playBook(book, resumeMs: 20000), isTrue);
      final start = player.currentPosition;
      await _until(tester,
          () => player.currentPosition > start + const Duration(seconds: 1),
          'real playback before checkpoint');
      await player.pause();
      expect(shelf.progressByBvid(book.bvid)?.positionMs,
          greaterThanOrEqualTo(19000));
      fixture.mediaAvailable = false;
      final reconnect = fixture.gatePlayUrl(LocalBiliFixture.cid(book.bvid, 1));
      final native = player.player.platform!;
      // Exercise the real native reopen/failure path; only its trigger is synthetic.
      // ignore: invalid_use_of_protected_member
      native.errorController.add('fixture reconnect trigger');
      await reconnect.entered.future.timeout(const Duration(seconds: 15));
      expect(player.loading, isTrue);
      reconnect.release();
      await _until(tester, () => !player.loading && player.error != null,
          'native reconnect candidates fail');
      expect(player.currentPosition, Duration.zero,
          reason: 'Failed native reopen/stop must actually reset the position.');
      if (action == 'stop') {
        await player.stop();
        expect(shelf.progressByBvid(book.bvid)?.positionMs,
            greaterThanOrEqualTo(19000),
            reason: 'A failed replacement must not make native zero saveable.');
      } else {
        fixture.mediaAvailable = true;
        await player.resume();
        expect(player.isPlaying, isTrue);
        expect(player.currentPosition.inMilliseconds,
            greaterThanOrEqualTo(19000),
            reason: 'Resume must use the stable session position, not native zero.');
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  }

  testWidgets(
    'old completed seek acknowledgement cannot pause or advance new selection',
    (tester) async {
      final first = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
      final second = await BiliApi.instance.detail(LocalBiliFixture.concert,
          mode: ContentMode.concert);
      await shelf.add(second);
      expect(await player.playBook(first, resumeMs: 87000), isTrue);
      await player.pause();
      await player.seek(const Duration(seconds: 89));
      player.setStopAtChapterEnd(true);
      final native = player.player.platform!;
      originalPlatform = native;
      final gate = _SeekAcknowledgementGate(native);
      seekGate = gate;
      player.player.platform = gate;
      // The real native seek runs before the gate delays its acknowledgement.
      // ignore: invalid_use_of_protected_member
      native.completedController.add(true);
      await gate.entered.future.timeout(const Duration(seconds: 15));
      player.player.platform = native;
      expect(await player.playBook(second, resumeMs: 12000), isTrue);
      player.flushProgress();
      final cid = LocalBiliFixture.cid(second.bvid, 1);
      expect(shelf.progressByBvid(second.bvid)?.lastCid, cid);
      gate.unblock();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 2)));
      await tester.pump();
      expect(player.isPlaying, isTrue,
          reason: 'Completion of A must not cancel the newer request to play B.');
      expect(shelf.progressByBvid(second.bvid)?.lastCid, cid,
          reason: 'Completion of A must not advance B to an unheard chapter.');
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

// Delegate native state/streams; only delay completion of an already issued seek.
class _SeekAcknowledgementGate extends Fake implements PlatformPlayer {
  _SeekAcknowledgementGate(this.native);
  final PlatformPlayer native;
  final entered = Completer<void>();
  final _released = Completer<void>();

  @override
  PlayerState get state => native.state;

  @override
  PlayerStream get stream => native.stream;

  @override
  Future<void> seek(Duration position) async {
    await native.seek(position);
    if (!entered.isCompleted) entered.complete();
    await _released.future;
  }

  void unblock() {
    if (!_released.isCompleted) _released.complete();
  }
}
