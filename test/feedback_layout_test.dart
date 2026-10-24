import 'dart:ui' show Tristate;

import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/follow_store.dart';
import 'package:blisten/core/storage/search_history_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/models/up_user.dart';
import 'package:blisten/pages/discover_page.dart';
import 'package:blisten/pages/login_page.dart';
import 'package:blisten/pages/search_page.dart';
import 'package:blisten/services/auth_store.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:blisten/widgets/book_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LayoutApi implements BiliApi {
  int qrGenerations = 0;
  int searches = 0;

  Book _book(ContentMode mode) => Book(
    bvid: 'BVlayout',
    aid: 17,
    title: '适合闭眼收听的长标题作品：从第一章一直听到故事的结尾',
    author: '名字很长的测试作者与主播',
    pic: '',
    pages: 128,
    play: 1234567,
    contentMode: mode,
  );

  @override
  Future<List<Book>> rankHotNovel({int limit = 30}) async => [
    _book(ContentMode.audiobook),
    _book(ContentMode.audiobook),
  ];

  @override
  Future<List<Book>> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    String? order,
    Function(int total)? onFirstPage,
    Function(int rawCount)? onRawCount,
    ContentMode mode = ContentMode.audiobook,
  }) async {
    searches++;
    onFirstPage?.call(1);
    onRawCount?.call(1);
    return [_book(mode)];
  }

  @override
  Future<List<UpUser>> searchUser(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async => const [
    UpUser(
      mid: 17,
      name: '很长很长的创作者名称以及工作室',
      sign: '这是很长的个人简介与音乐创作故事',
      fans: 123,
    ),
  ];

  @override
  Future<({String url, String qrKey})> qrGenerate() async {
    qrGenerations++;
    return (url: 'https://example.com/qr', qrKey: 'layout');
  }

  @override
  Future<String> qrPoll(String key) async => 'waiting';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget page, Brightness brightness) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: CacheStore.instance),
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider.value(value: FollowStore.instance),
    ChangeNotifierProvider.value(value: SearchHistoryStore.instance),
    ChangeNotifierProvider.value(value: LoginStore.instance),
  ],
  child: MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(2)),
      child: child!,
    ),
    home: page,
  ),
);

void _narrowScreen(WidgetTester tester, Brightness brightness) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  AppTheme.mode = brightness == Brightness.dark
      ? ThemeMode.dark
      : ThemeMode.light;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(() => AppTheme.mode = ThemeMode.system);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'abts_shelf': '[]',
      'abts_follows': '[]',
    });
    await ShelfStore.instance.load();
    await FollowStore.instance.load();
    await SearchHistoryStore.instance.clear();
    await LoginStore.instance.load();
  });

  testWidgets(
    'discover and search report selected options to accessibility services',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final api = _LayoutApi();
        await tester.pumpWidget(_host(DiscoverPage(api: api), Brightness.dark));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        final category = find.byKey(const ValueKey('discover-category-1'));
        expect(
          tester.getSemantics(category).flagsCollection.isSelected !=
              Tristate.none,
          isTrue,
        );
        expect(
          tester.getSemantics(category).flagsCollection.isSelected ==
              Tristate.isTrue,
          isFalse,
        );
        expect(tester.getSemantics(category).flagsCollection.isButton, isTrue);
        await tester.ensureVisible(category);
        await tester.tap(category);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(category).flagsCollection.isSelected ==
              Tristate.isTrue,
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _host(SearchPage(api: api, initialKeyword: '语义测试'), Brightness.dark),
        );
        await tester.pumpAndSettle();
        final firstTab = find.byKey(
          const ValueKey('search-category-audiobook'),
        );
        final upTab = find.byKey(const ValueKey('search-category-up'));
        expect(
          tester.getSemantics(firstTab).flagsCollection.isSelected ==
              Tristate.isTrue,
          isTrue,
        );
        expect(
          tester.getSemantics(upTab).flagsCollection.isSelected !=
              Tristate.none,
          isTrue,
        );
        expect(
          tester.getSemantics(upTab).flagsCollection.isSelected ==
              Tristate.isTrue,
          isFalse,
        );
        expect(tester.getSemantics(upTab).flagsCollection.isButton, isTrue);
        await tester.tap(upTab);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(upTab).flagsCollection.isSelected ==
              Tristate.isTrue,
          isTrue,
        );
        expect(
          tester.getSemantics(firstTab).flagsCollection.isSelected ==
              Tristate.isTrue,
          isFalse,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'history delete has a named 48dp target and does not submit search',
    (tester) async {
      final api = _LayoutApi();
      const keyword = '等待删除的历史关键词';
      await SearchHistoryStore.instance.add(keyword);
      await tester.pumpWidget(_host(SearchPage(api: api), Brightness.dark));
      await tester.pumpAndSettle();
      final delete = find.byTooltip('删除搜索历史：$keyword');
      expect(delete, findsOneWidget);
      expect(tester.getSize(delete).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(delete).height, greaterThanOrEqualTo(48));
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(SearchHistoryStore.instance.items, isEmpty);
      expect(api.searches, 0);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'discover ${brightness.name} at 320dp and 200% keeps grid and category controls usable',
      (tester) async {
        _narrowScreen(tester, brightness);
        await tester.pumpWidget(
          _host(DiscoverPage(api: _LayoutApi()), brightness),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.byType(BookGridItem), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.drag(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is ListView &&
                    widget.scrollDirection == Axis.vertical,
              )
              .first,
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('听歌'));
        await tester.tap(find.text('听歌'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'search ${brightness.name} at 320dp and 200% retains editable input above keyboard',
      (tester) async {
        _narrowScreen(tester, brightness);
        await tester.pumpWidget(
          _host(
            SearchPage(api: _LayoutApi(), initialKeyword: '长标题搜索'),
            brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BookListTile), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(TextField));
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '修改后仍然保留的关键词');
        expect(find.text('修改后仍然保留的关键词'), findsOneWidget);
        expect(find.byType(TextField).hitTestable(), findsOneWidget);
        for (final label in ['听书', '听歌', '听现场', 'UP 主']) {
          final target = find.widgetWithText(ChoiceChip, label);
          expect(target.hitTestable(), findsOneWidget);
          expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = const FakeViewPadding();
        await tester.tap(find.widgetWithText(ChoiceChip, 'UP 主'));
        await tester.pumpAndSettle();
        expect(find.text('很长很长的创作者名称以及工作室'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, '关注'));
        await tester.pumpAndSettle();
        expect(find.text('已关注'), findsOneWidget);
        expect(find.byType(SearchPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'login ${brightness.name} at 320dp and 200% keeps QR refresh reachable',
      (tester) async {
        _narrowScreen(tester, brightness);
        final api = _LayoutApi();
        await tester.pumpWidget(_host(LoginPage(api: api), brightness));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // ListView lazily builds the actions below the QR; scroll until built.
        await tester.scrollUntilVisible(
          find.text('刷新二维码'),
          200,
          scrollable: find.byType(Scrollable),
        );
        expect(find.text('刷新二维码').hitTestable(), findsOneWidget);
        await tester.tap(find.text('刷新二维码'));
        await tester.pumpAndSettle();
        expect(api.qrGenerations, 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
