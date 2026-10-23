import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/bookshelf_page.dart';
import 'package:blisten/pages/splash_screen.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/widgets/book_cards.dart';
import 'package:blisten/widgets/resource_import_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IdlePlayer extends ChangeNotifier implements BookPlayer {
  @override
  Book? get book => null;
  @override
  bool get isPlaying => false;
  @override
  bool get loaded => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget child, {double scale = 1, bool dark = false}) {
  AppTheme.mode = dark ? ThemeMode.dark : ThemeMode.light;
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: ShelfStore.instance),
      ChangeNotifierProvider<BookPlayer>(create: (_) => _IdlePlayer()),
    ],
    child: MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: child,
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'abts_shelf': '[]'});
    await ShelfStore.instance.load();
  });
  tearDown(() => AppTheme.mode = ThemeMode.dark);

  testWidgets('brand and empty-state content are horizontally centered', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(const SplashScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getCenter(find.byType(Image)).dx, closeTo(180, 0.1));
    expect(tester.getCenter(find.text('B听')).dx, closeTo(180, 0.1));
    await tester.pumpWidget(_host(const BookshelfPage()));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('收藏还是空的')).dx, closeTo(180, 0.1));
    expect(
      tester
          .getCenter(
            find.byWidgetPredicate((widget) => widget is OutlinedButton),
          )
          .dx,
      closeTo(180, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty collection opens link import and cancel preserves empty shelf',
    (tester) async {
      await tester.pumpWidget(_host(const BookshelfPage()));
      await tester.pumpAndSettle();
      final import = find.text('粘贴链接 / BV号');
      expect(import, findsOneWidget);
      await tester.tap(import);
      await tester.pumpAndSettle();
      expect(find.byType(ResourceImportDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'BV1xx411c7mD');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceImportDialog), findsNothing);
      expect(ShelfStore.instance.books, isEmpty);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'empty collection remains operable at 320dp 200% ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _host(const BookshelfPage(), scale: 2, dark: dark),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final import = find.text('粘贴链接 / BV号');
        await tester.ensureVisible(import);
        await tester.pumpAndSettle();
        expect(import.hitTestable(), findsOneWidget);
        await tester.tap(import);
        await tester.pumpAndSettle();
        expect(find.byType(ResourceImportDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'resource metadata wraps without hiding its tap action at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = false;
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: BookListTile(
              book: Book(
                bvid: 'BV1xx411c7mD',
                aid: 1,
                title: '这是一场有很长标题的音乐节现场完整录音',
                pic: '',
                contentMode: ContentMode.concert,
              ),
              subtitle: '第 123 段 · 很长的分段描述与演出信息',
              trailing: '99.9万播放',
              onTap: () => opened = true,
            ),
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('这是一场有很长标题的音乐节现场完整录音'));
      expect(opened, isTrue);
    },
  );
}
