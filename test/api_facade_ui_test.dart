import 'package:blisten/core/network/api_config.dart';
import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/follow_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/models/up_user.dart';
import 'package:blisten/pages/discover_page.dart';
import 'package:blisten/pages/follow_page.dart';
import 'package:blisten/pages/up_home_page.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The HTTP boundary is synthetic; parsing, fallback, cursors and pages are real.
class _Client implements BiliClient {
  _Client(this.respond);
  final Object Function(String url, Map<String, dynamic> query) respond;
  final calls = <({String url, Map<String, dynamic> query})>[];

  @override
  Future<Response<dynamic>> get(String url, {
    Map<String, dynamic>? query,
    bool useWbi = false,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    final parameters = Map<String, dynamic>.of(query ?? {});
    calls.add((url: url, query: parameters));
    final result = respond(url, parameters);
    if (result is Exception) throw result;
    return Response(data: result, statusCode: 200,
        requestOptions: RequestOptions(path: url));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RouteCapture extends NavigatorObserver {
  UpHomePage? destination;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! MaterialPageRoute) return;
    // Inspect the page constructed by FollowPage before its first frame. The
    // target is not mounted here, so its singleton API cannot start a request.
    final page = route.builder(navigator!.context);
    if (page is UpHomePage) destination = page;
  }
}

const _up = UpUser(mid: 42, name: '测试 UP');
Object _offline() => BiliApiException(-1, 'synthetic offline');
Map<String, dynamic> _search(List<Map<String, dynamic>> rows) => {
  'code': 0, 'data': {'result': rows, 'numResults': rows.length},
};
Map<String, dynamic> _book(String bvid, String title) => {
  'bvid': bvid, 'aid': 42, 'title': title,
  'duration': 900, 'mid': 42, 'author': _up.name,
};
Map<String, dynamic> _collections({bool season = false}) => {
  'code': 0,
  'data': {
    'items_lists': {
      'seasons_list': [
        if (season) {'meta': {'season_id': 7}, 'archives': []},
      ],
      'series_list': [],
    },
  },
};
Map<String, dynamic> _archives(List<Map<String, dynamic>> rows) => {
  'code': 0, 'data': {'archives': rows},
};
Object _empty(String url, Map<String, dynamic> query) {
  if (url == BiliEndpoints.upCollections) return _collections();
  if (url == BiliEndpoints.spaceArcSearch) {
    return {'code': 0, 'data': {'list': {'vlist': []}}};
  }
  return _search([]);
}

Widget _host(Widget page, {NavigatorObserver? observer}) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: CacheStore.instance),
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider.value(value: FollowStore.instance),
  ],
  child: MaterialApp(
    theme: AppTheme.dark(),
    navigatorObservers: [?observer],
    home: page,
  ),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'abts_shelf': '[]', 'abts_recent': '[]', 'abts_follows': '[]',
    });
    await ShelfStore.instance.load();
    await FollowStore.instance.load();
  });

  testWidgets('real UP facade shows all-source failure and retries to valid empty', (tester) async {
    var failed = true;
    final client = _Client((url, query) => failed ? _offline() : _empty(url, query));
    await tester.pumpWidget(_host(UpHomePage(up: _up, api: BiliApi(client: client))));
    await tester.pumpAndSettle();
    expect(client.calls, hasLength(3));
    expect(find.text('加载失败，请稍后重试'), findsOneWidget);
    expect(find.text('暂时取不到「测试 UP」的投稿'), findsNothing);

    failed = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(client.calls, hasLength(6));
    expect(find.text('加载失败，请稍后重试'), findsNothing);
    expect(find.text('暂时取不到「测试 UP」的投稿'), findsOneWidget);
  });

  testWidgets('real discovery facade distinguishes first failure from valid empty retry', (tester) async {
    var failed = true;
    final client = _Client((_, _) => failed ? _offline() : _search([]));
    await tester.pumpWidget(_host(DiscoverPage(api: BiliApi(client: client))));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('加载失败，请重试'), findsOneWidget);
    expect(find.text('暂时没有相关内容'), findsNothing);

    failed = false;
    await tester.tap(find.text('重试'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(client.calls, hasLength(2));
    expect(find.text('加载失败，请重试'), findsNothing);
    expect(find.text('暂时没有相关内容'), findsOneWidget);
  });

  testWidgets('real collection cursor retains partial books and retries its failed page', (tester) async {
    var failed = true;
    final client = _Client((url, query) {
      if (url == BiliEndpoints.upCollections) return _collections(season: true);
      if (url == BiliEndpoints.upCollectionArchives) {
        return switch (query['page_num']) {
          1 => _archives([_book('BV1TEST000001', '有声小说 第一页')]),
          2 => failed ? _offline() : _archives([_book('BV1TEST000002', '有声小说 第二页')]),
          _ => _archives([]),
        };
      }
      throw StateError('Unexpected fallback: $url');
    });
    await tester.pumpWidget(_host(UpHomePage(up: _up, api: BiliApi(client: client))));
    await tester.pumpAndSettle();
    expect(find.text('有声小说 第一页'), findsOneWidget);
    expect(find.text('部分内容加载失败，请重试'), findsOneWidget);

    failed = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    final pages = client.calls.where((c) => c.url == BiliEndpoints.upCollectionArchives)
        .map((c) => c.query['page_num']).toList();
    expect(pages, [1, 2, 2, 3]);
    expect(find.text('有声小说 第一页'), findsOneWidget);
    expect(find.text('有声小说 第二页'), findsOneWidget);
    expect(find.text('部分内容加载失败，请重试'), findsNothing);
  });

  testWidgets('real discovery refresh failure keeps results and visibly retries current query', (tester) async {
    var failed = false;
    final client = _Client((_, query) => failed
        ? _offline() : _search([_book('BV1TEST000001', '有声小说 已收到')]));
    await tester.pumpWidget(_host(DiscoverPage(api: BiliApi(client: client))));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('有声小说 已收到'), findsOneWidget);

    failed = true;
    await tester.tap(find.byTooltip('刷新'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('加载失败，请重试'), findsOneWidget);
    expect(find.text('有声小说 已收到'), findsOneWidget);

    failed = false;
    await tester.tap(find.text('重试'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(client.calls.map((c) => c.query['page']), [1, 1, 1]);
    expect(client.calls.every((c) => c.query['keyword'] == '有声小说' && c.query['order'] == 'click'), isTrue);
    expect(find.text('加载失败，请重试'), findsNothing);
    expect(find.text('有声小说 已收到'), findsOneWidget);
  });

  testWidgets('following opens the UP page with the persisted listening mode', (tester) async {
    await FollowStore.instance.toggle(_up.withContentMode(ContentMode.concert));
    await FollowStore.instance.load();
    final observer = _RouteCapture();
    await tester.pumpWidget(_host(const FollowPage(), observer: observer));
    await tester.tap(find.text(_up.name));
    expect(observer.destination?.contentMode, ContentMode.concert);
    expect(observer.destination?.up.mid, _up.mid);
    // Remove the navigator before the real target's initial API request starts.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('changing the UP listening mode updates the followed user after reload', (tester) async {
    await FollowStore.instance.toggle(_up.withContentMode(ContentMode.concert));
    final api = BiliApi(client: _Client(_empty));
    await tester.pumpWidget(_host(UpHomePage(up: _up,
        contentMode: ContentMode.concert, api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '听歌'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '听歌')).selected, isTrue);
    await FollowStore.instance.load();
    expect(FollowStore.instance.byMid(_up.mid)?.contentMode, ContentMode.music);
    expect(FollowStore.instance.length, 1);
  });
}
