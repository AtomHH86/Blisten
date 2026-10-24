import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/nav/home_tabs.dart';
import 'package:blisten/core/network/api_config.dart';
import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/search_history_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/chapter.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/book_detail_page.dart';
import 'package:blisten/pages/cache_sheet.dart';
import 'package:blisten/pages/discover_page.dart';
import 'package:blisten/pages/search_page.dart';
import 'package:blisten/pages/up_home_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Exercise the real cache index against a real local media fixture.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bvid = 'BV1MOVED00001';
const _title = '有声小说 移动作品';
final _book = Book(bvid: _bvid, aid: 1, title: _title, pic: '');

class _Client implements BiliClient {
  _Client({this.offline = false});
  final bool offline;
  @override
  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? query,
    bool useWbi = false,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    if (offline) throw BiliApiException(-1, 'synthetic offline');
    final data = url == BiliEndpoints.view
        ? {
            'bvid': _bvid,
            'aid': 1,
            'title': _title,
            'pic': '',
            'owner': {'mid': 42, 'name': '移动作品 UP', 'face': ''},
            'pages': [
              {'cid': 101, 'page': 1, 'part': '第一首', 'duration': 180},
              {'cid': 102, 'page': 2, 'part': '第二首', 'duration': 180},
            ],
          }
        : {
            'result': [
              {
                'bvid': _bvid,
                'aid': 1,
                'title': _title,
                'pic': '',
                'duration': 900,
                'author': '移动作品 UP',
                'mid': 42,
              },
            ],
            'numResults': 1,
          };
    return Response(
      data: {'code': 0, 'data': data},
      statusCode: 200,
      requestOptions: RequestOptions(path: url),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player extends ChangeNotifier implements BookPlayer {
  final requests = <({Book book, bool resume, int ms, int? cid})>[];
  // Opening a moved detail must leave this original audiobook session intact.
  @override
  Book? get book => _book;
  @override
  bool get loaded => true;
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  int get index => 0;
  @override
  bool get isPlaying => false;
  @override
  Chapter? get currentChapter => null;
  @override
  void flushProgress() {}
  @override
  Future<bool> playBook(
    Book book, {
    int resumeIndex = 0,
    int resumeMs = 0,
    int? resumeCid,
    bool resume = true,
  }) async {
    requests.add((book: book, resume: resume, ms: resumeMs, cid: resumeCid));
    return false;
  }

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
  UpHomePage? upPage;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! MaterialPageRoute) return;
    final page = route.builder(navigator!.context);
    if (page is UpHomePage) upPage = page;
  }
}

Widget _host(
  Widget page, {
  BookPlayer? player,
  GlobalKey<NavigatorState>? navigator,
  NavigatorObserver? observer,
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider.value(value: CacheStore.instance),
    ChangeNotifierProvider.value(value: SearchHistoryStore.instance),
    if (player != null) ChangeNotifierProvider<BookPlayer>.value(value: player),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    navigatorKey: navigator,
    navigatorObservers: [?observer],
    home: page,
  ),
);

Future<void> _hearAndCollect() async {
  final shelf = ShelfStore.instance;
  await shelf.updateProgress(
    _bvid,
    book: _book,
    cid: 102,
    chapterIndex: 1,
    positionMs: 45000,
    chapterDurationMs: 180000,
  );
  await shelf.add(_book);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    HomeTabs.discoverMode.value = null;
    await ShelfStore.instance.load();
  });

  for (final removeFavorite in [false, true]) {
    testWidgets(
      'old audiobook search opens moved ${removeFavorite ? 'recent' : 'favorite'} with music playback and cache mode',
      (tester) async {
        final shelf = ShelfStore.instance;
        await _hearAndCollect();
        await shelf.moveToMode(_bvid, ContentMode.music);
        if (removeFavorite) await shelf.remove(_bvid);
        final player = _Player();
        final navigator = GlobalKey<NavigatorState>();
        final routes = _Routes();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          player.dispose();
        });
        await tester.pumpWidget(
          _host(
            SearchPage(
              initialKeyword: '有声小说',
              api: BiliApi(client: _Client()),
            ),
            player: player,
            navigator: navigator,
            observer: routes,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(_title));
        await tester.pumpAndSettle();
        expect(find.byType(BookDetailPage), findsOneWidget);
        expect(find.text('歌曲详情'), findsOneWidget);
        expect(find.text('目录（2 曲）'), findsOneWidget);
        expect(find.text('继续收听'), findsNothing);
        expect(player.requests, isEmpty);
        expect(player.book!.contentMode, ContentMode.audiobook);

        await tester.tap(find.byTooltip('批量缓存'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<CacheSheet>(find.byType(CacheSheet)).book!.contentMode,
          ContentMode.music,
        );
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await tester.tap(find.text('开始收听'));
        await tester.pumpAndSettle();
        final request = player.requests.single;
        expect(request.book.contentMode, ContentMode.music);
        expect(request.resume, isFalse);
        expect(request.ms, 0);
        expect(request.cid, isNull);

        // Inspect the route built by the actual UP action before mounting its
        // unrelated feed; the destination mode is the contract under test.
        await tester.tap(find.text('UP 主 · 移动作品 UP'));
        expect(routes.upPage?.contentMode, ContentMode.music);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'offline discovery follows moved recent mode after unfavoriting and listens for moves',
    (tester) async {
      const entry = CacheEntry(
        bvid: _bvid,
        cid: 101,
        bookTitle: _title,
        chapterTitle: '第一首',
        contentMode: ContentMode.audiobook,
      );
      SharedPreferences.setMockInitialValues({
        'abts_cache_index': jsonEncode([entry.toJson()]),
      });
      final oldPaths = PathProviderPlatform.instance;
      late Directory root;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp(
          'blisten-moved-discovery-',
        );
        PathProviderPlatform.instance = _Paths(root.path);
        final dir = await Directory('${root.path}/audio_cache').create();
        await File(
          'test/fixtures/cache-silence.m4a',
        ).copy('${dir.path}/${entry.fileName}');
        await CacheStore.instance.load();
        await ShelfStore.instance.load();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await CacheStore.instance.clearAll();
          await root.delete(recursive: true);
          PathProviderPlatform.instance = oldPaths;
        });
        HomeTabs.discoverMode.value = null;
      });
      await _hearAndCollect();
      final shelf = ShelfStore.instance;
      await tester.pumpWidget(
        _host(DiscoverPage(api: BiliApi(client: _Client(offline: true)))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);

      await shelf.moveToMode(_bvid, ContentMode.music);
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      await shelf.remove(_bvid);
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      await tester.tap(find.byKey(const ValueKey('discover-channel-music')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      expect(find.text('已缓存 1 曲 · 离线可听'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('discover-channel-audiobook')),
      );
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
