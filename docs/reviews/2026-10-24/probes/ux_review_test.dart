// Standalone review tests live outside test/ to keep known-failing probes out of daily checks.
// ignore_for_file: invalid_use_of_visible_for_testing_member
// Review-only regression probes. Assertions describe the desired behavior;
// failures on the reviewed commit are evidence, not production test fixes.
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

final _book = Book(
  bvid: 'BV1xx411c7mD',
  aid: 1,
  title: 'Review 测试作品',
  pic: '',
  chapters: [Chapter(cid: 11, page: 1, part: 'Review 失败章节', duration: 180)],
);

class _Player extends ChangeNotifier implements BookPlayer {
  Book? activeBook;
  Duration timer = Duration.zero;
  bool failed = false;
  int playCalls = 0;

  @override
  Book? get book => activeBook;
  @override
  bool get loaded => activeBook != null;
  @override
  bool get loading => false;
  @override
  String? get error => failed ? 'Controlled review failure' : null;
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
  Duration get sleepRemaining => timer;
  @override
  bool get currentCached => false;
  @override
  int get index => 0;
  @override
  bool get isPlaying => false;
  @override
  void flushProgress() {}

  @override
  Future<bool> playBook(
    Book book, {
    int resumeIndex = 0,
    int resumeMs = 0,
    bool resume = true,
  }) async {
    playCalls++;
    failed = true;
    notifyListeners();
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget page, _Player player, {double scale = 1}) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider.value(value: CacheStore.instance),
    ChangeNotifierProvider<BookPlayer>.value(value: player),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: child!,
    ),
    home: page,
  ),
);

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openSleepSheet(WidgetTester tester) async {
  final action = find.widgetWithIcon(ActionChip, Icons.bedtime_outlined);
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'abts_shelf': '[]',
      'abts_recent_progress': '[]',
    });
    await ShelfStore.instance.load();
    AppTheme.mode = ThemeMode.light;
  });
  tearDown(() => AppTheme.mode = ThemeMode.system);

  testWidgets('failed detail chapter playback never reports playing', (
    tester,
  ) async {
    final player = _Player();
    await tester.pumpWidget(
      _host(BookDetailPage(bvid: _book.bvid, initialBook: _book), player),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review 失败章节'));
    await tester.tap(find.text('Review 失败章节'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(player.playCalls, 1);
    expect(player.error, isNotNull);
    expect(find.textContaining('正在播放第 1 章'), findsNothing);
  });

  for (final width in [320.0, 360.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'player sleep sheet fits ${width.toInt()}dp at ${(scale * 100).toInt()}% text',
        (tester) async {
          _screen(tester, Size(width, 640));
          final player = _Player()..activeBook = _book;
          await tester.pumpWidget(
            _host(const PlayerPage(), player, scale: scale),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _openSleepSheet(tester);
          expect(tester.takeException(), isNull);
          final finalOption = find.text('2 小时');
          await tester.ensureVisible(finalOption);
          await tester.pumpAndSettle();
          expect(finalOption.hitTestable(), findsOneWidget);
        },
      );
    }
  }

  testWidgets('10 minute sleep timer marks exactly one preset selected', (
    tester,
  ) async {
    // Enough height to isolate the selection bug from the separate overflow.
    _screen(tester, const Size(800, 1400));
    final player = _Player()
      ..activeBook = _book
      ..timer = const Duration(minutes: 10);
    await tester.pumpWidget(_host(const PlayerPage(), player));
    await tester.pumpAndSettle();
    await _openSleepSheet(tester);
    expect(tester.takeException(), isNull);
    final checkedOptions = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byIcon(Icons.check),
    );
    expect(checkedOptions, findsOneWidget);
  });
}
