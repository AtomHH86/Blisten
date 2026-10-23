import 'dart:async';

import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/player_page.dart';
import 'package:blisten/pages/recent_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book resource(ContentMode mode) =>
    Book(bvid: 'same-bv', aid: 1, title: '同一个视频', pic: '', contentMode: mode);

class _Player extends ChangeNotifier implements BookPlayer {
  final Book activeBook;
  bool ready = true;
  ShelfBook? resumed;
  _Player(this.activeBook);

  @override
  Book? get book => activeBook;
  @override
  bool get loaded => ready;
  @override
  bool get isPlaying => true;
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  void flushProgress() {}
  @override
  Future<bool> resumeShelf(ShelfBook sb) {
    resumed = sb;
    return Completer<bool>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(_Player player) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: ShelfStore.instance),
    ChangeNotifierProvider<BookPlayer>.value(value: player),
  ],
  child: MaterialApp(theme: AppTheme.dark(), home: const RecentPage()),
);

Future<void> prepareConcertFavorite() async {
  final shelf = ShelfStore.instance;
  await shelf.add(resource(ContentMode.music));
  await shelf.updateProgress(
    'same-bv',
    cid: 10,
    chapterIndex: 0,
    positionMs: 12000,
    chapterDurationMs: 180000,
  );
  // Explicit import reclassifies an existing favorite while music is playing.
  await shelf.add(resource(ContentMode.concert), updateContentMode: true);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ShelfStore.instance.load();
    await prepareConcertFavorite();
  });

  testWidgets('recent row does not mark an old mode as the active selection', (
    tester,
  ) async {
    final player = _Player(resource(ContentMode.music));
    await tester.pumpWidget(_host(player));
    expect(find.byTooltip('继续收听'), findsOneWidget);
    expect(find.byIcon(Icons.equalizer_rounded), findsNothing);
  });

  testWidgets('reclassified recent resource reloads through resumeShelf', (
    tester,
  ) async {
    final player = _Player(resource(ContentMode.music));
    await tester.pumpWidget(_host(player));
    await tester.tap(find.byType(IconButton).last);
    player.ready =
        false; // Any incorrectly pushed page can render without media.
    expect(player.resumed?.book.contentMode, ContentMode.concert);
    expect(player.resumed?.positionMs, 12000);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('same BV and mode keeps the current playback shortcut', (
    tester,
  ) async {
    final player = _Player(resource(ContentMode.concert));
    await tester.pumpWidget(_host(player));
    await tester.tap(find.byTooltip('打开播放页'));
    player.ready = false;
    await tester.pumpAndSettle();
    expect(player.resumed, isNull);
    expect(find.byType(PlayerPage), findsOneWidget);
  });
}
