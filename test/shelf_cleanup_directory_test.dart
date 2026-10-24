import 'dart:convert';

import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/chapter.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book _book({List<Chapter>? chapters}) => Book(
  bvid: 'directory-bv', aid: 1, title: '目录测试', pic: '', pages: 3,
  contentMode: ContentMode.concert, chapters: chapters,
);

final _chapters = [
  Chapter(cid: 101, page: 1, part: '第一段', duration: 90),
  Chapter(cid: 102, page: 2, part: '第二段', duration: 90),
  Chapter(cid: 103, page: 3, part: '第三段', duration: 90),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final shelf = ShelfStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await shelf.load();
  });

  test('removing a favorite preserves its recent CID and offset after reload', () async {
    final book = _book();
    await shelf.add(book);
    await shelf.updateProgress(book.bvid, book: book, cid: 103,
        chapterIndex: 2, positionMs: 12000, chapterDurationMs: 90000,
        totalChapters: 3);
    await shelf.markChapterDone(book.bvid, 101);
    await shelf.remove(book.bvid);
    await shelf.load();
    expect(shelf.isOnShelf(book.bvid), isFalse);
    final progress = shelf.progressByBvid(book.bvid);
    expect(progress, isNotNull);
    expect(progress!.lastCid, 103);
    expect(progress.positionMs, 12000);
    expect(progress.doneCids, [101]);
    // Removing it again must not be a hidden "clear recent" action.
    await shelf.remove(book.bvid);
    expect(shelf.progressByBvid(book.bvid)!.positionMs, 12000);
  });

  test('removed favorite intent survives progress saves and reload until manual add', () async {
    final book = _book();
    await shelf.add(book);
    await shelf.updateProgress(book.bvid, book: book, cid: 103,
        chapterIndex: 2, positionMs: 10000, chapterDurationMs: 90000);
    await shelf.remove(book.bvid);
    await shelf.updateProgress(book.bvid, book: book, cid: 103,
        chapterIndex: 2, positionMs: 12000, chapterDurationMs: 90000);
    await shelf.load();
    expect(shelf.progressByBvid(book.bvid)!.toJson()['autoAddSuppressed'], isTrue);
    expect(shelf.isOnShelf(book.bvid), isFalse);
    await shelf.add(book);
    await shelf.load();
    expect(shelf.byBvid(book.bvid)!.toJson()['autoAddSuppressed'], isFalse);
    expect(shelf.byBvid(book.bvid)!.positionMs, 12000);
    final legacy = ShelfBook.fromJson({'book': book.toJson()});
    expect(legacy.toJson()['autoAddSuppressed'], isFalse);
  });

  test('a persisted directory retains chapter identity and metadata', () {
    final restored = Book.fromJson(jsonDecode(jsonEncode(_book(chapters: _chapters).toJson())));
    expect(restored.chapters?.map((c) => c.cid), [101, 102, 103]);
    expect(restored.chapters?.last.part, '第三段');
    expect(restored.chapters?.last.duration, 90);
  });

  test('partial directory remains explicitly partial after JSON roundtrip', () {
    final stored = ShelfBook.fromJson({
      'book': {
        ..._book().toJson(),
        'chapters': [{'cid': 103, 'page': 3, 'part': '第三段', 'duration': 90}],
      },
      'chaptersComplete': false,
      'lastCid': 103,
      'positionMs': 12000,
    });
    final restored = ShelfBook.fromJson(jsonDecode(jsonEncode(stored.toJson())));
    expect(restored.toJson()['chaptersComplete'], isFalse);
    expect(restored.book.chapters?.single.cid, 103);
  });

  test('saving a fetched directory refreshes an already collected search result', () async {
    final book = _book();
    await shelf.add(book);
    await shelf.updateProgress(book.bvid, book: _book(chapters: _chapters),
        cid: 103, chapterIndex: 2, positionMs: 12000,
        chapterDurationMs: 90000, totalChapters: 3);
    await shelf.load();
    expect(shelf.byBvid(book.bvid)!.book.chapters?.map((c) => c.cid), [101, 102, 103]);
    expect(shelf.byBvid(book.bvid)!.book.contentMode, ContentMode.concert);
  });

  test('an offline subset never replaces a known complete directory', () async {
    final book = _book(chapters: _chapters);
    await shelf.add(book);
    await shelf.updateProgress(book.bvid, book: _book(), cid: 103,
        chapterIndex: 0, positionMs: 12000, chapterDurationMs: 90000,
        chapters: [_chapters.last], chaptersComplete: false);
    await shelf.load();
    final saved = shelf.byBvid(book.bvid)!;
    expect(saved.book.chapters!.map((c) => c.cid), [101, 102, 103]);
    expect(saved.chaptersComplete, isTrue);
    expect(saved.lastCid, 103);
  });

  test('clearing a favorite resets listening data while preserving its identity and directory', () async {
    final book = _book(chapters: _chapters);
    await shelf.add(book);
    await shelf.updateProgress(book.bvid, cid: 103, chapterIndex: 2,
        positionMs: 12000, chapterDurationMs: 90000);
    await shelf.markChapterDone(book.bvid, 101);
    await shelf.clearListeningRecord(book.bvid);
    await shelf.load();
    final saved = shelf.byBvid(book.bvid)!;
    expect(saved.lastCid, 0);
    expect(saved.lastChapterIndex, 0);
    expect(saved.positionMs, 0);
    expect(saved.chapterDurationMs, 0);
    expect(saved.doneCids, isEmpty);
    expect(saved.chapterProgress, isEmpty);
    expect(saved.hasProgress, isFalse);
    expect(saved.book.chapters!.map((c) => c.cid), [101, 102, 103]);
  });

  test('clearing a recent-only record deletes it without changing another favorite', () async {
    final book = _book();
    await shelf.updateProgress(book.bvid, book: book, cid: 103, chapterIndex: 2,
        positionMs: 12000, chapterDurationMs: 90000);
    await shelf.add(Book(bvid: 'other', aid: 2, title: '其他收藏', pic: ''));
    await shelf.clearListeningRecord(book.bvid);
    await shelf.load();
    expect(shelf.progressByBvid(book.bvid), isNull);
    expect(shelf.isOnShelf('other'), isTrue);
  });
}
