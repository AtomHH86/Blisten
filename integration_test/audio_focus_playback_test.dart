import 'dart:async';
import 'dart:io';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/player/playback_preferences.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:flutter/services.dart';
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
  const focusChannel = MethodChannel('abts/audio_focus');
  const eventChannel = 'abts/audio_focus_events';
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String focusResult = 'granted';
  int requestId = 0;
  Completer<void>? requested;
  Completer<Object?>? focusReply;

  Future<void> focusEvent(String event, {int? id}) async {
    await messenger.handlePlatformMessage(eventChannel,
        const StandardMethodCodec().encodeSuccessEnvelope(
            requestId == 0 ? event :
            {'event': event, 'requestId': id ?? requestId}), (_) {});
  }


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
      messenger.setMockMethodCallHandler(focusChannel, (call) async {
        if (call.method == 'request') {
          final args = call.arguments;
          if (args is Map) requestId = (args['requestId'] as int?) ?? requestId;
          if (requested != null && !requested!.isCompleted) requested!.complete();
          return focusReply == null ? focusResult : await focusReply!.future;
        }
        return true;
      });
      player.setup();
    }, timeout: const Duration(seconds: 60)),
  );

  setUp(
    () => guardedHook('playback review case setup', () async {
      focusResult = 'granted';
      requested = null;
      focusReply = null;
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
      if (focusReply != null && !focusReply!.isCompleted) focusReply!.complete('failed');
      await player.pause();
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
      messenger.setMockMethodCallHandler(focusChannel, null);
      await fixture.close();
      HttpOverrides.global = null;
    }),
  );

  testWidgets('failed focus never starts native audio', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.concert,
        mode: ContentMode.concert);
    focusResult = 'failed';
    expect(await player.playBook(book), isTrue);
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    expect(player.isPlaying, isFalse);
    expect(player.currentPosition.inMilliseconds, lessThan(500));
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('delayed focus waits for grant before native audio starts', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.concert,
        mode: ContentMode.concert);
    focusResult = 'delayed';
    requested = Completer<void>();
    final load = player.playBook(book);
    pending = load;
    await requested!.future.timeout(const Duration(seconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    expect(player.isPlaying, isFalse);
    await focusEvent('gained');
    expect(await load.timeout(const Duration(seconds: 20)), isTrue);
    pending = null;
    await _until(tester, () => player.isPlaying, 'focus grant starts audio');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('pause cancels delayed focus and ignores a late grant', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.music,
        mode: ContentMode.music);
    focusResult = 'delayed';
    requested = Completer<void>();
    final load = player.playBook(book);
    pending = load;
    await requested!.future.timeout(const Duration(seconds: 20));
    final oldRequest = requestId;
    await player.pause();
    await focusEvent('gained', id: oldRequest);
    await load.timeout(const Duration(seconds: 20));
    pending = null;
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    expect(player.isPlaying, isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('loss before a granted request reply still blocks audio until gain', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
    focusReply = Completer<Object?>();
    requested = Completer<void>();
    final load = player.playBook(book);
    pending = load;
    await requested!.future.timeout(const Duration(seconds: 20));
    await focusEvent('interrupted');
    focusReply!.complete('granted');
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    expect(player.isPlaying, isFalse,
        reason: 'A late request reply cannot erase a newer focus loss.');
    await focusEvent('gained');
    expect(await load.timeout(const Duration(seconds: 20)), isTrue);
    pending = null;
    expect(player.isPlaying, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('stop cancels delayed focus and ignores its late grant', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.concert,
        mode: ContentMode.concert);
    focusResult = 'delayed';
    requested = Completer<void>();
    final load = player.playBook(book);
    pending = load;
    await requested!.future.timeout(const Duration(seconds: 20));
    final oldRequest = requestId;
    await player.stop();
    await focusEvent('gained', id: oldRequest);
    expect(await load.timeout(const Duration(seconds: 20)), isFalse);
    pending = null;
    expect(player.loaded, isFalse);
    expect(player.isPlaying, isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('old delayed grant cannot release a newer resource request', (tester) async {
    final first = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
    final second = await BiliApi.instance.detail(LocalBiliFixture.concert,
        mode: ContentMode.concert);
    focusResult = 'delayed';
    requested = Completer<void>();
    final oldLoad = player.playBook(first);
    pending = oldLoad;
    await requested!.future.timeout(const Duration(seconds: 20));
    final oldRequest = requestId;
    requested = Completer<void>();
    final newLoad = player.playBook(second);
    pending = newLoad;
    await requested!.future.timeout(const Duration(seconds: 20));
    await focusEvent('gained', id: oldRequest);
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    expect(player.isPlaying, isFalse);
    await focusEvent('gained');
    expect(await newLoad.timeout(const Duration(seconds: 20)), isTrue);
    pending = null;
    expect(await oldLoad.timeout(const Duration(seconds: 20)), isFalse);
    expect(player.book?.bvid, second.bvid);
    expect(player.isPlaying, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('speech pauses on duck and resumes only while intent remains', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
    expect(await player.playBook(book), isTrue);
    await _until(tester, () => player.isPlaying, 'speech playing');
    await focusEvent('ducked');
    await _until(tester, () => !player.isPlaying, 'speech pauses rather than ducks');
    await focusEvent('gained');
    await _until(tester, () => player.isPlaying, 'speech restores after interruption');
    await focusEvent('interrupted');
    await _until(tester, () => !player.isPlaying, 'transient loss pauses');
    await player.pause();
    await focusEvent('gained');
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    expect(player.isPlaying, isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('music ducks volume and restores without pausing', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.music,
        mode: ContentMode.music);
    expect(await player.playBook(book), isTrue);
    final volume = player.player.state.volume;
    await focusEvent('ducked');
    await _until(tester, () => player.player.state.volume < volume, 'music ducks');
    expect(player.isPlaying, isTrue);
    await focusEvent('gained');
    await _until(tester, () => player.player.state.volume >= volume - 1, 'music restores');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('new immediate grant restores volume after duck then user pause', (tester) async {
    final first = await BiliApi.instance.detail(LocalBiliFixture.music,
        mode: ContentMode.music);
    final second = await BiliApi.instance.detail(LocalBiliFixture.concert,
        mode: ContentMode.concert);
    expect(await player.playBook(first), isTrue);
    final normalVolume = player.player.state.volume;
    await focusEvent('ducked');
    await _until(tester, () => player.player.state.volume < normalVolume, 'music ducks before pause');
    await player.pause();
    expect(await player.playBook(second), isTrue);
    expect(player.isPlaying, isTrue);
    expect(player.player.state.volume, closeTo(normalVolume, 1),
        reason: 'A fresh granted request must not inherit the old resource duck volume.');
  }, timeout: const Timeout(Duration(minutes: 2)));

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
