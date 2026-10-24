import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:blisten/pages/home_shell.dart';
import 'package:blisten/core/nav/home_tabs.dart';
import 'package:blisten/core/storage/follow_store.dart';
import 'package:blisten/core/storage/search_history_store.dart';
import 'package:blisten/core/theme/theme_controller.dart';
import 'package:blisten/services/auth_store.dart';

import 'package:provider/provider.dart';
import 'package:blisten/widgets/mini_player.dart';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/player/bili_audio_handler.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:audio_service/audio_service.dart';
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
  const marker = 'integration_library_preview_seed';
  const modeName = String.fromEnvironment(
    'ABTS_PREVIEW_MODE',
    defaultValue: 'music',
  );
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
      await FollowStore.instance.load();
      await SearchHistoryStore.instance.load();
      await LoginStore.instance.load();
      if (phase == 'seed') await CacheStore.instance.clearAll();
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

  testWidgets('cold process local preview $phase $modeName', (tester) async {
    final mode = modeName == 'music'
        ? ContentMode.music
        : ContentMode.audiobook;
    final id = mode == ContentMode.music
        ? LocalBiliFixture.music
        : LocalBiliFixture.audiobook;
    if (phase == 'seed') {
      final book = await BiliApi.instance.detail(id, mode: mode);
      expect(await player.playBook(book, resume: false), isTrue);
      await player.setRate(1);
      await player.playChapterIndex(1);
      await _until(
        tester,
        () => player.currentPosition.inSeconds >= 2,
        'actual heard',
      );
      await player.seek(const Duration(seconds: 18));
      await player.pause();
      await _until(
        tester,
        () =>
            shelf.recentBooks.isNotEmpty &&
            shelf.recentBooks.first.positionMs >= 17000,
        'saved checkpoint',
      );
      if (mode == ContentMode.audiobook) {
        final chapter = book.chapters![1];
        await CacheStore.instance.enqueue(
          bvid: id,
          bookTitle: book.cleanTitle,
          cover: '',
          contentMode: mode,
          items: [
            (
              cid: chapter.cid,
              chapterTitle: chapter.part,
              durationSec: 90,
              page: 2,
              part: chapter.part,
              order: 2,
            ),
          ],
          resolveUrl: player.resolveUrlFor,
          headers: player.downloadHeaders,
        );
        await _until(
          tester,
          () =>
              CacheStore.instance.isCached(id, chapter.cid) &&
              !CacheStore.instance.busy,
          'cold preview cache',
        );
      }
      await prefs.setString(marker, jsonEncode({'pid': pid, 'bvid': id}));
      return;
    }
    expect(jsonDecode(prefs.getString(marker)!)['pid'], isNot(pid));
    expect(shelf.recentBooks.first.book.bvid, id);
    expect(player.loaded, isFalse);
    expect(player.book, isNull);
    expect(player.player.state.playlist.medias, isEmpty);
    expect(fixture.playUrlRequests, isEmpty);
    expect(fixture.mediaRequests, isEmpty);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: shelf),
          ChangeNotifierProvider<BookPlayer>.value(value: player),
          ChangeNotifierProvider.value(value: CacheStore.instance),
          ChangeNotifierProvider.value(value: FollowStore.instance),
          ChangeNotifierProvider.value(value: SearchHistoryStore.instance),
          ChangeNotifierProvider.value(value: LoginStore.instance),
          ChangeNotifierProvider.value(value: ThemeController.instance),
        ],
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pumpAndSettle();
    for (final tab in [1, 2, 0]) {
      HomeTabs.switchTo(tab);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(player.loaded, isFalse);
      expect(fixture.playUrlRequests, isEmpty);
      expect(fixture.mediaRequests, isEmpty);
    }
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(player.loaded, isFalse);
    expect(player.player.state.playlist.medias, isEmpty);
    expect(fixture.playUrlRequests, isEmpty);
    expect(fixture.mediaRequests, isEmpty);
    await tester.ensureVisible(find.byTooltip('播放'));
    await tester.tap(find.byTooltip('播放'));
    await _until(
      tester,
      () => player.loaded && player.isPlaying,
      'explicit preview play',
    );
    expect(player.index, mode == ContentMode.music ? 0 : 1);
    expect(
      player.currentPosition.inSeconds,
      mode == ContentMode.music ? lessThan(4) : greaterThanOrEqualTo(17),
    );
    await player.pause();
    final before = player.currentPosition;
    player.togglePlay();
    await _until(tester, () => player.isPlaying, 'same session resumes');
    expect(
      player.currentPosition.inMilliseconds,
      greaterThanOrEqualTo(before.inMilliseconds - 500),
    );
    expect(shelf.books, isEmpty);
    if (mode == ContentMode.audiobook) expect(player.isOffline, isTrue);
  });
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
