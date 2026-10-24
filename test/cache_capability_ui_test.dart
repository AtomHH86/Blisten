import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/chapter.dart';
import 'package:blisten/pages/book_detail_page.dart';
import 'package:blisten/pages/cache_page.dart';
import 'package:blisten/pages/cache_sheet.dart';
import 'package:blisten/player/book_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UnsupportedCache extends ChangeNotifier implements CacheStore {
  @override
  bool get supported => false;
  @override
  String get unsupportedReason => '网页版暂不支持离线音频缓存';
  @override
  List<CacheEntry> get entries => [];
  @override
  List<CacheTask> get tasks => [];
  @override
  List<CacheFailure> get failures => [];
  @override
  int get pendingCount => 0;
  @override
  bool isCached(String bvid, int cid) => false;
  @override
  CacheTask? taskOf(String bvid, int cid) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IdlePlayer extends ChangeNotifier implements BookPlayer {
  int resolveCalls = 0;
  @override
  Book? get book => null;
  @override
  bool get loaded => false;
  @override
  Future<String?> resolveUrlFor(String bvid, int cid) async {
    resolveCalls++;
    return null;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'unsupported cache explains capability in 320dp 200% ${dark ? 'dark' : 'light'}',
      (tester) async {
        final cache = _UnsupportedCache();
        addTearDown(cache.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider<CacheStore>.value(
            value: cache,
            child: MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: const Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 320,
                      height: 341,
                      child: CachePage(embedded: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final explanation = find.text('网页版暂不支持离线音频缓存');
        expect(explanation, findsOneWidget);
        await tester.ensureVisible(explanation);
        expect(explanation.hitTestable(), findsOneWidget);
        expect(find.textContaining('在作品详情页点下载图标'), findsNothing);
        expect(find.text('清空'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('unsupported cache sheet shows reason without opening download selection',
      (tester) async {
    final cache = _UnsupportedCache();
    addTearDown(cache.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<CacheStore>.value(
      value: cache,
      child: MaterialApp(
        home: Scaffold(body: Builder(builder: (context) => TextButton(
          onPressed: () => CacheSheet.show(context),
          child: const Text('打开缓存'),
        ))),
      ),
    ));
    await tester.tap(find.text('打开缓存'));
    await tester.pumpAndSettle();
    expect(find.text('网页版暂不支持离线音频缓存'), findsOneWidget);
    expect(find.byType(CacheSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported single chapter cache does not resolve an audio URL',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ShelfStore.instance.load();
    final cache = _UnsupportedCache();
    final player = _IdlePlayer();
    addTearDown(() {
      cache.dispose();
      player.dispose();
    });
    final book = Book(bvid: 'BVunsupported', aid: 1, title: '缓存能力测试', pic: '',
        pages: 1, chapters: [Chapter(cid: 101, page: 1, part: '第一章', duration: 90)]);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ShelfStore.instance),
        ChangeNotifierProvider<CacheStore>.value(value: cache),
        ChangeNotifierProvider<BookPlayer>.value(value: player),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: BookDetailPage(
        bvid: book.bvid, initialBook: book,
      )),
    ));
    await tester.pumpAndSettle();
    final download = find.byIcon(Icons.download_rounded);
    await tester.ensureVisible(download);
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(player.resolveCalls, 0);
    expect(find.text('网页版暂不支持离线音频缓存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
