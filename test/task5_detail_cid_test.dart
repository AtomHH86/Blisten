import 'dart:async';
import 'dart:convert';

import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/chapter.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/book_detail_page.dart';
import 'package:blisten/pages/player_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _chapters = [
  Chapter(cid: 101, page: 1, part: '第一段', duration: 90),
  Chapter(cid: 102, page: 2, part: '第二段', duration: 90),
  Chapter(cid: 103, page: 3, part: '第三段', duration: 90),
];

class _Player extends ChangeNotifier implements BookPlayer {
  Book? activeBook;
  Completer<bool>? pendingPlay;
  final calls = <({int index, int ms, int? cid, bool resume})>[];
  @override
  Book? get book => activeBook;
  @override
  bool get loaded => activeBook != null;
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  void flushProgress() {}
  @override
  List<Chapter> get chapters => activeBook?.chapters ?? [];
  @override
  Chapter? get currentChapter => chapters.isEmpty ? null : chapters.first;
  @override
  int get index => 0;
  @override
  bool get isPlaying => false;
  @override
  bool get isOffline => false;
  @override
  bool get hasNext => false;
  @override
  bool get hasPrev => false;
  @override
  bool get currentCached => false;
  @override
  bool get stopAtChapterEnd => false;
  @override
  Duration get sleepRemaining => Duration.zero;
  @override
  double get rate => 1;
  @override
  String get rateLabel => '1.0x';
  @override
  Duration get currentDuration => const Duration(seconds: 90);
  @override
  final positionTick = ValueNotifier(Duration.zero);
  @override
  void dispose() {
    positionTick.dispose();
    super.dispose();
  }
  @override
  Future<bool> playBook(Book book, {int resumeIndex = 0, int resumeMs = 0,
      int? resumeCid, bool resume = true}) async {
    calls.add((index: resumeIndex, ms: resumeMs, cid: resumeCid, resume: resume));
    return await (pendingPlay?.future ?? Future.value(false));
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

void main() {
  Future<_Player> showDetail(WidgetTester tester, {ContentMode mode = ContentMode.concert,
      int? initialPage, List<Chapter>? directory, bool alreadyLoaded = false,
      _Routes? observer, GlobalKey<NavigatorState>? navigator}) async {
    final full = Book(bvid: 'BV1DETAIL003', aid: 1, title: '详情续播作品', pic: '',
        pages: 3, contentMode: mode, chapters: directory ?? _chapters);
    final partial = Book(bvid: full.bvid, aid: 1, title: full.title, pic: '',
        pages: 3, contentMode: mode, chapters: [_chapters.last]);
    SharedPreferences.setMockInitialValues({
      'abts_shelf': '[]',
      'abts_recent_progress': jsonEncode([ShelfBook(book: partial,
          lastCid: 103, lastChapterIndex: 0, positionMs: 12000,
          chapterDurationMs: 90000, chaptersComplete: false).toJson()]),
    });
    await ShelfStore.instance.load();
    final player = _Player()..activeBook = alreadyLoaded ? full.withChapters(_chapters) : null;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      player.dispose();
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ShelfStore.instance),
        ChangeNotifierProvider.value(value: CacheStore.instance),
        ChangeNotifierProvider<BookPlayer>.value(value: player),
      ],
      child: MaterialApp(theme: AppTheme.light(), navigatorKey: navigator,
          navigatorObservers: [?observer], home: BookDetailPage(
        bvid: full.bvid, contentMode: mode, initialPage: initialPage, initialBook: full,
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('第三段'), findsOneWidget);
    return player;
  }

  testWidgets('full detail resumes partial-directory progress by saved P3 CID', (tester) async {
    final player = await showDetail(tester);
    await tester.tap(find.text('继续收听'));
    await tester.pumpAndSettle();
    expect(player.calls.single.cid, 103);
    expect(player.calls.single.index, 2);
    expect(player.calls.single.ms, 12000);
  });

  testWidgets('explicit detail P1 selection takes priority over saved P3 progress', (tester) async {
    final player = await showDetail(tester, initialPage: 1);
    await tester.tap(find.text('播放第 1 段'));
    await tester.pumpAndSettle();
    expect(player.calls.single, (index: 0, ms: 0, cid: 101, resume: true));
  });

  testWidgets('music detail selection still starts from the beginning', (tester) async {
    final player = await showDetail(tester, mode: ContentMode.music);
    await tester.tap(find.text('开始收听'));
    await tester.pumpAndSettle();
    expect(player.calls.single, (index: 0, ms: 0, cid: null, resume: false));
  });

  testWidgets('chapter row sends its CID when fresh detail order differs from loaded order', (tester) async {
    final player = await showDetail(tester, alreadyLoaded: true,
        directory: [_chapters[2], _chapters[0], _chapters[1]]);
    await tester.tap(find.text('第三段'));
    await tester.pumpAndSettle();
    expect(player.calls.single, (index: 0, ms: 0, cid: 103, resume: true));
  });

  testWidgets('loaded detail mini bar opens once for rapid taps and works again after return', (tester) async {
    final observer = _Routes();
    final navigator = GlobalKey<NavigatorState>();
    await showDetail(tester, alreadyLoaded: true, observer: observer, navigator: navigator);
    final mini = find.text('第 1 段 · 第一段');
    expect(mini, findsOneWidget);
    // The new route already absorbs the second pointer event. This preserves
    // existing behavior; the pending-chapter case below is the observed RED.
    final location = tester.getCenter(mini);
    await tester.tapAt(location);
    await tester.tapAt(location);
    await tester.pumpAndSettle();
    expect(observer.pushes, 2); // home + one player
    expect(find.byType(PlayerPage), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailPage), findsOneWidget);
    await tester.tap(mini);
    await tester.pumpAndSettle();
    expect(observer.pushes, 3);
    expect(find.byType(PlayerPage), findsOneWidget);
  });

  testWidgets('loaded mini bar cannot open a player while a chapter submission is pending', (tester) async {
    final observer = _Routes();
    final player = await showDetail(tester, alreadyLoaded: true, observer: observer);
    final pending = Completer<bool>();
    player.pendingPlay = pending;
    await tester.tap(find.text('第三段'));
    await tester.pump();
    expect(player.calls, hasLength(1));
    await tester.tap(find.text('第 1 段 · 第一段'));
    await tester.pump();
    expect(observer.pushes, 1);
    expect(find.byType(PlayerPage), findsNothing);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('播放失败，请检查网络后重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('第 1 段 · 第一段'));
    await tester.pumpAndSettle();
    expect(observer.pushes, 2);
    expect(find.byType(PlayerPage), findsOneWidget);
  });
}
