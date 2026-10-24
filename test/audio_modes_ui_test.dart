import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:blisten/core/storage/search_history_store.dart';
import 'package:blisten/core/storage/follow_store.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/chapter.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/models/up_user.dart';
import 'package:blisten/pages/search_page.dart';
import 'package:blisten/pages/discover_page.dart';
import 'package:blisten/pages/book_detail_page.dart';
import 'package:blisten/pages/up_home_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:blisten/services/bili_resource.dart';
import 'package:blisten/widgets/resource_import_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api implements BiliApi {
  final requests = <({String keyword, int page, ContentMode mode})>[];
  final pending = <Completer<List<Book>>>[];
  bool defer = false;
  bool deferUsers = false;
  String? resultTitle;
  final pendingUsers = <Completer<List<UpUser>>>[];
  ContentMode? detailMode;
  final upRequests = <({int page, ContentMode mode})>[];

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
    requests.add((keyword: keyword, page: page, mode: mode));
    onRawCount?.call(20);
    if (defer) {
      final completer = Completer<List<Book>>();
      pending.add(completer);
      return completer.future;
    }
    return List.generate(
      20,
      (i) => _book(
        mode,
        resultTitle ?? '${mode.name} 第 $page 页${i == 0 ? '' : ' #$i'}',
        bvid: '${mode.name}-$page-$i',
      ),
    );
  }

  @override
  Future<List<Book>> rankHotNovel({int limit = 30}) async => [
    _book(ContentMode.audiobook, '推荐测试作品'),
  ];

  @override
  Future<List<UpUser>> searchUser(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    if (deferUsers) {
      final completer = Completer<List<UpUser>>();
      pendingUsers.add(completer);
      return completer.future;
    }
    return const [UpUser(mid: 17, name: '测试 UP 主')];
  }

  @override
  Future<({List<Book> books, bool hasMore})> upAudios(
    UpUser up, {
    int page = 1,
    int pageSize = 30,
    ContentMode mode = ContentMode.audiobook,
  }) async {
    upRequests.add((page: page, mode: mode));
    return (
      books: [_book(mode, 'UP 的短歌', bvid: 'BV1xx411c7m$page')],
      hasMore: page == 1,
    );
  }

  @override
  Future<Book> detail(
    String bvid, {
    ContentMode mode = ContentMode.audiobook,
  }) async {
    detailMode = mode;
    return _book(mode, '导入的作品');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Book _book(ContentMode mode, String title, {String bvid = 'BV1xx411c7mD'}) =>
    Book(
      bvid: bvid,
      aid: 1,
      title: title,
      pic: '',
      contentMode: mode,
      chapters: [
        Chapter(cid: 11, page: 1, part: '第一分 P', duration: 180),
        Chapter(cid: 12, page: 2, part: '第二分 P', duration: 180),
      ],
    );

class _Resolver implements BiliResourceResolver {
  bool fail = false;
  int? page = 2;
  Object? error;
  @override
  Future<BiliResource> resolve(String input) async {
    if (fail) throw const FormatException('请输入有效的 B 站链接或 BV 号');
    if (error != null) throw error!;
    return BiliResource(bvid: 'BV1xx411c7mD', page: page);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player extends ChangeNotifier implements BookPlayer {
  ({Book book, int index, int ms, bool resume})? selection;

  @override
  void flushProgress() {}

  @override
  Future<bool> playBook(
    Book book, {
    int resumeIndex = 0,
    int resumeMs = 0,
    bool resume = true,
  }) {
    selection = (book: book, index: resumeIndex, ms: resumeMs, resume: resume);
    // Keep playback pending so the widget check does not open the media page.
    return Completer<bool>().future;
  }

  @override
  Book? get book => null;
  @override
  int get index => 0;
  @override
  bool get loaded => false;
  @override
  bool get loading => false;
  @override
  bool get isPlaying => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String? _captureFont;

Widget _host(Widget child, {_Player? player}) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: SearchHistoryStore.instance),
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider.value(value: FollowStore.instance),
    ChangeNotifierProvider.value(value: CacheStore.instance),
    ChangeNotifierProvider<BookPlayer>.value(value: player ?? _Player()),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark().copyWith(
      textTheme: AppTheme.dark().textTheme.apply(fontFamily: _captureFont),
      appBarTheme: AppTheme.dark().appBarTheme.copyWith(
        titleTextStyle: AppTheme.dark().appBarTheme.titleTextStyle?.copyWith(
          fontFamily: _captureFont,
        ),
      ),
      chipTheme: AppTheme.dark().chipTheme.copyWith(
        labelStyle: AppTheme.dark().chipTheme.labelStyle?.copyWith(
          fontFamily: _captureFont,
        ),
      ),
    ),
    home: child,
  ),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'abts_shelf': '[]'});
    await ShelfStore.instance.load();
    await SearchHistoryStore.instance.clear();
  });

  testWidgets(
    'legacy search defaults to audiobook; mode changes rerun keyword',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(
        _host(SearchPage(initialKeyword: '三体', api: api)),
      );
      await tester.pumpAndSettle();
      expect(api.requests.single.mode, ContentMode.audiobook);
      expect(find.text('audiobook 第 1 页'), findsOneWidget);
      await tester.tap(find.text('听歌'));
      await tester.pumpAndSettle();
      expect(api.requests.last.mode, ContentMode.music);
      expect(find.text('music 第 1 页'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(api.requests.last.mode, ContentMode.music);
      expect(
        api.requests.any(
          (request) => request.page == 2 && request.mode == ContentMode.music,
        ),
        isTrue,
      );
      await tester.tap(find.text('听现场'));
      await tester.pumpAndSettle();
      expect(api.requests.last.mode, ContentMode.concert);
    },
  );

  testWidgets('discover song category and more search preserve content mode', (
    tester,
  ) async {
    final api = _Api();
    await tester.pumpWidget(_host(DiscoverPage(api: api)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('热门听书'), findsOneWidget);
    expect(find.text('推荐测试作品'), findsOneWidget);
    await tester.tap(find.text('听歌'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(api.requests.last.mode, ContentMode.music);
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    expect(api.requests.last.keyword, '歌曲 现场 MV');
    expect(api.requests.last.mode, ContentMode.music);
    final selected = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '听歌'),
    );
    expect(selected.selected, isTrue);
  });

  testWidgets(
    'UP category replaces old results and retains selection on failure',
    (tester) async {
      final api = _Api()..deferUsers = true;
      await tester.pumpWidget(
        _host(SearchPage(initialKeyword: '三体', api: api)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('UP 主'));
      await tester.pump();
      expect(find.text('audiobook 第 1 页'), findsNothing);
      api.pendingUsers.single.complete(const [
        UpUser(mid: 17, name: '测试 UP 主'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('测试 UP 主'), findsOneWidget);
      expect(find.text('audiobook 第 1 页'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, '听书'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UP 主'));
      await tester.pump();
      api.pendingUsers.last.completeError(Exception('网络不可用'));
      await tester.pumpAndSettle();
      expect(find.text('audiobook 第 1 页'), findsNothing);
      expect(find.text('测试 UP 主'), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'UP 主'))
            .selected,
        isTrue,
      );
      expect(find.text('重试'), findsOneWidget);
    },
  );

  testWidgets(
    'UP song listing, pagination and details retain selected content mode',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(
        _host(
          UpHomePage(
            up: const UpUser(mid: 17, name: '音乐 UP'),
            contentMode: ContentMode.music,
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.upRequests.single.mode, ContentMode.music);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(api.upRequests.last, (page: 2, mode: ContentMode.music));
      await tester.tap(find.text('UP 的短歌').first);
      await tester.pumpAndSettle();
      expect(api.detailMode, ContentMode.music);
      expect(find.text('歌曲详情'), findsOneWidget);
    },
  );

  testWidgets('outdated search response cannot replace newly selected mode', (
    tester,
  ) async {
    final api = _Api()..defer = true;
    await tester.pumpWidget(_host(SearchPage(initialKeyword: '现场', api: api)));
    await tester.pump();
    await tester.tap(find.text('听歌'));
    await tester.pump();
    api.pending[1].complete([_book(ContentMode.music, '最新歌曲条目')]);
    await tester.pumpAndSettle();
    api.pending[0].complete([_book(ContentMode.audiobook, '过时听书结果')]);
    await tester.pumpAndSettle();
    expect(find.text('最新歌曲条目'), findsOneWidget);
    expect(find.text('过时听书结果'), findsNothing);
  });

  testWidgets('late song pagination cannot append to concert search results', (
    tester,
  ) async {
    final api = _Api();
    await tester.pumpWidget(
      _host(
        SearchPage(
          initialKeyword: '现场',
          initialMode: ContentMode.music,
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    api.defer = true;
    await tester.drag(find.byType(ListView).first, const Offset(0, -4000));
    await tester.pump();
    expect(api.requests.last, (
      keyword: '现场',
      page: 2,
      mode: ContentMode.music,
    ));
    await tester.tap(find.text('听现场'));
    await tester.pump();
    api.pending.last.complete([_book(ContentMode.concert, '当前演唱会结果')]);
    await tester.pumpAndSettle();
    api.pending.first.complete([_book(ContentMode.music, '迟到的歌曲分页')]);
    await tester.pumpAndSettle();
    expect(find.text('当前演唱会结果'), findsOneWidget);
    expect(find.text('迟到的歌曲分页'), findsNothing);
  });

  testWidgets('pagination retry retains submitted keyword, page and mode', (
    tester,
  ) async {
    final api = _Api();
    await tester.pumpWidget(
      _host(
        SearchPage(
          initialKeyword: '原歌曲',
          initialMode: ContentMode.music,
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '未提交的新词');
    api.defer = true;
    await tester.drag(find.byType(ListView).first, const Offset(0, -4000));
    await tester.pump();
    api.pending.single.completeError(Exception('temporary network failure'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    api.defer = false;
    await tester.ensureVisible(find.text('重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(api.requests.last, (
      keyword: '原歌曲',
      page: 2,
      mode: ContentMode.music,
    ));
    expect(api.requests.where((request) => request.page == 2), hasLength(2));
  });

  testWidgets(
    'switching to UP results ignores older video response and preserves mode',
    (tester) async {
      final api = _Api()..defer = true;
      await tester.pumpWidget(
        _host(
          SearchPage(
            initialKeyword: '现场',
            initialMode: ContentMode.concert,
            api: api,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('UP 主'));
      await tester.pumpAndSettle();
      expect(find.text('测试 UP 主'), findsOneWidget);
      api.pending.single.complete([_book(ContentMode.concert, '旧视频结果')]);
      await tester.pumpAndSettle();
      expect(find.text('旧视频结果'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, '听现场'));
      await tester.pump();
      expect(api.requests.last.mode, ContentMode.concert);
      api.pending.last.complete([_book(ContentMode.concert, '新演唱会结果')]);
      await tester.pumpAndSettle();
      expect(find.text('新演唱会结果'), findsOneWidget);
    },
  );

  testWidgets(
    'import shows validation error, retains input and adds selected mode',
    (tester) async {
      final api = _Api();
      final resolver = _Resolver()..fail = true;
      ({Book book, int? page})? imported;
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  imported = await showDialog<({Book book, int? page})>(
                    context: context,
                    builder: (_) =>
                        ResourceImportDialog(api: api, resolver: resolver),
                  );
                },
                child: const Text('打开导入'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开导入'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'invalid input');
      await tester.tap(find.text('添加资源'));
      await tester.pumpAndSettle();
      expect(find.text('请输入有效的 B 站链接或 BV 号'), findsOneWidget);
      expect(find.text('invalid input'), findsOneWidget);
      expect(ShelfStore.instance.books, isEmpty);
      resolver.fail = false;
      await tester.enterText(find.byType(TextField), 'BV1xx411c7mD');
      await tester.tap(find.text('听现场'));
      await tester.tap(find.text('添加资源'));
      await tester.pumpAndSettle();
      expect(api.detailMode, ContentMode.concert);
      expect(imported?.page, 2);
      expect(
        ShelfStore.instance.byBvid('BV1xx411c7mD')!.book.contentMode,
        ContentMode.concert,
      );
    },
  );

  testWidgets('invalid part and network failure never add a resource', (
    tester,
  ) async {
    final api = _Api();
    final resolver = _Resolver()..page = 3;
    await tester.pumpWidget(
      _host(
        Scaffold(
          body: ResourceImportDialog(
            api: api,
            resolver: resolver,
            initialMode: ContentMode.concert,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'https://www.bilibili.com/video/BV1xx411c7mD?p=3',
    );
    await tester.tap(find.text('添加资源'));
    await tester.pumpAndSettle();
    expect(find.text('链接中的分 P 不存在，请检查 p 参数'), findsOneWidget);
    expect(ShelfStore.instance.books, isEmpty);
    resolver.error = DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionError,
    );
    await tester.tap(find.text('添加资源'));
    await tester.pumpAndSettle();
    expect(find.text('网络连接失败，请检查网络后重试'), findsOneWidget);
    expect(ShelfStore.instance.books, isEmpty);
  });

  testWidgets('plain BV import leaves normal resume policy in effect', (
    tester,
  ) async {
    ({Book book, int? page})? imported;
    final resolver = _Resolver()..page = null;
    await tester.pumpWidget(
      _host(
        Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                imported = await showDialog<({Book book, int? page})>(
                  context: context,
                  builder: (_) => ResourceImportDialog(
                    api: _Api(),
                    resolver: resolver,
                    initialMode: ContentMode.concert,
                  ),
                );
              },
              child: const Text('打开导入'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'BV1xx411c7mD');
    await tester.tap(find.text('添加资源'));
    await tester.pumpAndSettle();
    expect(imported, isNotNull);
    expect(imported!.page, isNull);
    expect(imported!.book.contentMode, ContentMode.concert);
  });

  for (final mode in ContentMode.values) {
    testWidgets(
      'detail ${mode.name} presents its resume policy and explicit part',
      (tester) async {
        final book = _book(mode, '模式详情');
        await ShelfStore.instance.add(
          book,
          withProgress: ShelfBook(
            book: book,
            lastChapterIndex: 1,
            lastCid: 12,
            positionMs: 42000,
          ),
        );
        await tester.pumpWidget(
          _host(
            BookDetailPage(
              bvid: book.bvid,
              contentMode: mode,
              initialBook: book,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final detailTitle = switch (mode) {
          ContentMode.audiobook => '听书详情',
          ContentMode.music => '歌曲详情',
          ContentMode.concert => '演唱会详情',
        };
        expect(find.text(detailTitle), findsOneWidget);
        expect(
          find.text(mode.resumesPosition ? '继续收听' : '开始收听'),
          findsOneWidget,
        );
        if (!mode.resumesPosition) expect(find.text('继续收听'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _host(
            BookDetailPage(
              bvid: book.bvid,
              contentMode: mode,
              initialBook: book,
              initialPage: 2,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('播放第 2 ${mode.unitLabel}'), findsOneWidget);
      },
    );
  }

  testWidgets('uncollected concert offers continuation from recent progress', (
    tester,
  ) async {
    final book = _book(ContentMode.concert, '未收藏的演唱会');
    await ShelfStore.instance.updateProgress(
      book.bvid,
      book: book,
      cid: 12,
      chapterIndex: 1,
      positionMs: 42000,
      chapterDurationMs: 180000,
    );
    expect(ShelfStore.instance.isOnShelf(book.bvid), isFalse);
    await tester.pumpWidget(
      _host(
        BookDetailPage(
          bvid: book.bvid,
          contentMode: ContentMode.concert,
          initialBook: book,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('继续收听'), findsOneWidget);
    expect(find.text('第 2 段 · 00:42'), findsOneWidget);
    expect(ShelfStore.instance.isOnShelf(book.bvid), isFalse);
  });

  testWidgets('concert at a later part zero seconds continues that part', (
    tester,
  ) async {
    final book = Book(
      bvid: 'BV1xx411c7mD',
      aid: 1,
      title: '演唱会第三分 P',
      pic: '',
      contentMode: ContentMode.concert,
      pages: 3,
      chapters: List.generate(
        3,
        (i) => Chapter(
          cid: 11 + i,
          page: i + 1,
          part: '演唱会分 P ${i + 1}',
          duration: 180,
        ),
      ),
    );
    await ShelfStore.instance.updateProgress(
      book.bvid,
      book: book,
      cid: 13,
      chapterIndex: 2,
      positionMs: 0,
      chapterDurationMs: 180000,
    );
    final player = _Player();
    await tester.pumpWidget(
      _host(
        BookDetailPage(
          bvid: book.bvid,
          contentMode: ContentMode.concert,
          initialBook: book,
        ),
        player: player,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('继续收听'), findsOneWidget);
    expect(find.text('第 3 段 · 00:00'), findsOneWidget);
    await tester.tap(find.text('继续收听'));
    await tester.pump();
    expect(player.selection?.index, 2);
    expect(player.selection?.ms, 0);
    expect(player.selection?.resume, isTrue);
  });

  testWidgets(
    'capture mobile mode search and import layout',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final font = File('/System/Library/Fonts/PingFang.ttc');
        if (await font.exists()) {
          final loader = FontLoader('CaptureChinese')
            ..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            );
          await loader.load();
          _captureFont = 'CaptureChinese';
        }
        final icons = File(
          '/private/tmp/abts-flutter-sdk/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        );
        if (await icons.exists()) {
          final loader = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(ByteData.sublistView(await icons.readAsBytes())),
            );
          await loader.load();
        }
      });
      final key = GlobalKey();
      final api = _Api()..resultTitle = '周杰伦《晴天》· 现场演唱';
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: _host(
            SearchPage(
              initialKeyword: '周杰伦',
              initialMode: ContentMode.music,
              api: api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(
        tester,
        key,
        '/private/tmp/abts-validation/search-modes-mobile.png',
      );
      await tester.tap(find.byTooltip('添加 B 站资源'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '听现场').last);
      await tester.enterText(
        find.byType(TextField).last,
        'https://www.bilibili.com/video/BV1xx411c7mD?p=2',
      );
      await tester.pumpAndSettle();
      await _capture(
        tester,
        key,
        '/private/tmp/abts-validation/import-modes-mobile.png',
      );
      expect(tester.takeException(), isNull);
      _captureFont = null;
    },
    skip: Platform.environment['ABTS_CAPTURE_UI'] != '1',
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String path) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
