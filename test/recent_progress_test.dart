import 'package:abts/core/storage/shelf_store.dart';
import 'package:abts/models/book.dart';
import 'package:abts/models/content_mode.dart';
import 'package:abts/player/playback_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book resource(String bvid, ContentMode mode) =>
    Book(bvid: bvid, aid: 0, title: bvid, pic: '', contentMode: mode);

Future<void> savePosition(Book book) => ShelfStore.instance.updateProgress(
  book.bvid,
  book: book,
  cid: 10,
  chapterIndex: 2,
  positionMs: 47000,
  chapterDurationMs: 180000,
  totalChapters: 5,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ShelfStore.instance.load();
  });

  test(
    'uncollected concert persists resume position without becoming a favorite',
    () async {
      final shelf = ShelfStore.instance;
      await savePosition(resource('concert', ContentMode.concert));
      expect(shelf.isOnShelf('concert'), isFalse);
      expect(shelf.books, isEmpty);
      await shelf.load();
      final progress = shelf.progressByBvid('concert')!;
      expect(progress.book.contentMode, ContentMode.concert);
      expect(progress.positionMs, 47000);
      expect(
        PlaybackPreferences.selectionStart(
          progress.book.contentMode,
          index: progress.lastChapterIndex,
          positionMs: progress.positionMs,
        ),
        (index: 2, positionMs: 47000),
      );
    },
  );

  test(
    'collecting preserves progress and removal clears it as before',
    () async {
      final shelf = ShelfStore.instance;
      final book = resource('music', ContentMode.music);
      await savePosition(book);
      await shelf.add(book);
      expect(shelf.byBvid('music')!.positionMs, 47000);
      expect(shelf.recentBooks, hasLength(1));
      await shelf.remove('music');
      expect(shelf.isOnShelf('music'), isFalse);
      expect(shelf.progressByBvid('music'), isNull);
      expect(shelf.recentBooks, isEmpty);
      await shelf.load();
      expect(shelf.progressByBvid('music'), isNull);
    },
  );

  test(
    'loading a store with no recent data clears previous in-memory history',
    () async {
      await savePosition(resource('old', ContentMode.concert));
      SharedPreferences.setMockInitialValues({});
      await ShelfStore.instance.load();
      expect(ShelfStore.instance.recentBooks, isEmpty);
      expect(ShelfStore.instance.progressByBvid('old'), isNull);
    },
  );

  test(
    'uncollected recent history keeps only the latest 100 resources',
    () async {
      for (var i = 0; i < 101; i++) {
        await savePosition(resource('concert-$i', ContentMode.concert));
      }
      final shelf = ShelfStore.instance;
      expect(shelf.recentBooks, hasLength(100));
      expect(shelf.progressByBvid('concert-0'), isNull);
      expect(shelf.progressByBvid('concert-100'), isNotNull);
    },
  );

  test(
    'a later concert part at its start remains a resumable history item',
    () async {
      final shelf = ShelfStore.instance;
      final book = resource('concert-part', ContentMode.concert);
      await shelf.updateProgress(
        book.bvid,
        book: book,
        cid: 20,
        chapterIndex: 2,
        positionMs: 0,
        chapterDurationMs: 180000,
      );
      expect(shelf.progressByBvid(book.bvid)!.hasProgress, isTrue);
    },
  );

  test(
    'first collection uses the selected mode while migrating recent progress',
    () async {
      final shelf = ShelfStore.instance;
      await savePosition(resource('same-bv', ContentMode.music));
      await shelf.add(resource('same-bv', ContentMode.concert));
      final collected = shelf.byBvid('same-bv')!;
      expect(collected.book.contentMode, ContentMode.concert);
      expect(collected.positionMs, 47000);
      expect(collected.lastChapterIndex, 2);
      await shelf.load();
      expect(shelf.byBvid('same-bv')!.book.contentMode, ContentMode.concert);
      expect(shelf.byBvid('same-bv')!.positionMs, 47000);
    },
  );
}
