import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/follow_store.dart';
import 'package:blisten/core/storage/search_history_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/book_detail_page.dart';
import 'package:blisten/pages/cache_page.dart';
import 'package:blisten/pages/home_shell.dart';
import 'package:blisten/pages/player_page.dart';
import 'package:blisten/pages/search_page.dart';
import 'package:blisten/player/bili_audio_handler.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/player/playback_preferences.dart';
import 'package:blisten/services/auth_store.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:audio_service/audio_service.dart';
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
  late BookPlayer player;
  late BiliAudioHandler handler;
  late SharedPreferences prefs;
  final shelf = ShelfStore.instance;
  final cache = CacheStore.instance;

  setUpAll(
    () => guardedHook('audio modes setUpAll', () async {
      final setupClock = Stopwatch()..start();
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'Run this suite on an Android device.',
      );
      await fixture.start();
      debugPrint(
        '[native setup] fixture ready (${setupClock.elapsedMilliseconds}ms)',
      );
      HttpOverrides.global = fixture;
      MediaKit.ensureInitialized();
      prefs = await SharedPreferences.getInstance();
      // This suite runs in its own emulator app sandbox, using native storage.
      await prefs.clear();
      await BiliClient.instance.initLocal();
      await shelf.load();
      await cache.load();
      await cache.clearAll();
      await SearchHistoryStore.instance.load();
      await FollowStore.instance.load();
      await LoginStore.instance.load();
      debugPrint(
        '[native setup] prefs/stores ready (${setupClock.elapsedMilliseconds}ms)',
      );
      player = BookPlayer.instance;
      await fixture.configurePlayer(player.player);
      player.setup();
      debugPrint(
        '[native setup] player configured (${setupClock.elapsedMilliseconds}ms)',
      );
      handler = await AudioService.init(
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
        '[native setup] audio service ready (${setupClock.elapsedMilliseconds}ms)',
      );
    }, timeout: const Duration(seconds: 90)),
  );

  setUp(
    () => guardedHook('audio modes setUp', () async {
      fixture.mediaAvailable = true;
      fixture.apiAvailable = true;
      for (final mode in ContentMode.values) {
        await PlaybackPreferences().saveRate(mode, 1);
      }
    }),
  );

  tearDown(
    () => guardedHook('audio modes tearDown', () async {
      await player.pause();
      await player.stop();
      expect(
        fixture.unexpectedRequests,
        isEmpty,
        reason:
            'Deterministic tests must not contact unapproved external services.',
      );
    }),
  );

  tearDownAll(
    () => guardedHook('audio modes tearDownAll', () async {
      await fixture.close();
      HttpOverrides.global = null;
    }),
  );

  testWidgets(
    'native mode switching preserves independent rates and media controls',
    (tester) async {
      // Catches a shared rate key, omitted native setRate after open, or a broken
      // audio_service -> BookPlayer pause/play/seek bridge.
      final audiobook = await _detail(
        LocalBiliFixture.audiobook,
        ContentMode.audiobook,
      );
      final music = await _detail(LocalBiliFixture.music, ContentMode.music);
      final children = await _detail(LocalBiliFixture.children,
          ContentMode.children);
      final concert = await _detail(
        LocalBiliFixture.concert,
        ContentMode.concert,
      );
      for (final sample in [
        (book: audiobook, rate: 1.5),
        (book: music, rate: 0.75),
        (book: children, rate: 1.75),
        (book: concert, rate: 1.25),
      ]) {
        expect(await player.playBook(sample.book, resume: false), isTrue);
        await _playing(tester, player);
        expect(player.rate, 1);
        await player.setRate(sample.rate);
        await _until(
          tester,
          () => (player.player.state.rate - sample.rate).abs() < 0.01,
          'native rate ${sample.rate}',
        );
      }
      for (final sample in [
        (book: audiobook, rate: 1.5),
        (book: music, rate: 0.75),
        (book: children, rate: 1.75),
        (book: concert, rate: 1.25),
      ]) {
        expect(await player.playBook(sample.book, resume: false), isTrue);
        await _playing(tester, player);
        expect(player.rate, sample.rate);
        expect(player.player.state.rate, closeTo(sample.rate, 0.01));
      }
      await handler.seek(const Duration(seconds: 18));
      await _until(
        tester,
        () => player.currentPosition.inSeconds >= 17,
        'native seek',
      );
      await handler.pause();
      await _until(
        tester,
        () => !player.isPlaying && !handler.playbackState.value.playing,
        'media session pause',
      );
      // Native playing=false can arrive before the final queued position event.
      // Establish two stable observations before measuring the paused interval.
      var paused = player.currentPosition;
      var stableObservations = 0;
      for (var attempt = 0; attempt < 10 && stableObservations < 2; attempt++) {
        await tester.pump(const Duration(milliseconds: 300));
        final observed = player.currentPosition;
        stableObservations = observed == paused ? stableObservations + 1 : 0;
        paused = observed;
      }
      expect(
        stableObservations,
        2,
        reason: 'Native paused position must settle.',
      );
      await tester.pump(const Duration(milliseconds: 650));
      expect(
        player.currentPosition,
        paused,
        reason: 'Native position must not advance while paused.',
      );
      await handler.play();
      await _until(
        tester,
        () =>
            player.currentPosition > paused + const Duration(milliseconds: 300),
        'resume advances from paused position',
      );
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.mediaItem.value?.id, '${LocalBiliFixture.concert}/301');
      expect(handler.mediaItem.value?.title, contains('第 1 段'));
    },
  );

  testWidgets(
    'long-form modes restore the saved part and timestamp from native storage',
    (tester) async {
      // Catches lost progress writes, wrong cid/index, or resetting long content.
      for (final sample in [
        (id: LocalBiliFixture.audiobook, mode: ContentMode.audiobook),
        (id: LocalBiliFixture.concert, mode: ContentMode.concert),
        (id: LocalBiliFixture.children, mode: ContentMode.children),
      ]) {
        final book = await _detail(sample.id, sample.mode);
        expect(await player.playBook(book, resume: false), isTrue);
        await player.playChapterIndex(1);
        await _playing(tester, player);
        await player.seek(const Duration(seconds: 24));
        await _until(
          tester,
          () => player.currentPosition.inSeconds >= 23,
          'seek before saving',
        );
        await player.pause();
        final savedAt = player.currentPosition.inMilliseconds;
        await _persistedProgress(tester, prefs, sample.id, minMs: 23000);
        // Reloads through Android SharedPreferences; not an app process restart.
        await prefs.reload();
        await shelf.load();
        final saved = shelf.progressByBvid(sample.id)!;
        expect(saved.lastChapterIndex, 1);
        expect(saved.lastCid, LocalBiliFixture.cid(sample.id, 2));
        expect(saved.book.contentMode, sample.mode);
        expect(saved.positionMs, closeTo(savedAt, 1500));
        expect(await player.resumeShelf(saved), isTrue);
        await _playing(tester, player);
        expect(player.index, 1);
        expect(
          player.currentPosition.inMilliseconds,
          inInclusiveRange(23000, 28500),
        );
        await player.pause();
        if (sample.mode == ContentMode.children) {
          await player.playChapterIndex(2);
          await _playing(tester, player);
          expect(player.index, 2);
          expect(player.currentPosition.inMilliseconds, lessThan(3000));
          expect(shelf.isOnShelf(sample.id), isFalse);
        }
      }
    },
  );

  testWidgets(
    'song pause resumes but reselecting a multi-P song restarts its first part',
    (tester) async {
      // Catches applying song restart to pause/resume, and retaining a saved
      // timestamp/part when a whole song is selected again.
      final book = await _detail(LocalBiliFixture.music, ContentMode.music);
      expect(await player.playBook(book, resume: false), isTrue);
      await player.playChapterIndex(2);
      await _playing(tester, player);
      await player.seek(const Duration(seconds: 20));
      await _until(
        tester,
        () => player.currentPosition.inSeconds >= 19,
        'song seek',
      );
      await player.pause();
      final paused = player.currentPosition;
      await player.resume();
      await _until(
        tester,
        () =>
            player.currentPosition > paused + const Duration(milliseconds: 250),
        'song pause/resume keeps the position',
      );
      expect(player.index, 2);
      await player.pause();
      await _persistedProgress(tester, prefs, book.bvid, minMs: 19000);
      await prefs.reload();
      await shelf.load();
      final saved = shelf.progressByBvid(book.bvid)!;
      expect(saved.lastChapterIndex, 2);
      expect(await player.playBookWithFallback(saved), ShelfPlayOutcome.ok);
      await _playing(tester, player);
      expect(player.index, 0);
      expect(player.currentPosition.inMilliseconds, lessThan(3000));
      // Explicit multi-P selection still opens the requested song, at its start.
      await player.playChapterIndex(1);
      await _playing(tester, player);
      expect(player.index, 1);
      expect(player.currentPosition.inMilliseconds, lessThan(3000));
    },
  );

  for (final mode in [ContentMode.concert, ContentMode.children]) {
  testWidgets(
    'queued ${mode.name} cache survives index reload and plays offline with its mode',
    (tester) async {
      // Catches contentMode lost by queue -> download -> JSON -> cache playback,
      // or offline playback secretly requiring a reachable streaming server.
      final book = await _detail(mode.name == 'children'
          ? LocalBiliFixture.children : LocalBiliFixture.cached, mode);
      final chapter = book.chapters![1];
      await PlaybackPreferences().saveRate(mode, 1.25);
      await cache.enqueue(
        bvid: book.bvid,
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
        () => cache.isCached(book.bvid, chapter.cid) && !cache.busy,
        'native cache queue completes',
        timeout: const Duration(seconds: 25),
      );
      await prefs.reload();
      await cache.load();
      final entry = cache.entriesOf(book.bvid).single;
      expect(entry.contentMode, mode);
      expect(entry.page, 2);
      final path = await cache.cacheFilePath(book.bvid, chapter.cid);
      expect(path, isNotNull);
      expect(await File(path!).length(), greaterThan(100000));
      fixture.mediaAvailable = false;
      fixture.apiAvailable = false;
      await tester.pumpWidget(_host(const CachePage(), player));
      await tester.tap(find.text(book.cleanTitle));
      await _until(
        tester,
        () => find.text(chapter.part).evaluate().isNotEmpty,
        'cache chapter sheet',
      );
      await tester.tap(find.text(chapter.part));
      await _until(
        tester,
        () => find.byType(PlayerPage).evaluate().isNotEmpty,
        'cache page opens player',
      );
      await _playing(tester, player);
      expect(player.book!.contentMode, mode);
      expect(player.currentChapter!.cid, mode.name == 'children' ? 902 : 502);
      expect(player.isOffline, isTrue);
      expect(player.playbackUrl, isNull);
      expect(player.player.state.rate, closeTo(1.25, 0.01));
      expect(shelf.isOnShelf(book.bvid), isFalse);
      await player.seek(const Duration(seconds: 12));
      await _until(
        tester,
        () => player.currentPosition.inSeconds >= 11,
        'offline seek',
      );
      await player.pause();
      final paused = player.currentPosition;
      await player.resume();
      await _until(
        tester,
        () =>
            player.currentPosition > paused + const Duration(milliseconds: 250),
        'offline pause/resume',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  }

  testWidgets(
    'discovery, search and Bili import preserve mode through real detail playback',
    (tester) async {
      // Catches mode dropped by navigation/import, a short-song audiobook filter,
      // or invalid p being silently accepted and persisted.
      await tester.pumpWidget(_host(const HomeShell(), player));
      await tester.tap(find.widgetWithText(NavigationDestination, '发现'));
      await _until(
        tester,
        () =>
            tester
                    .widget<NavigationBar>(find.byType(NavigationBar))
                    .selectedIndex ==
                1 &&
            find.text('本地有声小说测试').evaluate().isNotEmpty,
        'discovery tab and its fetched results',
      );
      await tester.tap(find.text('听歌').first);
      await _until(
        tester,
        () => find.text('本地三分钟歌曲').evaluate().isNotEmpty,
        'song discovery result',
      );
      await tester.tap(find.text('更多'));
      final searchPage = find.byType(SearchPage);
      await _until(
        tester,
        () =>
            searchPage.evaluate().isNotEmpty &&
            ModalRoute.of(tester.element(searchPage))!.animation!.isCompleted &&
            find
                .descendant(of: searchPage, matching: find.text('本地三分钟歌曲'))
                .evaluate()
                .isNotEmpty,
        'song search navigation',
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '听歌'))
            .selected,
        isTrue,
      );
      await tester.tap(
        find
            .descendant(of: searchPage, matching: find.byTooltip('添加 B 站资源'))
            .hitTestable(),
      );
      await _until(
        tester,
        () =>
            find.byType(AlertDialog).evaluate().isNotEmpty &&
            ModalRoute.of(
              tester.element(find.byType(AlertDialog)),
            )!.animation!.isCompleted,
        'import dialog',
      );
      final importDialog = find.byType(AlertDialog);
      final importField = find.descendant(
        of: importDialog,
        matching: find.byType(TextField),
      );
      final importSubmit = find.descendant(
        of: importDialog,
        matching: find.widgetWithText(FilledButton, '添加到收藏'),
      );
      await _enterImportLink(
        tester,
        importField,
        'https://www.bilibili.com/video/${LocalBiliFixture.imported}?p=9',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '听现场').last);
      await tester.pump();
      expect(tester.widget<FilledButton>(importSubmit).onPressed, isNotNull);
      await tester.tap(importSubmit.hitTestable());
      await _until(
        tester,
        () => find.text('链接中的分 P 不存在，请检查 p 参数').evaluate().isNotEmpty,
        'invalid part rejected',
      );
      expect(shelf.isOnShelf(LocalBiliFixture.imported), isFalse);
      await _enterImportLink(
        tester,
        importField,
        'https://www.bilibili.com/video/${LocalBiliFixture.imported}?p=2',
      );
      expect(tester.widget<FilledButton>(importSubmit).onPressed, isNotNull);
      await tester.tap(importSubmit.hitTestable());
      await _until(
        tester,
        () =>
            find.byType(BookDetailPage).evaluate().isNotEmpty &&
            ModalRoute.of(
              tester.element(find.byType(BookDetailPage)),
            )!.animation!.isCompleted,
        'import opens details',
      );
      expect(find.text('演唱会详情'), findsOneWidget);
      expect(
        shelf.byBvid(LocalBiliFixture.imported)!.book.contentMode,
        ContentMode.concert,
      );
      await tester.tap(find.text('播放第 2 段'));
      await _until(
        tester,
        () => find.byType(PlayerPage).evaluate().isNotEmpty && player.isPlaying,
        'imported part plays in native player',
      );
      expect(player.book!.bvid, LocalBiliFixture.imported);
      expect(player.book!.contentMode, ContentMode.concert);
      expect(player.currentChapter!.cid, 402);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _enterImportLink(
  WidgetTester tester,
  Finder field,
  String link,
) async {
  expect(tester.widget<TextField>(field).enabled, isTrue);
  // Submission disables the field and closes its native input connection.
  // A real tap reopens it; enterText alone can reuse a stale focusedEditable.
  await tester.ensureVisible(field);
  await _until(
    tester,
    () => field.hitTestable().evaluate().isNotEmpty,
    'import field is visible before editing',
  );
  await tester.tap(field.hitTestable());
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  await _until(
    tester,
    () => tester.widget<EditableText>(editable).focusNode.hasFocus,
    'import field receives focus',
  );
  await tester.enterText(field, link);
  await tester.pump();
  expect(
    tester.widget<TextField>(field).controller!.text,
    link,
    reason: 'Submit the edited link, not the previous invalid value.',
  );
  // Android can deliver SHOW after an immediate unfocus/HIDE. Observe the real
  // keyboard and its settled viewport before asking it to close.
  await _waitForImportKeyboard(tester, visible: true);
  FocusScope.of(tester.element(field)).unfocus();
  await tester.pump();
  await _waitForImportKeyboard(tester, visible: false);
  expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isFalse);
}

Future<void> _waitForImportKeyboard(
  WidgetTester tester, {
  required bool visible,
}) async {
  double? previousInset;
  final stable = Stopwatch();
  await _until(tester, () {
    final inset = tester.view.viewInsets.bottom;
    if ((visible ? inset <= 0 : inset != 0) || inset != previousInset) {
      previousInset = inset;
      stable
        ..reset()
        ..start();
      return false;
    }
    return stable.elapsed >= const Duration(milliseconds: 300);
  }, 'import keyboard ${visible ? 'opens' : 'closes'} and viewport settles');
}

Future<Book> _detail(String bvid, ContentMode mode) =>
    BiliApi.instance.detail(bvid, mode: mode);

Future<void> _playing(WidgetTester tester, BookPlayer player) async {
  try {
    await _until(
      tester,
      () =>
          player.loaded &&
          player.isPlaying &&
          player.currentDuration.inSeconds >= 89 &&
          player.currentPosition > Duration.zero,
      'native media decodes and advances',
    );
  } on TestFailure catch (error, stack) {
    Error.throwWithStackTrace(
      TestFailure(
        '$error\n'
        'bvid: ${player.book?.bvid}, loaded: ${player.loaded}, '
        'loading: ${player.loading}, isPlaying: ${player.isPlaying}, '
        'duration: ${player.currentDuration}, position: ${player.currentPosition}, '
        'error: ${player.error}\n'
        'nativeState: ${player.player.state}\n'
        'lifecycle: ${tester.binding.lifecycleState}, '
        'framesEnabled: ${tester.binding.framesEnabled}',
      ),
      stack,
    );
  }
}

Future<void> _until(
  WidgetTester tester,
  bool Function() predicate,
  String reason, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final clock = Stopwatch()..start();
  while (!predicate() && clock.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(predicate(), isTrue, reason: 'Timed out waiting for $reason');
}

Future<void> _persistedProgress(
  WidgetTester tester,
  SharedPreferences prefs,
  String bvid, {
  required int minMs,
}) async {
  await _until(tester, () {
    final rows = [
      ...jsonDecode(prefs.getString('abts_shelf') ?? '[]') as List,
      ...jsonDecode(prefs.getString('abts_recent_progress') ?? '[]') as List,
    ];
    return rows.any(
      (row) => row['book']['bvid'] == bvid && row['positionMs'] >= minMs,
    );
  }, 'persisted progress $bvid');
}

Widget _host(Widget child, BookPlayer player) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider.value(value: player),
    ChangeNotifierProvider.value(value: CacheStore.instance),
    ChangeNotifierProvider.value(value: SearchHistoryStore.instance),
    ChangeNotifierProvider.value(value: FollowStore.instance),
    ChangeNotifierProvider.value(value: LoginStore.instance),
  ],
  child: MaterialApp(theme: AppTheme.light(), home: child),
);
