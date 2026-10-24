import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/player/bili_audio_handler.dart';
import 'package:blisten/player/playback_preferences.dart';
import 'package:blisten/services/audio_focus.dart';
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
      final handler = await AudioService.init(
        builder: BiliAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.bting.audio.channel.audio',
          androidNotificationChannelName: 'B听焦点测试',
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
        ),
      );
      player.attachHandler(handler);
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
      // No Activity remains. Keep the paused media service/engine alive until
      // flutter drive receives the report; the external runner then force-stops.
      await player.pause();
      expect(fixture.unexpectedRequests, isEmpty);
    }, timeout: const Duration(seconds: 40)),
  );

  tearDownAll(
    () => guardedHook('playback review cleanup', () async {
      await fixture.close();
      HttpOverrides.global = null;
    }),
  );

  testWidgets('native noisy receiver survives finished Activity with media service', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.concert,
        mode: ContentMode.concert);
    expect(await player.playBook(book), isTrue);
    final before = player.currentPosition;
    final noisyReceived = Completer<void>();
    final previousNoisy = AudioFocus.instance.onNoisy;
    AudioFocus.instance.onNoisy = () {
      if (!noisyReceived.isCompleted) {
        // Observe the real native EventChannel and delegate the product behavior.
        // ignore: avoid_print
        print('BLISTEN_RECEIVED_NATIVE_NOISY');
        noisyReceived.complete();
      }
      previousNoisy?.call();
    };
    try {
      await SystemNavigator.pop();
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
      expect(player.isPlaying, isTrue);
      expect(player.currentPosition, greaterThan(before));
      // The external dedicated-emulator runner now sends the protected Android
      // broadcast as root. Do not replace it with a Dart callback/channel mock.
      // ignore: avoid_print
      print('BLISTEN_READY_FOR_NATIVE_NOISY');
      await tester.runAsync(
        () => noisyReceived.future.timeout(const Duration(seconds: 45)),
      );
      final paused = await tester.runAsync(() async {
        final clock = Stopwatch()..start();
        while (player.isPlaying && clock.elapsed < const Duration(seconds: 45)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        return !player.isPlaying;
      });
      expect(paused, isTrue, reason: 'Actual Android noisy broadcast must pause after Activity destruction.');
      await player.resume();
      expect(player.isPlaying, isTrue,
          reason: 'Engine-owned native focus channel must still work after Activity destruction.');
    } finally {
      AudioFocus.instance.onNoisy = previousNoisy;
    }
  }, timeout: const Timeout(Duration(minutes: 2)),
      skip: !const bool.fromEnvironment('BLISTEN_NATIVE_NOISY_PROBE'));
}
