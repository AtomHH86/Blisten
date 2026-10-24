import 'dart:convert';

import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/models/chapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recent_progress_test.dart' show resource, savePosition;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final shelf = ShelfStore.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await shelf.load();
  });
  test('unplayed favorites do not create listening history', () async {
    await shelf.add(resource('unplayed', ContentMode.audiobook));
    expect(shelf.recentBooks, isEmpty);
    expect(shelf.progressByBvid('unplayed'), isNotNull);
  });
  test('zero rewind retains heard history after restart', () async {
    await savePosition(resource('heard', ContentMode.music));
    await shelf.updateProgress('heard', cid: 10, chapterIndex: 0,
        positionMs: 0, chapterDurationMs: 180000);
    await shelf.load();
    expect(shelf.recentBooks.single.book.bvid, 'heard');
  });
  test('nonfavorite completion persists', () async {
    await savePosition(resource('heard', ContentMode.music));
    await shelf.markChapterDone('heard', 10);
    await shelf.load();
    expect(shelf.isChapterDone('heard', 10), isTrue);
    expect(shelf.doneCount('heard'), 1);
  });
  test('clear preserves favorite but removes history', () async {
    final book = resource('heard', ContentMode.music);
    await savePosition(book);
    await shelf.add(book);
    await shelf.clearListeningRecord('heard');
    await shelf.load();
    expect(shelf.isOnShelf('heard'), isTrue);
    expect(shelf.recentBooks, isEmpty);
    expect(shelf.progressByBvid('heard')!.positionMs, 0);
  });
  test('mode moves retain progress and resist old session metadata', () async {
    await savePosition(resource('heard', ContentMode.music));
    await shelf.markChapterDone('heard', 10);
    await shelf.moveToMode('heard', ContentMode.concert);
    await shelf.updateProgress('heard', book: resource('heard', ContentMode.music),
        cid: 10, chapterIndex: 2, positionMs: 47000,
        chapterDurationMs: 180000, listened: false);
    await shelf.load();
    expect(shelf.progressByBvid('heard')!.book.contentMode, ContentMode.concert);
    expect(shelf.progressByBvid('heard')!.positionMs, 47000);
    expect(shelf.isChapterDone('heard', 10), isTrue);
  });
  test('metadata changes do not reorder listening history', () async {
    final older = resource('older', ContentMode.music);
    await savePosition(older);
    shelf.progressByBvid('older')!.lastListenedAt = 100;
    await savePosition(resource('newer', ContentMode.concert));
    shelf.progressByBvid('newer')!.lastListenedAt = 200;
    await shelf.add(older);
    await shelf.moveToMode('older', ContentMode.children);
    expect(shelf.recentBooks.map((b) => b.book.bvid), ['newer', 'older']);
  });
  test('selection and restoration without playback do not create history', () async {
    await shelf.updateProgress('unplayed', book: resource('unplayed', ContentMode.music),
        cid: 10, chapterIndex: 2, positionMs: 47000,
        chapterDurationMs: 180000, listened: false);
    expect(shelf.recentBooks, isEmpty);
    expect(shelf.progressByBvid('unplayed'), isNull);
  });

  test('legacy progress without timestamp still establishes heard evidence', () {
    final saved = ShelfBook.fromJson({
      'book': resource('legacy', ContentMode.audiobook).toJson(),
      'positionMs': 12000,
    });
    expect(saved.hasListened, isTrue);
    final unplayed = ShelfBook.fromJson({
      'book': resource('unplayed', ContentMode.audiobook).toJson(),
      'updatedAt': 1234,
    });
    expect(unplayed.hasListened, isFalse);
  });
  test('moving preserves full directory and chapter completion', () async {
    final book = resource('directory', ContentMode.music).withChapters([
      Chapter(cid: 10, page: 1, part: 'one', duration: 180),
      Chapter(cid: 20, page: 2, part: 'two', duration: 180),
    ]);
    await savePosition(book);
    await shelf.markChapterDone('directory', 10);
    await shelf.add(book);
    await shelf.moveToMode('directory', ContentMode.concert);
    await shelf.load();
    final saved = shelf.progressByBvid('directory')!;
    expect(saved.book.bvid, 'directory');
    expect(saved.book.chapters!.map((c) => c.cid), [10, 20]);
    expect(saved.chaptersComplete, isTrue);
    expect(saved.doneCids, [10]);
    expect(saved.positionMs, 47000);
  });
  test('removing unplayed favorites cannot evict heard history', () async {
    for (var i = 0; i < 100; i++) {
      await savePosition(resource('heard-$i', ContentMode.music));
    }
    await shelf.add(resource('unplayed', ContentMode.audiobook));
    await shelf.remove('unplayed');
    expect(shelf.recentBooks, hasLength(100));
    expect(shelf.progressByBvid('heard-0'), isNotNull);
  });

  Future<void> fillRecent({bool oldFavorite = false}) async {
    SharedPreferences.setMockInitialValues({
      'abts_shelf': jsonEncode([
        if (oldFavorite)
          ShelfBook(book: resource('old-favorite', ContentMode.music),
              lastListenedAt: 1).toJson(),
      ]),
      'abts_recent_progress': jsonEncode([
        for (var i = 0; i < 100; i++)
          ShelfBook(book: resource('heard-$i', ContentMode.music),
              lastListenedAt: 1000 + i).toJson(),
      ]),
    });
    await shelf.load();
  }

  test('removing an old heard favorite preserves the latest 100 uncollected listens', () async {
    await fillRecent(oldFavorite: true);
    await shelf.remove('old-favorite');
    await shelf.load();
    expect(shelf.recentBooks, hasLength(100));
    expect(shelf.progressByBvid('old-favorite'), isNull);
    expect(shelf.progressByBvid('heard-99'), isNotNull);
    expect(shelf.progressByBvid('heard-0'), isNotNull);
  });

  test('nonlistening progress updates do not protect old records from eviction', () async {
    await fillRecent();
    await shelf.updateProgress('heard-0', cid: 10, chapterIndex: 0,
        positionMs: 0, chapterDurationMs: 180000, listened: false);
    await savePosition(resource('latest', ContentMode.music));
    await shelf.load();
    expect(shelf.recentBooks, hasLength(100));
    expect(shelf.progressByBvid('heard-0'), isNull);
    expect(shelf.progressByBvid('heard-99'), isNotNull);
    expect(shelf.progressByBvid('latest'), isNotNull);
  });

  test('a new listen receives its timestamp before the retention limit is applied', () async {
    await fillRecent();
    await savePosition(resource('latest', ContentMode.music));
    await shelf.load();
    expect(shelf.progressByBvid('latest'), isNotNull);
    expect(shelf.progressByBvid('heard-0'), isNull);
    expect(shelf.progressByBvid('heard-99'), isNotNull);
  });

}
