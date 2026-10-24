import 'package:blisten/core/nav/home_tabs.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/follow_store.dart';
import 'package:blisten/pages/my_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/auth_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/pages/bookshelf_page.dart';
import 'package:blisten/pages/favorites_page.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends ChangeNotifier implements BookPlayer {
  @override
  Duration get sleepRemaining => Duration.zero;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ShelfStore.instance.load();
    HomeTabs.index.value = 0;
    HomeTabs.libraryView.value = LibraryView.favorites;
  });
  testWidgets('library has one fixed slot title row with selected semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: ShelfStore.instance,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const BookshelfPage(),
        ),
      ),
    );
    expect(find.text('收藏'), findsOneWidget);
    for (final label in ['收藏', '在听', '缓存', '关注']) {
      expect(find.text(label), findsOneWidget);
    }
    final selected = tester.widget<Semantics>(
      find.byKey(const ValueKey('library-tab-favorites')),
    );
    expect(selected.properties.selected, isTrue);
    expect(
      tester.getSize(find.byKey(const ValueKey('library-header'))).height,
      56,
    );
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    testWidgets(
      '320dp 200 percent header ${dark ? 'dark' : 'light'} keeps slots and avoids overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: ShelfStore.instance,
            child: MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              builder: (_, child) => MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 640),
                  textScaler: TextScaler.linear(2),
                ),
                child: child!,
              ),
              home: const BookshelfPage(),
            ),
          ),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('library-header'))).height,
          96,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'group order stays during edits and refreshes on reentry with fixed tie order',
    (tester) async {
      final shelf = ShelfStore.instance;
      Future<void> add(String id, ContentMode mode) => shelf.add(
        Book(bvid: id, aid: 1, title: id, pic: '', contentMode: mode),
      );
      await add('book', ContentMode.audiobook);
      await add('song1', ContentMode.music);
      await add('song2', ContentMode.music);
      Widget host(bool active) => ChangeNotifierProvider.value(
        value: shelf,
        child: MaterialApp(
          home: Scaffold(body: FavoritesPage(embedded: true, active: active)),
        ),
      );
      await tester.pumpWidget(host(true));
      double top(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(top('听歌 · 2 项收藏'), lessThan(top('听书 · 1 项收藏')));
      await add('book2', ContentMode.audiobook);
      await add('book3', ContentMode.audiobook);
      await tester.pump();
      expect(top('听歌 · 2 项收藏'), lessThan(top('听书 · 3 项收藏')));
      await tester.pumpWidget(host(false));
      await tester.pumpWidget(host(true));
      expect(top('听书 · 3 项收藏'), lessThan(top('听歌 · 2 项收藏')));
      await shelf.remove('book3');
      await tester.pumpWidget(host(false));
      await tester.pumpWidget(host(true));
      expect(top('听书 · 2 项收藏'), lessThan(top('听歌 · 2 项收藏')));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'My ordinary menus redirect to the same library views without pushing pages',
    (tester) async {
      final player = _Player();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: ShelfStore.instance),
            ChangeNotifierProvider.value(value: FollowStore.instance),
            ChangeNotifierProvider.value(value: CacheStore.instance),
            ChangeNotifierProvider.value(value: LoginStore.instance),
            ChangeNotifierProvider<BookPlayer>.value(value: player),
          ],
          child: const MaterialApp(home: MyPage()),
        ),
      );
      for (final entry in {
        '我的收藏': LibraryView.favorites,
        '最近收听': LibraryView.recent,
        '离线缓存': LibraryView.cache,
        '关注的 UP 主': LibraryView.following,
      }.entries) {
        HomeTabs.index.value = 2;
        await tester.ensureVisible(find.text(entry.key));
        await tester.tap(find.text(entry.key));
        await tester.pump();
        expect(HomeTabs.index.value, 0);
        expect(HomeTabs.libraryView.value, entry.value);
        expect(find.byType(MyPage), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'favorite move offers replay rules and preserves listening data',
    (tester) async {
      final shelf = ShelfStore.instance;
      await shelf.add(Book(bvid: 'move', aid: 1, title: '移动作品', pic: ''));
      await shelf.updateProgress(
        'move',
        cid: 10,
        chapterIndex: 0,
        positionMs: 1234,
        chapterDurationMs: 10000,
      );
      final heardAt = shelf.byBvid('move')!.lastListenedAt;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: shelf,
          child: const MaterialApp(home: FavoritesPage()),
        ),
      );
      await tester.longPress(find.text('移动作品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移动到其他频道'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('听歌：再次选择时从头播放'));
      await tester.pumpAndSettle();
      expect(shelf.books.length, 1);
      expect(shelf.byBvid('move')!.book.contentMode, ContentMode.music);
      expect(shelf.byBvid('move')!.positionMs, 1234);
      expect(shelf.byBvid('move')!.lastListenedAt, heardAt);
      expect(tester.takeException(), isNull);
    },
  );
  test('secondary navigation selects the requested library view', () {
    HomeTabs.index.value = 2;
    HomeTabs.openLibrary(LibraryView.recent);
    expect(HomeTabs.index.value, 0);
    expect(HomeTabs.libraryView.value, LibraryView.recent);
  });
}
