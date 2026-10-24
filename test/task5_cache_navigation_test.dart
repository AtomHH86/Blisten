import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/cache_page.dart';
import 'package:blisten/pages/player_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// The real CacheStore reconciles an actual local media file in this fixture.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Stage C prerequisite: use the existing BookPlayer provider in the real sheet
// instead of directly reading its singleton. Production already provides the
// singleton; tests control only its asynchronous boundary. Routing stays real.
class _Player extends ChangeNotifier implements BookPlayer {
  final attempts = <Completer<CachePlayOutcome>>[];
  final requested = <({String bvid, int cid, ContentMode mode})>[];

  @override
  Future<CachePlayOutcome> playCachedEntry(String bvid, int cid, Book book) {
    requested.add((bvid: bvid, cid: cid, mode: book.contentMode));
    final result = Completer<CachePlayOutcome>();
    attempts.add(result);
    return result.future;
  }

  // The destination is the production PlayerPage. Its unloaded UI is enough
  // to verify route ownership without replacing navigation or native media.
  @override
  Book? get book => null;
  @override
  bool get loaded => false;
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  void flushProgress() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getExternalStoragePath() async => null;
}

class _Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  final popped = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => popped.add(route);
}

const _entry = CacheEntry(
  bvid: 'BV1CACHE00001', cid: 103, bookTitle: '缓存导航作品', chapterTitle: '第三段',
  contentMode: ContentMode.concert, page: 3, part: '第三段', order: 3,
);

void main() {
  final cache = CacheStore.instance;
  final shelf = ShelfStore.instance;

  Future<({GlobalKey<NavigatorState> navigator, _Routes routes})> showCache(
      WidgetTester tester, _Player player) async {
    final originalPaths = PathProviderPlatform.instance;
    late Directory root;
    SharedPreferences.setMockInitialValues({
      'abts_cache_index': jsonEncode([_entry.toJson()]),
      'abts_shelf': '[]', 'abts_recent_progress': '[]',
    });
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('blisten-cache-route-');
      PathProviderPlatform.instance = _Paths(root.path);
      final directory = await Directory('${root.path}/audio_cache').create();
      await File('test/fixtures/cache-silence.m4a').copy('${directory.path}/${_entry.fileName}');
      await cache.load();
      await shelf.load();
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await cache.clearAll();
        await root.delete(recursive: true);
        PathProviderPlatform.instance = originalPaths;
      });
      player.dispose();
    });
    final navigator = GlobalKey<NavigatorState>();
    final routes = _Routes();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: cache),
        ChangeNotifierProvider.value(value: shelf),
        ChangeNotifierProvider<BookPlayer>.value(value: player),
      ],
      child: MaterialApp(
        navigatorKey: navigator, navigatorObservers: [routes], theme: AppTheme.dark(),
        home: const CachePage(),
      ),
    ));
    await tester.tap(find.text(_entry.bookTitle));
    await tester.pumpAndSettle();
    expect(find.text(_entry.chapterTitle), findsOneWidget);
    expect(cache.entries, hasLength(1));
    return (navigator: navigator, routes: routes);
  }

  testWidgets('cache sheet double tap starts one operation and opens one player', (tester) async {
    final player = _Player();
    final host = await showCache(tester, player);
    await tester.tap(find.text(_entry.chapterTitle));
    await tester.pump();
    await tester.tap(find.text(_entry.chapterTitle));
    await tester.pump();
    expect(player.attempts, hasLength(1));
    expect(player.requested.single, (bvid: _entry.bvid, cid: _entry.cid, mode: ContentMode.concert));
    player.attempts.single.complete(CachePlayOutcome.okOffline);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(host.routes.pushed, hasLength(3)); // home, sheet, player
    expect(host.routes.popped, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final dismiss in [true, false]) {
    testWidgets('cache completion leaves a newer route intact after ${dismiss ? 'dismissed' : 'covered'} sheet', (tester) async {
      final player = _Player();
      final host = await showCache(tester, player);
      await tester.tap(find.text(_entry.chapterTitle));
      await tester.pump();
      expect(player.attempts, hasLength(1));
      if (dismiss) {
        await tester.tapAt(const Offset(20, 80)); // actual modal barrier
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
      }
      final newer = MaterialPageRoute<void>(builder: (_) => const Scaffold(
        body: Center(child: Text('后来打开的页面')),
      ));
      unawaited(host.navigator.currentState!.push(newer));
      await tester.pumpAndSettle();
      final pushCount = host.routes.pushed.length;
      final popCount = host.routes.popped.length;
      player.attempts.single.complete(dismiss ? CachePlayOutcome.okOffline : CachePlayOutcome.failed);
      await tester.pumpAndSettle();
      expect(newer.isCurrent, isTrue);
      expect(find.text('后来打开的页面'), findsOneWidget);
      expect(find.byType(PlayerPage, skipOffstage: false), findsNothing);
      expect(host.routes.pushed, hasLength(pushCount));
      expect(host.routes.popped, hasLength(popCount));
      expect(find.textContaining('重试'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final outcome in [CachePlayOutcome.failed, CachePlayOutcome.fileMissing]) {
    testWidgets('cache ${outcome.name} result stays actionable on its sheet', (tester) async {
      final player = _Player();
      final host = await showCache(tester, player);
      await tester.tap(find.text(_entry.chapterTitle));
      player.attempts.single.complete(outcome);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.descendant(of: find.byType(BottomSheet), matching:
          find.textContaining(outcome == CachePlayOutcome.fileMissing ? '重新缓存' : '重试')), findsWidgets);
      expect(host.routes.popped, isEmpty);
      if (outcome == CachePlayOutcome.failed) {
        expect(cache.isCached(_entry.bvid, _entry.cid), isTrue);
      }
      expect(tester.takeException(), isNull);
      if (outcome == CachePlayOutcome.failed) {
        await tester.tap(find.text(_entry.chapterTitle));
        await tester.pump();
        expect(player.attempts, hasLength(2), reason: 'Failure must release the submit guard.');
        player.attempts.last.complete(CachePlayOutcome.okOffline);
        await tester.pumpAndSettle();
        expect(find.byType(PlayerPage), findsOneWidget);
      }
    });
  }

  testWidgets('thrown cache playback error is visible and permits retry', (tester) async {
    final player = _Player();
    await showCache(tester, player);
    await tester.tap(find.text(_entry.chapterTitle));
    player.attempts.single.completeError(StateError('synthetic playback failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet),
        matching: find.textContaining('重试')), findsWidgets);
    await tester.tap(find.text(_entry.chapterTitle));
    expect(player.attempts, hasLength(2));
    player.attempts.last.complete(CachePlayOutcome.okOffline);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
  });
}
