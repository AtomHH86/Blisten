import 'package:dio/dio.dart';
import 'dart:async';

import 'package:blisten/core/storage/follow_store.dart';
import 'package:blisten/core/storage/search_history_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/models/up_user.dart';
import 'package:blisten/pages/search_page.dart';
import 'package:blisten/pages/up_home_page.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api implements BiliApi {
  final videos = <({String keyword, ContentMode mode})>[];
  final users = <({String keyword, int page})>[];
  Completer<List<UpUser>>? pendingUsers;
  CancelToken? userCancelToken;
  bool paginate = false;
  bool failSecondPage = false;

  @override
  Future<List<Book>> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    String? order,
    Function(int total)? onFirstPage,
    Function(int rawCount)? onRawCount,
    ContentMode mode = ContentMode.audiobook,
    CancelToken? cancelToken,
  }) async {
    videos.add((keyword: keyword, mode: mode));
    onRawCount?.call(1);
    return [
      Book(
        bvid: 'BVtest',
        aid: 1,
        title: '${mode.name}内容',
        pic: '',
        contentMode: mode,
      ),
    ];
  }

  @override
  Future<List<UpUser>> searchUser(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    CancelToken? cancelToken,
  }) async {
    users.add((keyword: keyword, page: page));
    userCancelToken = cancelToken;
    if (pendingUsers != null) return pendingUsers!.future;
    if (page == 2 && failSecondPage) throw Exception('temporary failure');
    if (!paginate) return const [UpUser(mid: 1, name: '独立搜索的创作者')];
    if (page == 1) {
      return List.generate(20, (i) => UpUser(mid: i + 1, name: '创作者${i + 1}'));
    }
    return const [
      UpUser(mid: 20, name: '创作者20'),
      UpUser(mid: 21, name: '第二页创作者'),
    ];
  }

  @override
  Future<({List<Book> books, bool hasMore})> upAudios(
    UpUser up, {
    int page = 1,
    int pageSize = 30,
    ContentMode mode = ContentMode.audiobook,
    void Function(Object error)? onPartialFailure,
    CancelToken? cancelToken,
  }) async => (books: <Book>[], hasMore: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(
  _Api api, {
  String? keyword,
  ContentMode mode = ContentMode.audiobook,
  Brightness brightness = Brightness.dark,
  double textScale = 1,
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider.value(value: FollowStore.instance),
    ChangeNotifierProvider.value(value: SearchHistoryStore.instance),
  ],
  child: MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: SearchPage(api: api, initialKeyword: keyword, initialMode: mode),
  ),
);

Finder _category(String label) => find.widgetWithText(ChoiceChip, label);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'abts_shelf': '[]',
      'abts_follows': '[]',
    });
    await ShelfStore.instance.load();
    await FollowStore.instance.load();
    await SearchHistoryStore.instance.clear();
  });

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('children search accepts keyboard input at 320dp 200% ${brightness.name}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final api = _Api();
      await tester.pumpWidget(_host(api, mode: ContentMode.children,
          brightness: brightness, textScale: 2));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '小星星');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      for (final label in ['听书', '听歌', '听现场', '儿童', 'UP 主']) {
        expect(_category(label).hitTestable(), findsOneWidget);
      }
      expect(tester.widget<ChoiceChip>(_category('儿童')).selected, isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(find.text('children内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('five categories stay usable at 320dp 200% ${brightness.name}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _Api();
      await tester.pumpWidget(_host(api, brightness: brightness, textScale: 2));
      await tester.pumpAndSettle();
      for (final label in ['听书', '听歌', '听现场', '儿童', 'UP 主']) {
        expect(_category(label).hitTestable(), findsOneWidget);
        await tester.tap(_category(label));
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(_category(label)).selected, isTrue);
        expect(tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((chip) => chip.selected), hasLength(1));
        expect(tester.takeException(), isNull);
      }
      await tester.tap(_category('儿童'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '小星星');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('children内容'), findsOneWidget);
      await tester.ensureVisible(find.text('children内容'));
      expect(find.text('children内容').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('children suggestions search and UP route retain the chosen context',
      (tester) async {
    final api = _Api();
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    await tester.tap(_category('儿童'));
    await tester.pumpAndSettle();
    expect(find.text('儿歌、动画、故事 · 仅收听声音'), findsOneWidget);
    for (final keyword in ['儿歌', '儿童动画片', '儿童故事']) {
      expect(find.text(keyword), findsOneWidget);
    }
    await tester.tap(find.text('儿童故事'));
    await tester.pumpAndSettle();
    expect(find.text('children内容'), findsOneWidget);
    expect(api.videos.single.keyword, '儿童故事');
    expect(api.videos.single.mode.name, 'children');
    await tester.tap(_category('UP 主'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('独立搜索的创作者'));
    await tester.pumpAndSettle();
    expect(tester.widget<UpHomePage>(find.byType(UpHomePage)).contentMode.name,
        'children');
  });

  testWidgets('UP can be selected before typing and searches users only', (
    tester,
  ) async {
    final api = _Api();
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    await tester.tap(_category('UP 主'));
    await tester.pumpAndSettle();
    expect(api.users, isEmpty);
    expect(api.videos, isEmpty);
    expect(find.text('热门搜索'), findsNothing);
    await tester.enterText(find.byType(TextField), '创作者名字');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(api.users.single, (keyword: '创作者名字', page: 1));
    expect(api.videos, isEmpty);
    expect(find.text('独立搜索的创作者'), findsOneWidget);
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .where((chip) => chip.selected),
      hasLength(1),
    );
  });

  testWidgets('returning to previous category cancels pending UP results', (
    tester,
  ) async {
    final api = _Api()..pendingUsers = Completer<List<UpUser>>();
    await tester.pumpWidget(_host(api, keyword: '同一个词'));
    await tester.pumpAndSettle();
    await tester.tap(_category('UP 主'));
    await tester.pump();
    expect(tester.widget<ChoiceChip>(_category('UP 主')).selected, isTrue);
    expect(find.text('audiobook内容'), findsNothing);
    await tester.tap(_category('听书'));
    await tester.pumpAndSettle();
    expect(api.userCancelToken!.isCancelled, isTrue);
    api.pendingUsers!.complete(const [UpUser(mid: 9, name: '迟到的UP')]);
    await tester.pumpAndSettle();
    expect(find.text('迟到的UP'), findsNothing);
    expect(find.text('audiobook内容'), findsOneWidget);
    expect(api.videos.last.keyword, '同一个词');
    expect(tester.widget<ChoiceChip>(_category('听书')).selected, isTrue);
  });

  testWidgets('UP failure keeps category and keyword for retry', (
    tester,
  ) async {
    final api = _Api()..pendingUsers = Completer<List<UpUser>>();
    await tester.pumpWidget(_host(api, keyword: '失败后重试'));
    await tester.pumpAndSettle();
    await tester.tap(_category('UP 主'));
    await tester.pump();
    api.pendingUsers!.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(_category('UP 主')).selected, isTrue);
    expect(find.text('失败后重试'), findsOneWidget);
    expect(find.text('audiobook内容'), findsNothing);
    api.pendingUsers = null;
    await tester.ensureVisible(find.text('重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(api.users.last, (keyword: '失败后重试', page: 1));
    expect(find.text('独立搜索的创作者'), findsOneWidget);
  });

  testWidgets(
    'clear invalidates pending UP response and retains UP selection',
    (tester) async {
      final api = _Api()..pendingUsers = Completer<List<UpUser>>();
      await tester.pumpWidget(_host(api, keyword: '清空前'));
      await tester.pumpAndSettle();
      await tester.tap(_category('UP 主'));
      await tester.pump();
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(api.userCancelToken!.isCancelled, isTrue);
      api.pendingUsers!.complete(const [UpUser(mid: 9, name: '清空后的迟到结果')]);
      await tester.pumpAndSettle();
      expect(find.text('清空后的迟到结果'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.widget<ChoiceChip>(_category('UP 主')).selected, isTrue);
    },
  );

  testWidgets('UP search opens creator in the last explicit content mode', (
    tester,
  ) async {
    final api = _Api();
    await tester.pumpWidget(_host(api, keyword: '歌手', mode: ContentMode.music));
    await tester.pumpAndSettle();
    await tester.tap(_category('UP 主'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('独立搜索的创作者'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<UpHomePage>(find.byType(UpHomePage)).contentMode,
      ContentMode.music,
    );
  });

  testWidgets(
    'UP pagination retries submitted keyword and deduplicates creators',
    (tester) async {
      final api = _Api()
        ..paginate = true
        ..failSecondPage = true;
      await tester.pumpWidget(_host(api, keyword: '已提交人名'));
      await tester.pumpAndSettle();
      await tester.tap(_category('UP 主'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '未提交新词');
      await tester.drag(find.byType(ListView), const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(api.users.last, (keyword: '已提交人名', page: 2));
      api.failSecondPage = false;
      await tester.ensureVisible(find.text('重试'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(api.users.where((r) => r.page == 2), hasLength(2));
      expect(api.users.last.keyword, '已提交人名');
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.text('第二页创作者'), findsOneWidget);
      expect(find.text('创作者20'), findsOneWidget);
      expect(find.text('— 已经到底啦 —'), findsOneWidget);
    },
  );
}
