import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/player/bili_audio_handler.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/player/playback_preferences.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/checked_hooks.dart';
import 'support/local_bili_fixture.dart';

/// Run seed, then verify in two separate `flutter drive --keep-app-running` Android launches.
/// The verify phase never clears or seeds application settings/progress.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('ABTS_RESTART_PHASE');
  const marker = 'integration_restart_seed';
  const samples = [
    (
      id: LocalBiliFixture.audiobook,
      mode: ContentMode.audiobook,
      rate: 1.5,
      seconds: 14,
    ),
    (
      id: LocalBiliFixture.music,
      mode: ContentMode.music,
      rate: 0.75,
      seconds: 18,
    ),
    (
      id: LocalBiliFixture.concert,
      mode: ContentMode.concert,
      rate: 1.25,
      seconds: 22,
    ),
    (
      id: LocalBiliFixture.children,
      mode: ContentMode.children,
      rate: 1.75,
      seconds: 26,
    ),
  ];
  final fixture = LocalBiliFixture();
  late BookPlayer player;
  late SharedPreferences prefs;
  final shelf = ShelfStore.instance;

  setUpAll(
    () => guardedHook('restart setUpAll', () async {
      final setupClock = Stopwatch()..start();
      expect(Platform.isAndroid, isTrue);
      expect(
        phase,
        isIn(['seed', 'verify']),
        reason: 'Pass --dart-define=ABTS_RESTART_PHASE=seed or verify.',
      );
      await fixture.start();
      debugPrint(
        '[restart $phase setup] fixture ready (${setupClock.elapsedMilliseconds}ms)',
      );
      HttpOverrides.global = fixture;
      MediaKit.ensureInitialized();
      prefs = await SharedPreferences.getInstance();
      if (phase == 'seed') await prefs.clear();
      await BiliClient.instance.initLocal();
      await shelf.load();
      await CacheStore.instance.load();
      debugPrint(
        '[restart $phase setup] prefs/stores ready (${setupClock.elapsedMilliseconds}ms)',
      );
      player = BookPlayer.instance;
      await fixture.configurePlayer(player.player);
      player.setup();
      debugPrint(
        '[restart $phase setup] player configured (${setupClock.elapsedMilliseconds}ms)',
      );
      final handler = await AudioService.init(
        builder: BiliAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.bting.audio.channel.audio',
          androidNotificationChannelName: 'B听',
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
        ),
      );
      player.attachHandler(handler);
      debugPrint(
        '[restart $phase setup] audio service ready (${setupClock.elapsedMilliseconds}ms)',
      );
    }, timeout: const Duration(seconds: 90)),
  );

  tearDownAll(
    () => guardedHook('restart tearDownAll', () async {
      await player.pause();
      await player.stop();
      expect(fixture.unexpectedRequests, isEmpty);
      await fixture.close();
      HttpOverrides.global = null;
    }),
  );

  testWidgets(
    'process restart $phase preserves mode, rate and selection policy',
    (tester) async {
      // Catches in-memory-only settings/progress and incorrect startup mode
      // defaults. A different Android PID is required before any verify playback.
      if (phase == 'seed') {
        for (final sample in samples) {
          final book = await BiliApi.instance.detail(
            sample.id,
            mode: sample.mode,
          );
          expect(await player.playBook(book, resume: false), isTrue);
          await player.setRate(sample.rate);
          await player.playChapterIndex(2);
          await _until(
            tester,
            () => player.currentDuration.inSeconds >= 89,
            'duration',
          );
          await player.seek(Duration(seconds: sample.seconds));
          await _until(
            tester,
            () => player.currentPosition.inSeconds >= sample.seconds - 1,
            'seed position for ${sample.mode.name}',
          );
          // A seek establishes an offset, not heard history.
          final observed = player.currentPosition;
          final target = Duration(seconds: sample.seconds);
          final sought = observed > target ? observed : target;
          await _until(
            tester,
            () => player.isPlaying && !player.buffering &&
                player.currentPosition > sought + const Duration(seconds: 1),
            'real seed playback for ${sample.mode.name}',
          );
          await player.pause();
          await _until(tester, () {
            final rows =
                jsonDecode(prefs.getString('abts_recent_progress') ?? '[]')
                    as List;
            return rows.any(
              (row) =>
                  row['book']['bvid'] == sample.id &&
                  row['lastChapterIndex'] == 2 &&
                  row['positionMs'] >= (sample.seconds - 1) * 1000,
            );
          }, 'native progress persistence');
        }
        await prefs.setString(
          marker,
          jsonEncode({'pid': pid, 'phase': 'seed'}),
        );
        await prefs.reload();
        expect(prefs.getString(marker), isNotNull);
        return;
      }

      final raw = prefs.getString(marker);
      expect(
        raw,
        isNotNull,
        reason: 'Run the seed process first without clearing app data.',
      );
      final seed = jsonDecode(raw!) as Map;
      expect(
        pid,
        isNot(seed['pid']),
        reason: 'Verify must run in a newly launched Android process.',
      );
      for (final sample in samples) {
        final saved = shelf.progressByBvid(sample.id);
        expect(
          saved,
          isNotNull,
          reason: '${sample.mode.name} persisted across process restart',
        );
        expect(saved!.book.contentMode, sample.mode);
        expect(saved.lastChapterIndex, 2);
        expect(saved.lastCid, LocalBiliFixture.cid(sample.id, 3));
        expect(
          saved.positionMs,
          inInclusiveRange(
            (sample.seconds - 1) * 1000,
            (sample.seconds + 4) * 1000,
          ),
        );
        expect(await PlaybackPreferences().rateFor(sample.mode), sample.rate);
        expect(await player.resumeShelf(saved), isTrue);
        await _until(
          tester,
          () => player.isPlaying && player.currentPosition > Duration.zero,
          'native playback after process restart',
        );
        expect(player.rate, sample.rate);
        expect(player.player.state.rate, closeTo(sample.rate, 0.01));
        if (sample.mode == ContentMode.music) {
          expect(player.index, 0);
          expect(player.currentPosition.inMilliseconds, lessThan(3000));
        } else {
          expect(player.index, 2);
          expect(
            player.currentPosition.inMilliseconds,
            inInclusiveRange(
              (sample.seconds - 1) * 1000,
              (sample.seconds + 6) * 1000,
            ),
          );
        }
        await player.pause();
      }
    },
  );
}

Future<void> _until(
  WidgetTester tester,
  bool Function() predicate,
  String reason,
) async {
  final clock = Stopwatch()..start();
  while (!predicate() && clock.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(predicate(), isTrue, reason: 'Timed out waiting for $reason');
}
