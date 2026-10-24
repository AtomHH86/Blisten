import 'dart:convert';

import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/follow_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/core/theme/theme_controller.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/chapter.dart';
import 'package:blisten/pages/about_page.dart';
import 'package:blisten/pages/cache_page.dart';
import 'package:blisten/pages/cache_sheet.dart';
import 'package:blisten/pages/my_page.dart';
import 'package:blisten/pages/settings_page.dart';
import 'package:blisten/pages/sleep_timer_page.dart';
import 'package:blisten/pages/theme_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/auth_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _book = Book(
  bvid: 'BV1xx411c7mD',
  aid: 1,
  title: '长标题收听资源：从第一章开始的一段完整中文故事',
  pic: '',
  chapters: [
    Chapter(cid: 11, page: 1, part: '这是一段较长的章节名称用于检查换行', duration: 180),
    Chapter(cid: 12, page: 2, part: '第二章', duration: 180),
  ],
);

// Layout fixture represents an already server-verified account. Persisted
// profile data is intentionally insufficient to establish authentication.
class _VerifiedLogin extends ChangeNotifier implements LoginStore {
  @override
  bool get isLogin => status == LoginStatus.verified;
  @override
  LoginStatus status = LoginStatus.verified;
  @override
  String get userName => '这是一个较长的中文用户昵称';
  @override
  String get userFace => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
final _verifiedLogin = _VerifiedLogin();

class _Player extends ChangeNotifier implements BookPlayer {
  Duration timer = Duration.zero;
  bool stopAtEnd = false;

  @override
  Book? get book => _book;
  @override
  List<Chapter> get chapters => _book.chapters!;
  @override
  bool get loaded => true;
  @override
  bool get isPlaying => false;
  @override
  Duration get sleepRemaining => timer;
  @override
  bool get stopAtChapterEnd => stopAtEnd;
  @override
  void setSleepTimer(Duration duration) {
    timer = duration;
    notifyListeners();
  }

  @override
  void cancelSleepTimer() {
    timer = Duration.zero;
    notifyListeners();
  }

  @override
  void setStopAtChapterEnd(bool value) {
    stopAtEnd = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget page, _Player player, ThemeMode mode, {double scale = 1}) {
  AppTheme.mode = mode;
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: ShelfStore.instance),
      ChangeNotifierProvider.value(value: CacheStore.instance),
      ChangeNotifierProvider.value(value: FollowStore.instance),
      ChangeNotifierProvider<LoginStore>.value(value: _verifiedLogin),
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
      home: page,
    ),
  );
}

void _narrowScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _reachable(WidgetTester tester, Finder finder) async {
  // Lazy lists have no element for offscreen items until they are scrolled in.
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

// Read colors after Material state resolution and text style inheritance. This
// catches, for example, a page overriding a themed button with white text.
void _expectRenderedContrast(
  WidgetTester tester,
  Finder control, {
  double minimum = 4.5,
}) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: control, matching: find.byType(RichText)).first,
  );
  final foreground = paragraph.text.style!.color!;
  final material = tester.widget<Material>(
    find.descendant(of: control, matching: find.byType(Material)).first,
  );
  final canvas = Theme.of(tester.element(control)).scaffoldBackgroundColor;
  final background = Color.alphaBlend(
    material.color ?? Colors.transparent,
    canvas,
  );
  final paintedText = Color.alphaBlend(foreground, background);
  final a = paintedText.computeLuminance();
  final b = background.computeLuminance();
  final ratio = ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
  expect(
    ratio,
    greaterThanOrEqualTo(minimum),
    reason: 'Rendered control text contrast',
  );
}

void main() {
  setUp(() async {
    _verifiedLogin.status = LoginStatus.verified;
    const entry = CacheEntry(
      bvid: 'BV1xx411c7mD',
      cid: 11,
      bookTitle: '长标题收听资源：从第一章开始的一段完整中文故事',
      chapterTitle: '第一章 · 较长的中文章节名称与收听进度',
      durationSec: 180,
      sizeBytes: 12 * 1024 * 1024,
    );
    SharedPreferences.setMockInitialValues({
      'abts_shelf': '[]',
      'abts_recent_progress': '[]',
      'abts_follows': '[]',
      'abts_cache_index': jsonEncode([entry.toJson()]),
      'abts_cache_pending': '[]',
      'abts_cache_events': '[]',
      'bili_login_user': jsonEncode({
        'login': true,
        'name': '这是一个较长的中文用户昵称',
        'face': '',
      }),
    });
    await ShelfStore.instance.load();
    await ShelfStore.instance.add(
      _book,
      withProgress: ShelfBook(
        book: _book,
        lastCid: 11,
        positionMs: 42000,
        chapterDurationMs: 180000,
      ),
    );
    await FollowStore.instance.load();
    await LoginStore.instance.load();
    await CacheStore.instance.load();
    await ThemeController.instance.load();
  });
  tearDown(() => AppTheme.mode = ThemeMode.system);

  testWidgets('unverified credential keeps logout reachable and shows verification state', (tester) async {
    _verifiedLogin.status = LoginStatus.unverified;
    await tester.pumpWidget(_host(const SettingsPage(), _Player(), ThemeMode.light));
    await tester.pumpAndSettle();
    expect(find.text('登录待验证'), findsOneWidget);
    expect(find.text('暂时无法验证，请检查网络'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'enabled and selected controls have readable text and 48dp targets in ${mode.name}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          var selected = false;
          await tester.pumpWidget(
            _host(
              Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(onPressed: () {}, child: const Text('开始收听')),
                      TextButton(onPressed: () {}, child: const Text('重试')),
                      OutlinedButton(onPressed: () {}, child: const Text('返回')),
                      IconButton(
                        tooltip: '播放',
                        onPressed: () {},
                        icon: const Icon(Icons.play_arrow),
                      ),
                      CheckboxListTile(
                        title: const Text('缓存此章'),
                        value: selected,
                        onChanged: (value) => setState(() => selected = value!),
                      ),
                      RadioGroup<int>(
                        groupValue: 1,
                        onChanged: (_) {},
                        child: const RadioListTile<int>(
                          value: 1,
                          title: Text('已选外观'),
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('播完当前章暂停'),
                        value: true,
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
              _Player(),
              mode,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('缓存此章'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                .value,
            isTrue,
          );
          for (final type in [FilledButton, TextButton, OutlinedButton]) {
            final finder = find.byType(type);
            _expectRenderedContrast(tester, finder);
            expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
          }
          expect(
            tester.getSize(find.byType(IconButton)).shortestSide,
            greaterThanOrEqualTo(48),
          );
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'Settings account action stays reachable at 320dp 200% in ${mode.name}',
      (tester) async {
        _narrowScreen(tester);
        await tester.pumpWidget(
          _host(const SettingsPage(), _Player(), mode, scale: 2),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _reachable(tester, find.widgetWithText(OutlinedButton, '退出登录'));
        await tester.tap(find.text('退出登录'));
        await tester.pumpAndSettle();
        expect(find.textContaining('收藏与收听进度仍保留'), findsOneWidget);
        await _reachable(tester, find.text('取消'));
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(_verifiedLogin.isLogin, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Theme options stay reachable and selectable at 320dp 200% in ${mode.name}',
      (tester) async {
        _narrowScreen(tester);
        await tester.pumpWidget(
          _host(const ThemePage(), _Player(), mode, scale: 2),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _reachable(tester, find.text('深色'));
        await tester.tap(find.text('深色'));
        await tester.pumpAndSettle();
        expect(ThemeController.instance.mode, ThemeMode.dark);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'My recent cards and final menu action fit 320dp 200% in ${mode.name}',
      (tester) async {
        _narrowScreen(tester);
        await tester.pumpWidget(
          _host(const MyPage(), _Player(), mode, scale: 2),
        );
        await tester.pumpAndSettle();
        expect(find.text(_book.cleanTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _reachable(tester, find.text('关于我们'));
        await tester.tap(find.text('关于我们'));
        await tester.pumpAndSettle();
        expect(find.byType(AboutPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Sleep preset and custom action work at 320dp 200% in ${mode.name}',
      (tester) async {
        _narrowScreen(tester);
        final player = _Player();
        await tester.pumpWidget(
          _host(const SleepTimerPage(), player, mode, scale: 2),
        );
        await tester.pumpAndSettle();
        await _reachable(tester, find.text('10 分钟'));
        await tester.tap(find.text('10 分钟'));
        await tester.pumpAndSettle();
        expect(player.timer, const Duration(minutes: 10));
        await _reachable(tester, find.text('自定义时长'));
        await tester.tap(find.text('自定义时长'));
        await tester.pumpAndSettle();
        await _reachable(tester, find.text('设置定时'));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Cache management keeps chapter and delete action reachable at 320dp 200% in ${mode.name}',
      (tester) async {
        _narrowScreen(tester);
        await tester.pumpWidget(
          _host(const CachePage(), _Player(), mode, scale: 2),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _reachable(tester, find.text(_book.cleanTitle));
        await tester.tap(find.text(_book.cleanTitle));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _reachable(tester, find.byTooltip('删除'));
        await tester.tap(find.byTooltip('删除'));
        await tester.pumpAndSettle();
        await _reachable(tester, find.widgetWithText(TextButton, '删除'));
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(CacheStore.instance.entries, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Cache selection and enabled submit fit 320dp 200% in ${mode.name}',
      (tester) async {
        _narrowScreen(tester);
        await tester.pumpWidget(
          _host(
            Scaffold(body: CacheSheet(book: _book)),
            _Player(),
            mode,
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final chapter = find.widgetWithText(CheckboxListTile, '2 · 第二章');
        await _reachable(tester, chapter);
        await tester.tap(chapter);
        await tester.pumpAndSettle();
        final submit = find.ancestor(
          of: find.text('缓存选中的 1 章'),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        );
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        expect(submit.hitTestable(), findsOneWidget);
        expect(tester.getSize(submit).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
