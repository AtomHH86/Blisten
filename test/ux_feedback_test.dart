import 'package:dio/dio.dart';
import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/follow_store.dart';
import 'package:blisten/core/storage/search_history_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/models/up_user.dart';
import 'package:blisten/pages/discover_page.dart';
import 'package:blisten/pages/follow_page.dart';
import 'package:blisten/pages/login_page.dart';
import 'package:blisten/pages/search_page.dart';
import 'package:blisten/pages/up_home_page.dart';
import 'package:blisten/services/auth_store.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:blisten/services/bili_resource.dart';
import 'package:blisten/widgets/resource_import_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api implements BiliApi {
  bool failBrowse = false;
  bool failMore = true;
  bool failPoll = true;
  int browseCalls = 0;
  int pollCalls = 0;
  final pages = <int>[];

  @override
  Future<List<Book>> rankHotNovel({int limit = 30, void Function(Object error)? onPartialFailure,
    CancelToken? cancelToken,
  }) async {
    browseCalls++;
    if (failBrowse) throw BiliApiException(-500, '接口暂不可用');
    return [];
  }

  @override
  Future<({List<Book> books, bool hasMore})> upAudios(
    UpUser up, {
    int page = 1,
    int pageSize = 30,
    ContentMode mode = ContentMode.audiobook,
    void Function(Object error)? onPartialFailure,
    CancelToken? cancelToken,
  }) async {
    pages.add(page);
    if (page == 2 && failMore) throw BiliApiException(-500, '分页失败');
    return (
      books: [
        Book(
          bvid: 'BV$page',
          aid: page,
          title: '投稿第$page页',
          pic: '',
          contentMode: mode,
        ),
      ],
      hasMore: page == 1,
    );
  }

  @override
  Future<({String url, String qrKey})> qrGenerate() async =>
      (url: 'https://example.com/qr', qrKey: 'fixture');

  @override
  Future<String> qrPoll(String key) async {
    pollCalls++;
    if (failPoll) throw BiliApiException(-500, '轮询失败');
    return 'waiting';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InvalidResource implements BiliResourceResolver {
  @override
  Future<BiliResource> resolve(String input) async =>
      throw const FormatException('请输入有效的 B 站链接或 BV 号');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget child, {double scale = 1}) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: CacheStore.instance),
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider.value(value: FollowStore.instance),
    ChangeNotifierProvider.value(value: SearchHistoryStore.instance),
    ChangeNotifierProvider.value(value: LoginStore.instance),
  ],
  child: MaterialApp(
    theme: AppTheme.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: child,
  ),
);

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
    'discover API failure is neutral, retryable and does not claim offline playback',
    (tester) async {
      final api = _Api()..failBrowse = true;
      await tester.pumpWidget(_host(DiscoverPage(api: api)));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.textContaining('无网络'), findsNothing);
      expect(find.textContaining('自动切换离线'), findsNothing);
      expect(find.text('加载失败，请重试'), findsOneWidget);
      api.failBrowse = false;
      await tester.tap(find.text('重试'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(api.browseCalls, 2);
      expect(find.text('暂时没有相关内容'), findsOneWidget);
      expect(find.text('去搜索'), findsOneWidget);
    },
  );

  testWidgets('UP pagination failure keeps results and retries the same page', (
    tester,
  ) async {
    final api = _Api();
    await tester.pumpWidget(
      _host(
        UpHomePage(
          up: const UpUser(mid: 17, name: '测试 UP'),
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('投稿第1页'), findsOneWidget);
    expect(find.text('加载更多失败，请重试'), findsOneWidget);
    api.failMore = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(api.pages, [1, 2, 2]);
    expect(find.text('投稿第1页'), findsOneWidget);
    expect(find.text('投稿第2页'), findsOneWidget);
  });

  testWidgets('QR polling failure is visible and can resume checking', (
    tester,
  ) async {
    final api = _Api();
    await tester.pumpWidget(_host(LoginPage(api: api)));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('登录状态检查失败，请重试或刷新二维码'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    api.failPoll = false;
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(api.pollCalls, 2);
    expect(find.text('使用哔哩哔哩 App 扫码登录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty following provides a working search entry', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const FollowPage()));
    await tester.tap(find.text('去搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.byTooltip('返回上一页'), findsOneWidget);
    expect(find.byTooltip('回到发现页'), findsNothing);
  });

  testWidgets(
    'narrow large-text import preserves mode and input after validation failure',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: ResourceImportDialog(
              initialMode: ContentMode.concert,
              resolver: _InvalidResource(),
            ),
          ),
          scale: 2,
        ),
      );
      await tester.enterText(find.byType(TextField), '保留这段分享文本');
      await tester.ensureVisible(find.text('添加资源'));
      await tester.tap(find.text('添加资源'));
      await tester.pumpAndSettle();
      expect(find.text('保留这段分享文本'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '听现场'))
            .selected,
        isTrue,
      );
      expect(find.text('请输入有效的 B 站链接或 BV 号'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
