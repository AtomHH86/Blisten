import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:blisten/core/nav/home_tabs.dart';
import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/follow_store.dart';
import 'package:blisten/core/storage/search_history_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/core/theme/theme_controller.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/home_shell.dart';
import 'package:blisten/pages/player_page.dart';
import 'package:blisten/pages/search_page.dart';
import 'package:blisten/pages/splash_screen.dart';
import 'package:blisten/player/bili_audio_handler.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/auth_store.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:blisten/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/checked_hooks.dart';
import 'support/local_bili_fixture.dart';

// Real Android rendering and decoding, using explicitly local test resources.
// PNG capture is evidence for manual visual review, not a golden-image claim.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final fixture = LocalBiliFixture();
  final shelf = ShelfStore.instance;
  late BookPlayer player;
  late SharedPreferences prefs;

  setUpAll(
    () => guardedHook('visual setUpAll', () async {
      expect(Platform.isAndroid, isTrue);
      if (const bool.fromEnvironment('BLISTEN_EXPECT_NOTIFICATIONS_DENIED')) {
        expect(
          await Permission.notification.status,
          anyOf(PermissionStatus.denied, PermissionStatus.permanentlyDenied),
        );
      }
      await fixture.start();
      HttpOverrides.global = fixture;
      MediaKit.ensureInitialized();
      prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await BiliClient.instance.initLocal();
      await CacheStore.instance.load();
      await CacheStore.instance.clearAll();
      await SearchHistoryStore.instance.load();
      await FollowStore.instance.load();
      await LoginStore.instance.load();
      player = BookPlayer.instance;
      await fixture.configurePlayer(player.player);
      player.setup();
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
      await binding.convertFlutterSurfaceToImage();
    }, timeout: const Duration(seconds: 90)),
  );

  setUp(
    () => guardedHook('visual setUp', () async {
      await player.stop();
      await prefs.remove('abts_shelf');
      await prefs.remove('abts_recent_progress');
      await FollowStore.instance.remove(1);
      await shelf.load();
      HomeTabs.openLibrary(LibraryView.favorites);
    }),
  );

  tearDown(
    () => guardedHook('visual tearDown', () async {
      await player.stop();
      expect(fixture.unexpectedRequests, isEmpty);
    }),
  );
  tearDownAll(
    () => guardedHook('visual tearDownAll', () async {
      await fixture.close();
      HttpOverrides.global = null;
    }),
  );

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull, reason: name);
    await binding.takeScreenshot(name);
  }

  for (final dark in [false, true]) {
    final tone = dark ? 'dark' : 'light';
    testWidgets(
      '$tone brand, import, tabs and native playback remain coherent',
      (tester) async {
        addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
        AppTheme.mode = dark ? ThemeMode.dark : ThemeMode.light;
        await tester.pumpWidget(
          _host(const SplashScreen(), player, dark: dark),
        );
        await _until(
          tester,
          () => tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((image) => image.image != null),
          'mascot decoded',
        );
        await capture(tester, '$tone-splash');
        await tester.pumpWidget(_host(const HomeShell(), player, dark: dark));
        await tester.pump(const Duration(seconds: 1));
        await capture(tester, '$tone-empty-collection');
        expect(find.text('还没有收听内容'), findsOneWidget);
        final import = find.text('粘贴链接 / BV号');
        await tester.ensureVisible(import);
        await tester.tap(import);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('添加 B 站资源'), findsOneWidget);
        await capture(tester, '$tone-import');
        await tester.tap(find.text('取消'));
        await tester.pump(const Duration(milliseconds: 400));

        for (final item in [
          (LocalBiliFixture.audiobook, ContentMode.audiobook),
          (LocalBiliFixture.music, ContentMode.music),
          (LocalBiliFixture.concert, ContentMode.concert),
        ]) {
          await shelf.add(
            await BiliApi.instance.detail(item.$1, mode: item.$2),
          );
        }
        final music = shelf.byBvid(LocalBiliFixture.music)!.book;
        expect(await player.playBook(music, resumeIndex: 1), isTrue);
        await _until(
          tester,
          () => player.isPlaying && player.currentDuration.inSeconds >= 89,
          'native decode',
        );
        await capture(tester, '$tone-collection-playing');
        for (final view in LibraryView.values) {
          final tab = find.byKey(ValueKey('library-tab-${view.name}'));
          await tester.ensureVisible(tab);
          await tester.tap(tab);
          await capture(tester, '$tone-library-${view.name}-playing');
        }
        HomeTabs.openLibrary(LibraryView.favorites);
        await tester.pump(const Duration(milliseconds: 250));
        final position = player.currentPosition;
        await tester.tap(find.byType(MiniPlayer));
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.byType(PlayerPage), findsOneWidget);
        expect(
          player.index,
          1,
          reason: 'Opening the player must retain selected part.',
        );
        expect(player.currentPosition, greaterThanOrEqualTo(position));
        await capture(tester, '$tone-player');
        await tester.ensureVisible(find.byTooltip('返回上一页，继续收听'));
        await tester.tap(find.byTooltip('返回上一页，继续收听'));
        await tester.pump(const Duration(milliseconds: 450));
        expect(player.isPlaying, isTrue, reason: 'Back does not pause audio.');
        await tester.tap(find.widgetWithText(NavigationDestination, '发现'));
        await tester.pump(const Duration(seconds: 1));
        await capture(tester, '$tone-discover');
        await tester.tap(find.text('更多'));
        await _until(
          tester,
          () =>
              find.byType(SearchPage).evaluate().isNotEmpty &&
              find.text('本地有声小说测试').evaluate().isNotEmpty,
          'content search results',
        );
        await capture(tester, '$tone-search-categories');
        await tester.tap(find.widgetWithText(ChoiceChip, 'UP 主'));
        await _until(
          tester,
          () => find.text('本地测试 UP 主').evaluate().isNotEmpty,
          'independent UP results',
        );
        await capture(tester, '$tone-search-up');
        await tester.tap(find.widgetWithText(FilledButton, '关注'));
        await _until(
          tester,
          () =>
              FollowStore.instance.isFollowing(1) &&
              find.widgetWithText(FilledButton, '已关注').evaluate().isNotEmpty,
          'follow search result',
        );
        expect(find.byType(SearchPage), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, '已关注'));
        await _until(
          tester,
          () =>
              !FollowStore.instance.isFollowing(1) &&
              find.widgetWithText(FilledButton, '关注').evaluate().isNotEmpty,
          'unfollow search result',
        );
        await tester.tap(find.widgetWithText(ChoiceChip, '听歌'));
        await _until(
          tester,
          () =>
              !tester
                  .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'UP 主'))
                  .selected &&
              find.text('本地测试 UP 主').evaluate().isEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty,
          'return to content category',
        );
        await tester.tap(find.byTooltip('返回上一页'));
        await tester.pump(const Duration(milliseconds: 450));
        await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
        await tester.pump(const Duration(milliseconds: 300));
        await capture(tester, '$tone-my');
        expect(player.isPlaying, isTrue);
        expect(player.book?.bvid, music.bvid);
        final beforeTheme = player.currentPosition;
        final beforeUrl = player.playbackUrl;
        AppTheme.mode = dark ? ThemeMode.light : ThemeMode.dark;
        await tester.pumpWidget(_host(const HomeShell(), player, dark: !dark));
        await _until(
          tester,
          () =>
              Theme.of(
                tester.element(find.byType(HomeShell)),
              ).appBarTheme.iconTheme?.color ==
              AppTheme.textMain,
          'theme transition finishes',
        );
        await capture(tester, '$tone-theme-switch-playing');
        expect(player.isPlaying, isTrue);
        expect(player.index, 1);
        expect(player.playbackUrl, beforeUrl);
        expect(player.currentPosition, greaterThanOrEqualTo(beforeTheme));
        if (const bool.fromEnvironment('BLISTEN_EXPECT_NOTIFICATIONS_DENIED')) {
          expect(
            await Permission.notification.status,
            anyOf(PermissionStatus.denied, PermissionStatus.permanentlyDenied),
          );
        }
        await _until(
          tester,
          () => shelf.recentBooks.isNotEmpty,
          'actual recent preview',
        );
        await player.stop();
        await tester.pumpWidget(_host(const HomeShell(), player, dark: !dark));
        await capture(tester, '$tone-local-preview');
        final requests = fixture.playUrlRequests.length;
        final mediaRequests = fixture.mediaRequests.length;
        await tester.tap(find.byType(MiniPlayer));
        await tester.pump(const Duration(milliseconds: 450));
        await capture(tester, '$tone-silent-preview-page');
        expect(find.text('上次收听'), findsOneWidget);
        expect(
          find.textContaining(shelf.recentBooks.first.positionText),
          findsOneWidget,
        );
        expect(player.loaded, isFalse);
        expect(fixture.playUrlRequests.length, requests);
        expect(fixture.mediaRequests.length, mediaRequests);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('$tone 200% text keeps main tabs and player reachable', (
      tester,
    ) async {
      addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
      AppTheme.mode = dark ? ThemeMode.dark : ThemeMode.light;
      final book = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
      await shelf.add(book);
      expect(
        await player.playBook(book, resumeIndex: 1, resumeMs: 17000),
        isTrue,
      );
      await tester.pumpWidget(
        _host(const HomeShell(), player, dark: dark, scale: 2),
      );
      await capture(tester, '$tone-large-collection');
      await tester.tap(find.byType(MiniPlayer));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byType(PlayerPage), findsOneWidget);
      await capture(tester, '$tone-large-player');
      final pause = find.byTooltip('暂停');
      await tester.ensureVisible(pause);
      await tester.tap(pause);
      await _until(tester, () => !player.isPlaying, 'large text pause control');
      await capture(tester, '$tone-large-player-controls');
      await tester.ensureVisible(find.byTooltip('返回上一页，继续收听'));
      await tester.tap(find.byTooltip('返回上一页，继续收听'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
      await capture(tester, '$tone-large-my');
      for (final view in LibraryView.values) {
        HomeTabs.openLibrary(view);
        await capture(tester, '$tone-320dp-200-${view.name}-paused');
      }
      await tester.tap(find.widgetWithText(NavigationDestination, '发现'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('听歌').first);
      await _until(
        tester,
        () => find.text('本地三分钟歌曲').evaluate().isNotEmpty,
        'large text music discovery',
      );
      await tester.tap(find.text('更多'));
      await _until(
        tester,
        () =>
            find.byType(SearchPage).evaluate().isNotEmpty &&
            ModalRoute.of(
              tester.element(find.byType(SearchPage)),
            )!.animation!.isCompleted &&
            find.text('本地三分钟歌曲').evaluate().isNotEmpty,
        'large text content search',
      );
      await capture(tester, '$tone-large-search-categories');
      await tester.tap(find.widgetWithText(ChoiceChip, 'UP 主'));
      await _until(
        tester,
        () => find.text('本地测试 UP 主').evaluate().isNotEmpty,
        'large text UP search',
      );
      await capture(tester, '$tone-large-search-up');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Widget _host(
  Widget child,
  BookPlayer player, {
  required bool dark,
  double scale = 1,
}) => Center(
  child: SizedBox(
    width: scale > 1 ? 320 : double.infinity,
    height: scale > 1 ? 640 : double.infinity,
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ShelfStore.instance),
        ChangeNotifierProvider.value(value: player),
        ChangeNotifierProvider.value(value: CacheStore.instance),
        ChangeNotifierProvider.value(value: SearchHistoryStore.instance),
        ChangeNotifierProvider.value(value: FollowStore.instance),
        ChangeNotifierProvider.value(value: LoginStore.instance),
        ChangeNotifierProvider.value(value: ThemeController.instance),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: scale > 1
                ? const Size(320, 640)
                : MediaQuery.of(context).size,
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: KeyedSubtree(key: ValueKey('$dark-$scale'), child: child),
      ),
    ),
  ),
);

Future<void> _until(
  WidgetTester tester,
  bool Function() predicate,
  String reason,
) async {
  final clock = Stopwatch()..start();
  while (!predicate() && clock.elapsed < const Duration(seconds: 20)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(predicate(), isTrue, reason: reason);
}
