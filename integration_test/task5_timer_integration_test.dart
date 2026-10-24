// Move into integration_test/ only at the stage C checkpoint. Relative support
// imports intentionally target the existing integration_test/support helpers.
import 'dart:io';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/checked_hooks.dart';
import 'support/local_bili_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final fixture = LocalBiliFixture();
  late BookPlayer player;

  setUpAll(() => guardedHook('task5 timer setup', () async {
    expect(Platform.isAndroid, isTrue);
    await fixture.start();
    HttpOverrides.global = fixture;
    MediaKit.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await BiliClient.instance.initLocal();
    await ShelfStore.instance.load();
    await CacheStore.instance.load();
    await CacheStore.instance.clearAll();
    player = BookPlayer.instance;
    await fixture.configurePlayer(player.player);
    player.setup();
  }, timeout: const Duration(seconds: 60)));

  tearDown(() => guardedHook('task5 timer case cleanup', () async {
    player.cancelSleepTimer();
    await player.stop();
    fixture.releaseGates();
    expect(fixture.unexpectedRequests, isEmpty);
  }));

  tearDownAll(() => guardedHook('task5 timer cleanup', () async {
    await fixture.close();
    HttpOverrides.global = null;
  }));

  testWidgets('native expiry clears selection/deadline, pauses and does not pause again after explicit resume', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
    expect(await player.playBook(book), isTrue);
    await until(tester, () => player.isPlaying, 'native playback started');
    player.setSleepTimer(const Duration(seconds: 1));
    expect(player.sleepTimerDuration, const Duration(seconds: 1));
    expect(player.sleepTimerDeadline, isNotNull);
    await until(tester, () => player.sleepRemaining == Duration.zero && !player.isPlaying,
      'timer expired and native playback paused');
    expect(player.sleepTimerDuration, Duration.zero);
    expect(player.sleepTimerDeadline, isNull);
    await player.resume();
    await until(tester, () => player.isPlaying, 'explicit resume after expiry');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2300)));
    await tester.pump();
    expect(player.isPlaying, isTrue,
      reason: 'The old expired timer must be canceled, never repausing resumed playback.');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('cancel clears the timer without changing independent chapter-end setting', (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
    expect(await player.playBook(book), isTrue);
    player.setStopAtChapterEnd(true);
    player.setSleepTimer(const Duration(minutes: 20));
    expect(player.sleepTimerDuration, const Duration(minutes: 20));
    expect(player.sleepTimerDeadline, isNotNull);
    player.cancelSleepTimer();
    expect(player.sleepRemaining, Duration.zero);
    expect(player.sleepTimerDuration, Duration.zero);
    expect(player.sleepTimerDeadline, isNull);
    expect(player.stopAtChapterEnd, isTrue);
    player.setStopAtChapterEnd(false);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> until(WidgetTester tester, bool Function() ready, String label) async {
  final clock = Stopwatch()..start();
  while (!ready() && clock.elapsed < const Duration(seconds: 20)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  expect(ready(), isTrue, reason: label);
}
