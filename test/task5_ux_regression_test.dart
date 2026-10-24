import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/services.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member
// Migrated Task 5 regression probes retain their original assertions.
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/chapter.dart';
import 'package:blisten/pages/book_detail_page.dart';
import 'package:blisten/pages/player_page.dart';
import 'package:blisten/pages/sleep_timer_page.dart';
import 'package:blisten/pages/recent_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  Duration selectedTimer = Duration.zero;
  @override
  Duration get sleepTimerDuration => selectedTimer;
  @override
  DateTime? get sleepTimerDeadline => selectedTimer > Duration.zero
      ? DateTime.utc(2026, 10, 24, 12).add(selectedTimer) : null;
  bool failed = false;
  int playCalls = 0;
  Completer<bool>? pendingPlay;
  bool playing = false;
  int timerCalls = 0;

  @override
  void setSleepTimer(Duration duration) {
    timerCalls++;
    timer = duration;
    selectedTimer = duration;
    notifyListeners();
  }

  @override
  void cancelSleepTimer() {
    timer = Duration.zero;
    selectedTimer = Duration.zero;
    notifyListeners();
  }

  @override
  void setStopAtChapterEnd(bool value) {}

  @override
  Future<bool> resumeShelf(ShelfBook item) => playBook(item.book);


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
  bool get isPlaying => playing;
  @override
  void flushProgress() {}

  @override
  Future<bool> playBook(
    Book book, {
    int resumeIndex = 0,
    int resumeMs = 0, int? resumeCid,
    bool resume = true,
  }) async {
    playCalls++;
    final result = await (pendingPlay?.future ?? Future.value(false));
    failed = !result;
    if (result) activeBook = book;
    notifyListeners();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget page, _Player player, {double scale = 1,
  GlobalKey<NavigatorState>? navigatorKey, NavigatorObserver? observer,
  ThemeMode mode = ThemeMode.light}) {
  AppTheme.mode = mode;
  return MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider.value(value: CacheStore.instance),
    ChangeNotifierProvider<BookPlayer>.value(value: player),
  ],
  child: MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: [?observer],
    theme: mode == ThemeMode.dark ? AppTheme.dark() : AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: child!,
    ),
    home: page,
  ),
);
}

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

class _Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

Future<void> _customDialog(WidgetTester tester) async {
  final custom = find.text('自定义时长');
  await tester.scrollUntilVisible(custom, 180);
  await tester.tap(custom);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
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
      ..timer = const Duration(minutes: 10)
      ..selectedTimer = const Duration(minutes: 10);
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

  for (final value in ['', '0', '721', '-1', '1.5']) {
    for (final submitKey in [false, true]) {
      testWidgets('custom timer rejects "$value" via ${submitKey ? 'keyboard' : 'button'} without closing', (tester) async {
        final player = _Player()..activeBook = _book;
        await tester.pumpWidget(_host(const SleepTimerPage(), player));
        await tester.pumpAndSettle();
        await _customDialog(tester);
        await tester.enterText(find.byType(TextField), value);
        if (submitKey) {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        } else {
          await tester.tap(find.text('设置定时'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, value);
        expect(field.decoration!.errorText, isNotNull);
        expect(field.decoration!.errorText, isNotEmpty);
        expect(player.timerCalls, 0);
      });
    }
  }

  for (final minutes in [1, 720]) {
    testWidgets('custom timer accepts inclusive boundary $minutes', (tester) async {
      final player = _Player()..activeBook = _book;
      await tester.pumpWidget(_host(const SleepTimerPage(), player));
      await tester.pumpAndSettle();
      await _customDialog(tester);
      await tester.enterText(find.byType(TextField), '$minutes');
      await tester.tap(find.text('设置定时'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(player.timer, Duration(minutes: minutes));
      expect(player.timerCalls, 1);
    });
  }

  testWidgets('off remains usable without loaded media', (tester) async {
    final player = _Player()..timer = const Duration(minutes: 10)
      ..selectedTimer = const Duration(minutes: 10);
    await tester.pumpWidget(_host(const SleepTimerPage(), player));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭定时'));
    await tester.pumpAndSettle();
    expect(player.timer, Duration.zero);
  });

  testWidgets('detail duplicate primary submits make one call and push one player', (tester) async {
    final player = _Player()..pendingPlay = Completer<bool>();
    final observer = _Routes();
    await tester.pumpWidget(_host(BookDetailPage(bvid: _book.bvid, initialBook: _book), player, observer: observer));
    await tester.pumpAndSettle();
    final play = find.byType(FilledButton).first;
    await tester.tap(play);
    await tester.pump();
    await tester.tap(play);
    await tester.pump();
    expect(player.playCalls, 1);
    player.pendingPlay!.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(observer.pushes, 2);
  });

  testWidgets('failed primary playback remains on detail with actionable feedback', (tester) async {
    final player = _Player();
    await tester.pumpWidget(_host(BookDetailPage(bvid: _book.bvid, initialBook: _book), player));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    expect(player.playCalls, 1);
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.byType(BookDetailPage), findsOneWidget);
    expect(find.textContaining('重试'), findsWidgets);
  });

  testWidgets('detail chapter false result has visible failure guidance', (tester) async {
    final player = _Player();
    await tester.pumpWidget(_host(BookDetailPage(bvid: _book.bvid, initialBook: _book), player));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review 失败章节'));
    await tester.tap(find.text('Review 失败章节'));
    await tester.pumpAndSettle();
    expect(find.textContaining('正在播放第 1 章'), findsNothing);
    expect(find.textContaining('重试'), findsWidgets);
  });

  testWidgets('loaded but paused chapter never claims to be playing', (tester) async {
    final player = _Player()..pendingPlay = Completer<bool>();
    await tester.pumpWidget(_host(BookDetailPage(bvid: _book.bvid, initialBook: _book), player));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review 失败章节'));
    await tester.tap(find.text('Review 失败章节'));
    player.pendingPlay!.complete(true);
    await tester.pumpAndSettle();
    expect(player.isPlaying, isFalse);
    expect(find.textContaining('正在播放第 1 章'), findsNothing);
  });

  for (final recent in [false, true]) {
    testWidgets('${recent ? 'recent resume' : 'detail play'} completion cannot cover a newly opened route', (tester) async {
      if (recent) {
        await ShelfStore.instance.add(_book, withProgress: ShelfBook(book: _book, lastCid: 11, positionMs: 42000, chapterDurationMs: 180000));
      }
      final player = _Player()..pendingPlay = Completer<bool>();
      final navigator = GlobalKey<NavigatorState>();
      final observer = _Routes();
      await tester.pumpWidget(_host(recent ? const RecentPage() : BookDetailPage(bvid: _book.bvid, initialBook: _book), player, navigatorKey: navigator, observer: observer));
      await tester.pumpAndSettle();
      await tester.tap(recent ? find.byTooltip('继续收听') : find.byType(FilledButton).first);
      await tester.pump();
      unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Unrelated route')))));
      await tester.pumpAndSettle();
      final pushesBeforeCompletion = observer.pushes;
      player.pendingPlay!.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Unrelated route'), findsOneWidget);
      expect(find.byType(PlayerPage), findsNothing);
      expect(observer.pushes, pushesBeforeCompletion);
    });
  }

  testWidgets('recent duplicate resume makes one call and one player route', (tester) async {
    await ShelfStore.instance.add(_book, withProgress: ShelfBook(book: _book, lastCid: 11, positionMs: 42000, chapterDurationMs: 180000));
    final player = _Player()..pendingPlay = Completer<bool>();
    final observer = _Routes();
    await tester.pumpWidget(_host(const RecentPage(), player, observer: observer));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('继续收听'));
    await tester.pump();
    await tester.tap(find.byTooltip('继续收听'));
    await tester.pump();
    expect(player.playCalls, 1);
    player.pendingPlay!.complete(true);
    await tester.pumpAndSettle();
    expect(observer.pushes, 2);
    expect(find.byType(PlayerPage), findsOneWidget);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('standalone timer last action reachable ${mode.name} ${width.toInt()}dp ${(scale * 100).toInt()}%', (tester) async {
          _screen(tester, Size(width, 640));
          final player = _Player()..activeBook = _book;
          await tester.pumpWidget(_host(const SleepTimerPage(), player, mode: mode, scale: scale));
          await tester.pumpAndSettle();
          final custom = find.text('自定义时长');
          await tester.scrollUntilVisible(custom, 160);
          await tester.pumpAndSettle();
          expect(custom.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
        if (mode == ThemeMode.dark) {
          testWidgets('player timer all options reachable dark ${width.toInt()}dp ${(scale * 100).toInt()}%', (tester) async {
            _screen(tester, Size(width, 640));
            final player = _Player()..activeBook = _book;
            await tester.pumpWidget(_host(const PlayerPage(), player, mode: mode, scale: scale));
            await tester.pumpAndSettle();
            await _openSleepSheet(tester);
            expect(tester.takeException(), isNull);
            final finalOption = find.text('2 小时');
            await tester.ensureVisible(finalOption);
            await tester.pumpAndSettle();
            expect(finalOption.hitTestable(), findsOneWidget);
          });
        }
      }
    }
  }

  testWidgets('detail completion after back cannot reopen the player', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final observer = _Routes();
    final player = _Player()..pendingPlay = Completer<bool>();
    await tester.pumpWidget(_host(const Scaffold(body: Text('Origin route')), player, navigatorKey: navigator, observer: observer));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => BookDetailPage(bvid: _book.bvid, initialBook: _book))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    final pushes = observer.pushes;
    player.pendingPlay!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Origin route'), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);
    expect(observer.pushes, pushes);
  });

  testWidgets('recent false result stays on recent and offers retry', (tester) async {
    await ShelfStore.instance.add(_book, withProgress: ShelfBook(book: _book, lastCid: 11, positionMs: 42000, chapterDurationMs: 180000));
    final player = _Player();
    await tester.pumpWidget(_host(const RecentPage(), player));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('继续收听'));
    await tester.pumpAndSettle();
    expect(find.byType(RecentPage), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.textContaining('重试'), findsWidgets);
  });

  for (final panel in ['speed', 'chapter', 'timer']) {
    testWidgets('$panel panel exposes actual selected row semantics and returns focus', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        _screen(tester, const Size(800, 1400));
        final player = _Player()..activeBook = _book..timer = const Duration(minutes: 10)
        ..selectedTimer = const Duration(minutes: 10);
        await tester.pumpWidget(_host(const PlayerPage(), player));
        await tester.pumpAndSettle();
        final icon = switch (panel) {
          'speed' => Icons.speed_rounded,
          'chapter' => Icons.format_list_bulleted,
          _ => Icons.bedtime_outlined,
        };
        final trigger = find.widgetWithIcon(ActionChip, icon);
        await tester.ensureVisible(trigger);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        final row = switch (panel) {
          'speed' => find.widgetWithText(ListTile, '1.0x'),
          'chapter' => find.widgetWithText(ListTile, '1 · Review 失败章节'),
          _ => find.widgetWithText(ListTile, '10 分钟'),
        };
        expect(row, findsOneWidget);
        expect(tester.getSemantics(row).flagsCollection.isSelected, Tristate.isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        final focusedChip = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<ActionChip>();
        expect(focusedChip, same(tester.widget<ActionChip>(trigger)));
      } finally {
        semantics.dispose();
      }
    });
  }

  for (final host in ['page', 'modal']) {
    testWidgets('timer $host selection remains original after countdown crosses a lower preset', (tester) async {
      _screen(tester, const Size(800, 1400));
      final player = _Player()
        ..activeBook = _book
        ..timer = const Duration(minutes: 10)
        ..selectedTimer = const Duration(minutes: 30);
      await tester.pumpWidget(_host(host == 'page' ? const SleepTimerPage() : const PlayerPage(), player));
      await tester.pumpAndSettle();
      if (host == 'modal') await _openSleepSheet(tester);
      final selected = find.descendant(
        of: find.widgetWithText(ListTile, '30 分钟'), matching: find.byIcon(Icons.check));
      expect(selected, findsOneWidget);
      expect(find.descendant(of: find.widgetWithText(ListTile, '10 分钟'),
        matching: find.byIcon(Icons.check)), findsNothing);
      player.timer = const Duration(minutes: 5);
      player.notifyListeners();
      await tester.pump();
      expect(selected, findsOneWidget);
    });
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final panel in ['speed', 'chapter']) {
      for (final width in [320.0, 360.0]) {
        testWidgets('$panel last option reachable 200% ${mode.name} ${width.toInt()}dp', (tester) async {
          _screen(tester, Size(width, 640));
          final chapters = List.generate(40, (index) => Chapter(
            cid: index + 1, page: index + 1,
            part: '可读的长章节标题 ${index + 1}', duration: 180));
          final longBook = Book(bvid: 'BV_TASK5_LONG', aid: 2,
            title: 'Task 5 多章节布局', pic: '', chapters: chapters);
          final player = _Player()..activeBook = longBook;
          await tester.pumpWidget(_host(const PlayerPage(), player, mode: mode, scale: 2));
          await tester.pumpAndSettle();
          final trigger = find.widgetWithIcon(ActionChip,
            panel == 'speed' ? Icons.speed_rounded : Icons.format_list_bulleted);
          await tester.ensureVisible(trigger);
          await tester.tap(trigger);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final last = find.text(panel == 'speed' ? '3.0x' : '40 · 可读的长章节标题 40');
          await tester.scrollUntilVisible(last, 180,
            scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
          await tester.pumpAndSettle();
          expect(last.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('focused custom timer label has readable rendered contrast in ${mode.name}', (tester) async {
      final player = _Player()..activeBook = _book;
      await tester.pumpWidget(_host(const SleepTimerPage(), player, mode: mode));
      await tester.pumpAndSettle();
      await _customDialog(tester);
      final label = find.text('分钟数');
      expect(label, findsOneWidget);
      final field = tester.widget<InputDecorator>(find.descendant(
        of: find.byType(TextField), matching: find.byType(InputDecorator)));
      expect(field.isFocused, isTrue);
      final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
        of: label, matching: find.byType(RichText)));
      final style = paragraph.text.style!;
      final foreground = style.foreground?.color ?? style.color;
      expect(foreground, isNotNull);
      Color? surface;
      tester.element(label).visitAncestorElements((element) {
        final widget = element.widget;
        if (widget is Material && widget.color != null) {
          surface = widget.color;
          return false;
        }
        return true;
      });
      expect(surface, isNotNull, reason: 'Read the painted dialog material, not a palette constant.');
      final defaults = Theme.of(tester.element(label)).inputDecorationTheme;
      final decoration = field.decoration.applyDefaults(defaults);
      final fill = decoration.filled == true
          ? Color.alphaBlend(decoration.fillColor ?? Colors.transparent, surface!)
          : surface!;
      // An outline's floating label straddles surface and field fill. Both
      // backgrounds must remain readable after inherited/focused style resolves.
      for (final background in [surface!, fill]) {
        final ink = Color.alphaBlend(foreground!, background);
        final a = ink.computeLuminance();
        final b = background.computeLuminance();
        final ratio = ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Actual focused label ink must contrast against its painted background.');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
