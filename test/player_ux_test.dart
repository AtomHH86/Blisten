import 'dart:async';

import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/chapter.dart';
import 'package:blisten/pages/book_detail_page.dart';
import 'package:blisten/pages/player_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bvid = 'BV1xx411c7mD';
final _book = Book(
  bvid: _bvid,
  aid: 1,
  title: '测试收藏',
  pic: '',
  chapters: [Chapter(cid: 11, page: 1, part: '测试分 P', duration: 180)],
);

class _Player extends ChangeNotifier implements BookPlayer {
  int retries = 0;
  bool pending = false;
  bool failed = false;
  String? failureReason;
  Book? activeBook;
  final retryResult = Completer<bool>();

  @override
  Book? get book => activeBook;
  @override
  bool get loaded => activeBook != null;
  @override
  List<Chapter> get chapters => activeBook?.chapters ?? [];
  @override
  Chapter? get currentChapter => chapters.isEmpty ? null : chapters.first;
  @override
  final positionTick = ValueNotifier(Duration.zero);
  @override
  Duration get currentDuration => const Duration(seconds: 180);
  @override
  bool get isOffline => false;
  @override
  bool get hasNext => false;
  @override
  bool get hasPrev => false;
  @override
  double get rate => 1;
  @override
  String get rateLabel => '1.0x';
  @override
  bool get stopAtChapterEnd => false;
  @override
  Duration get sleepRemaining => Duration.zero;
  @override
  bool get currentCached => false;
  @override
  bool get loading => pending;
  @override
  String? get error =>
      failed ? failureReason ?? 'internal diagnostic must not be sole guidance' : null;
  @override
  int get index => 0;
  @override
  bool get isPlaying => false;
  @override
  void flushProgress() {}

  @override
  Future<bool> playBook(Book book, {int resumeIndex = 0, int resumeMs = 0,
      int? resumeCid, bool resume = true}) async {
    failed = true;
    notifyListeners();
    return false;
  }

  @override
  Future<bool> retryPlayback() async {
    retries++;
    pending = true;
    notifyListeners();
    final result = await retryResult.future;
    pending = false;
    failed = !result;
    notifyListeners();
    return result;
  }

  @override
  Future<void> removeFromShelf(String bvid) => ShelfStore.instance.remove(bvid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(
  Widget child,
  _Player player, {
  ThemeMode mode = ThemeMode.dark,
  double scale = 1,
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider.value(value: CacheStore.instance),
    ChangeNotifierProvider<BookPlayer>.value(value: player),
  ],
  child: MaterialApp(
    theme: mode == ThemeMode.light ? AppTheme.light() : AppTheme.dark(),
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
      'abts_recent_progress': '[]',
    });
    await ShelfStore.instance.load();
  });

  Future<void> showDetail(WidgetTester tester) async {
    await ShelfStore.instance.add(
      _book,
      withProgress: ShelfBook(
        book: _book,
        lastCid: 11,
        positionMs: 42000,
        lastListenedAt: 1,
        doneCids: [11],
      ),
    );
    await tester.pumpWidget(
      _host(BookDetailPage(bvid: _bvid, initialBook: _book), _Player()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.collections_bookmark_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets('cancel detail removal retains collection and progress', (
    tester,
  ) async {
    await showDetail(tester);
    expect(find.textContaining('收听进度保留在最近收听中'), findsOneWidget);
    expect(ShelfStore.instance.isOnShelf(_bvid), isTrue);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(ShelfStore.instance.isOnShelf(_bvid), isTrue);
    expect(ShelfStore.instance.progressByBvid(_bvid)!.positionMs, 42000);
    expect(ShelfStore.instance.progressByBvid(_bvid)!.doneCids, [11]);
  });

  testWidgets(
    'detail removal requires confirmation and keeps recent progress',
    (tester) async {
      await showDetail(tester);
      expect(ShelfStore.instance.progressByBvid(_bvid), isNotNull);
      await tester.tap(find.text('移出'));
      await tester.pumpAndSettle();
      expect(ShelfStore.instance.isOnShelf(_bvid), isFalse);
      expect(ShelfStore.instance.progressByBvid(_bvid)!.positionMs, 42000);
      expect(ShelfStore.instance.progressByBvid(_bvid)!.doneCids, [11]);
    },
  );

  testWidgets(
    'playback failure has an executable retry with in-place loading',
    (tester) async {
      final player = _Player()..failed = true;
      await tester.pumpWidget(_host(const PlayerPage(), player));
      expect(find.text('暂时无法播放'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(player.retries, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      player.retryResult.complete(true);
      await tester.pumpAndSettle();
      expect(player.error, isNull);
    },
  );

  for (final loaded in [false, true]) {
    testWidgets('platform limit is explained without retry in player loaded=$loaded',
        (tester) async {
      final player = _Player()
        ..failed = true
        ..failureReason = 'iOS 预览版暂未开放在线播放'
        ..activeBook = loaded ? _book : null;
      await tester.pumpWidget(_host(const PlayerPage(), player));
      await tester.pumpAndSettle();
      expect(find.text('iOS 预览版暂未开放在线播放'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(find.byTooltip('重试播放'), findsNothing);
      expect(find.text('请重试，或返回后选择其他内容。'), findsNothing);
    });
  }

  testWidgets('platform limit reaches the detail playback failure message',
      (tester) async {
    final player = _Player()..failureReason = 'iOS 预览版暂未开放在线播放';
    await tester.pumpWidget(
      _host(BookDetailPage(bvid: _bvid, initialBook: _book), player),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始收听'));
    await tester.pumpAndSettle();
    expect(find.text('iOS 预览版暂未开放在线播放'), findsOneWidget);
    expect(find.text('播放失败，请检查网络后重试'), findsNothing);
  });

  testWidgets('detail platform limit does not offer a retry for an existing session',
      (tester) async {
    final player = _Player()
      ..activeBook = _book
      ..failed = true
      ..failureReason = 'iOS 预览版暂未开放在线播放';
    await tester.pumpWidget(
      _host(BookDetailPage(bvid: _bvid, initialBook: _book), player),
    );
    await tester.pumpAndSettle();
    expect(find.text('iOS 预览版暂未开放在线播放'), findsOneWidget);
    expect(find.byTooltip('重试播放'), findsNothing);
  });

  testWidgets('unrecognized detail playback errors keep safe generic guidance',
      (tester) async {
    final player = _Player()..failureReason = 'private diagnostic https://internal.invalid';
    await tester.pumpWidget(
      _host(BookDetailPage(bvid: _bvid, initialBook: _book), player),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始收听'));
    await tester.pumpAndSettle();
    expect(find.text('播放失败，请检查网络后重试'), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);
  });

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets(
      'player controls remain reachable at 320dp and 200% text in ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppTheme.mode = mode;
        addTearDown(() => AppTheme.mode = ThemeMode.dark);
        final player = _Player()..activeBook = _book;
        await tester.pumpWidget(
          _host(const PlayerPage(), player, mode: mode, scale: 2),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final playButton = find.byIcon(Icons.play_arrow_rounded);
        await tester.ensureVisible(playButton);
        final mainControl = find.ancestor(
          of: playButton,
          matching: find.byType(InkResponse),
        );
        expect(tester.getSize(mainControl).width, greaterThanOrEqualTo(64));
        expect(tester.getSize(mainControl).height, greaterThanOrEqualTo(64));
        final backButton = find.byTooltip('后退 15 秒');
        expect(tester.getSize(backButton).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(backButton).height, greaterThanOrEqualTo(48));
        await tester.ensureVisible(find.widgetWithText(ActionChip, '睡眠定时'));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'detail preserves readable long title at 320dp and 200% text in ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppTheme.mode = mode;
        addTearDown(() => AppTheme.mode = ThemeMode.dark);
        final book = Book(
          bvid: _bvid,
          aid: 1,
          pic: '',
          title: '很长的中文标题也能在详情中完整阅读，不会被固定高度截断',
          chapters: _book.chapters,
        );
        await tester.pumpWidget(
          _host(
            BookDetailPage(bvid: _bvid, initialBook: book),
            _Player(),
            mode: mode,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        final title = tester.widget<Text>(find.text(book.cleanTitle));
        expect(title.maxLines, isNull);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('开始收听'), findsOneWidget);
      },
    );
  }
}
