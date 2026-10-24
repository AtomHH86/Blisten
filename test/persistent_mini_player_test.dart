import 'dart:convert';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/chapter.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreviewPlayer extends ChangeNotifier implements BookPlayer {
  Book? active;
  ShelfBook? selected;
  int toggles = 0;
  bool playing = false;
  bool waiting = false;
  bool failed = false;
  @override
  Book? get book => active;
  @override
  bool get loaded => active != null;
  @override
  bool get loading => false;
  @override
  bool get buffering => waiting;
  @override
  bool get isPlaying => playing;
  @override
  String? get error => failed ? 'failure' : null;
  @override
  Chapter? get currentChapter => null;
  @override
  void flushProgress() {}
  @override
  Future<bool> resumeShelf(ShelfBook row) async {
    selected = row;
    return true;
  }

  @override
  Future<void> togglePlay() async {
    toggles++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final book = Book(bvid: 'BVpreview', aid: 1, title: '真实上次内容', pic: '');
  Future<void> mount(
    WidgetTester tester,
    PreviewPlayer player, {
    bool history = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'abts_shelf': '[]',
      'abts_recent_progress': jsonEncode(
        history
            ? [
                ShelfBook(
                  book: book,
                  lastListenedAt: 10,
                  positionMs: 24000,
                ).toJson(),
              ]
            : [],
      ),
    });
    await ShelfStore.instance.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ShelfStore.instance),
          ChangeNotifierProvider<BookPlayer>.value(value: player),
        ],
        child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty mini row reserves space and offers discovery', (
    tester,
  ) async {
    await mount(tester, PreviewPlayer(), history: false);
    expect(find.text('还没有收听内容'), findsOneWidget);
    expect(find.text('去发现'), findsOneWidget);
    expect(find.byTooltip('播放'), findsNothing);
  });
  testWidgets('cold preview and opening cover are silent until explicit play', (
    tester,
  ) async {
    final player = PreviewPlayer();
    await mount(tester, player);
    expect(find.text(book.title), findsOneWidget);
    expect(player.selected, isNull);
    await tester.tap(find.text(book.title));
    await tester.pumpAndSettle();
    expect(find.text(book.title), findsOneWidget);
    expect(player.selected, isNull);
    await tester.tap(find.byTooltip('播放'));
    await tester.pump();
    expect(player.selected?.book.bvid, book.bvid);
    expect(player.toggles, 0);
  });
  testWidgets('current paused session wins over recent and toggles in place', (
    tester,
  ) async {
    final player = PreviewPlayer()
      ..active = Book(bvid: 'BVactive', aid: 2, title: '当前会话', pic: '');
    await mount(tester, player);
    expect(find.text('当前会话'), findsOneWidget);
    expect(find.text(book.title), findsNothing);
    await tester.tap(find.byTooltip('播放'));
    expect(player.toggles, 1);
    expect(player.selected, isNull);
  });
  testWidgets(
    'clearing matching preview reveals next history without selecting playback',
    (tester) async {
      final player = PreviewPlayer();
      await mount(tester, player);
      await ShelfStore.instance.clearListeningRecord(book.bvid);
      await tester.pumpAndSettle();
      expect(find.text('还没有收听内容'), findsOneWidget);
      expect(player.selected, isNull);
    },
  );
  testWidgets(
    'disc rotates only during confirmed playback and freezes for buffering errors reduced motion',
    (tester) async {
      final player = PreviewPlayer()..active = book;
      await mount(tester, player);
      final turns = tester
          .widget<RotationTransition>(
            find.byKey(const ValueKey('mini-player-disc')),
          )
          .turns;
      expect((turns as AnimationController).isAnimating, isFalse);
      player.playing = true;
      player.notifyListeners();
      await tester.pump();
      expect(turns.isAnimating, isTrue);
      await tester.pump(const Duration(seconds: 1));
      final angle = turns.value;
      player.waiting = true;
      player.notifyListeners();
      await tester.pump();
      expect(turns.isAnimating, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(turns.value, angle);
      player.waiting = false;
      player.failed = true;
      player.notifyListeners();
      await tester.pump();
      expect(turns.isAnimating, isFalse);
      player.failed = false;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: ShelfStore.instance),
            ChangeNotifierProvider<BookPlayer>.value(value: player),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(body: MiniPlayer()),
            ),
          ),
        ),
      );
      await tester.pump();
      final reducedTurns =
          tester
                  .widget<RotationTransition>(
                    find.byKey(const ValueKey('mini-player-disc')),
                  )
                  .turns
              as AnimationController;
      expect(reducedTurns.isAnimating, isFalse);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    },
  );
}
