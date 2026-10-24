import 'package:dio/dio.dart';
import 'dart:async';

import 'package:blisten/core/storage/follow_store.dart';
import 'package:blisten/core/storage/search_history_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/models/up_user.dart';
import 'package:blisten/pages/book_detail_page.dart';
import 'package:blisten/pages/search_page.dart';
import 'package:blisten/pages/up_home_page.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _Result = ({List<Book> books, bool hasMore});

class _Api implements BiliApi {
  final requests = <({ContentMode mode, int page})>[];
  Future<_Result> Function(ContentMode mode, int page)? respond;
  ContentMode? detailMode;

  @override
  Future<_Result> upAudios(
    UpUser up, {
    int page = 1,
    int pageSize = 30,
    ContentMode mode = ContentMode.audiobook,
    void Function(Object error)? onPartialFailure,
    CancelToken? cancelToken,
  }) async {
    requests.add((mode: mode, page: page));
    if (respond != null) return respond!(mode, page);
    return _result('${mode.name} 第$page页', hasMore: page == 1);
  }

  @override
  Future<Book> detail(String bvid, {ContentMode mode = ContentMode.audiobook}) {
    detailMode = mode;
    // Keep the real details route loading: this test only exercises mode routing.
    return Completer<Book>().future;
  }

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
    onRawCount?.call(0);
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

_Result _result(String title, {bool hasMore = false}) => (
  // The page must tag API results with the selected mode, not rely on the fixture.
  books: [Book(bvid: title, aid: 1, title: title, pic: '')],
  hasMore: hasMore,
);

Widget _host(
  _Api api, {
  ContentMode mode = ContentMode.audiobook,
  UpUser up = const UpUser(mid: 17, name: '测试 UP'),
  Brightness brightness = Brightness.dark,
  double textScale = 1,
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: FollowStore.instance),
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider.value(value: SearchHistoryStore.instance),
  ],
  child: MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: UpHomePage(up: up, contentMode: mode, api: api),
  ),
);

Finder _modeChip(String label) => find.widgetWithText(ChoiceChip, label);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'abts_shelf': '[]',
      'abts_follows': '[]',
    });
    await FollowStore.instance.load();
    await ShelfStore.instance.load();
    await SearchHistoryStore.instance.clear();
  });

  testWidgets(
    'UP mode switch restarts page one and opens details in new mode',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(_host(api, mode: ContentMode.music));
      await tester.pumpAndSettle();
      expect(_modeChip('听歌'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(_modeChip('听歌')).selected, isTrue);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('music 第2页'), findsOneWidget);

      await tester.tap(_modeChip('听现场'));
      await tester.pumpAndSettle();
      expect(api.requests.last, (mode: ContentMode.concert, page: 1));
      expect(find.text('music 第1页'), findsNothing);
      expect(find.text('music 第2页'), findsNothing);
      await tester.tap(find.text('concert 第1页'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('演唱会详情'), findsOneWidget);
      expect(
        tester.widget<BookDetailPage>(find.byType(BookDetailPage)).contentMode,
        ContentMode.concert,
      );
      expect(api.detailMode, ContentMode.concert);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late UP pagination cannot append to a different mode', (
    tester,
  ) async {
    final oldPage = Completer<_Result>();
    final newPage = Completer<_Result>();
    final api = _Api()
      ..respond = (mode, page) async {
        if (mode == ContentMode.music && page == 2) return oldPage.future;
        if (mode == ContentMode.concert) return newPage.future;
        return _result('原歌曲列表', hasMore: true);
      };
    await tester.pumpWidget(_host(api, mode: ContentMode.music));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    expect(_modeChip('听现场'), findsOneWidget);
    await tester.tap(_modeChip('听现场'));
    await tester.pump();
    expect(find.text('原歌曲列表'), findsNothing);
    newPage.complete(_result('新现场列表'));
    await tester.pumpAndSettle();
    oldPage.complete(_result('旧歌曲第二页'));
    await tester.pumpAndSettle();
    expect(find.text('新现场列表'), findsOneWidget);
    expect(find.text('旧歌曲第二页'), findsNothing);
    expect(find.text('原歌曲列表'), findsNothing);
  });

  testWidgets('late UP first page cannot replace the newly selected mode', (
    tester,
  ) async {
    final oldFirst = Completer<_Result>();
    final api = _Api()
      ..respond = (mode, page) async {
        if (mode == ContentMode.audiobook) return oldFirst.future;
        return _result('新歌曲列表');
      };
    await tester.pumpWidget(_host(api));
    await tester.pump();
    expect(_modeChip('听歌'), findsOneWidget);
    await tester.tap(_modeChip('听歌'));
    await tester.pumpAndSettle();
    oldFirst.complete(_result('旧听书列表'));
    await tester.pumpAndSettle();
    expect(find.text('新歌曲列表'), findsOneWidget);
    expect(find.text('旧听书列表'), findsNothing);
    expect(tester.widget<ChoiceChip>(_modeChip('听歌')).selected, isTrue);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'UP ${fails ? 'error' : 'empty'} state can switch content mode',
      (tester) async {
        final api = _Api()
          ..respond = (mode, page) async {
            if (mode == ContentMode.audiobook) {
              if (fails) throw Exception('fixture unavailable');
              return (books: <Book>[], hasMore: false);
            }
            return _result('恢复后的歌曲');
          };
        await tester.pumpWidget(_host(api));
        await tester.pumpAndSettle();
        expect(find.text(fails ? '加载失败' : '暂时取不到「测试 UP」的投稿'), findsOneWidget);
        expect(_modeChip('听歌'), findsOneWidget);
        await tester.tap(_modeChip('听歌'));
        await tester.pumpAndSettle();
        expect(find.text('恢复后的歌曲'), findsOneWidget);
        expect(find.text('加载失败'), findsNothing);
        expect(find.text('暂时取不到「测试 UP」的投稿'), findsNothing);
        expect(api.requests.last, (mode: ContentMode.music, page: 1));
      },
    );
  }

  testWidgets('UP empty search fallback uses the visible mode', (tester) async {
    final api = _Api()
      ..respond = (mode, page) async => (books: <Book>[], hasMore: false);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(_modeChip('听现场'), findsOneWidget);
    await tester.tap(_modeChip('听现场'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索「测试 UP」'));
    await tester.pumpAndSettle();
    final search = tester.widget<SearchPage>(find.byType(SearchPage));
    expect(search.initialMode, ContentMode.concert);
    expect(search.initialKeyword, '测试 UP');
  });

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets(
      'UP ${brightness.name} 320dp 200% layout keeps empty modes and results usable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _Api()
          ..respond = (mode, page) async {
            if (mode == ContentMode.audiobook) {
              return (books: <Book>[], hasMore: false);
            }
            return _result('可以打开的歌曲');
          };
        await tester.pumpWidget(
          _host(
            api,
            brightness: brightness,
            textScale: 2,
            up: const UpUser(
              mid: 17,
              name: '名字很长的音乐故事创作者与现场工作室',
              sign: '这里分享音乐、演唱会现场和有声故事，欢迎闭上眼睛一起认真听每一个声音。',
              fans: 12345678,
              videos: 98765,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('暂时取不到'), findsOneWidget);
        for (final label in ['听书', '听歌', '听现场', '听故事']) {
          expect(_modeChip(label).hitTestable(), findsOneWidget);
        }

        await tester.tap(_modeChip('听歌'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.widget<ChoiceChip>(_modeChip('听歌')).selected, isTrue);
        await tester.ensureVisible(find.text('可以打开的歌曲'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('可以打开的歌曲').hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('歌曲详情'), findsOneWidget);
        expect(api.detailMode, ContentMode.music);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
