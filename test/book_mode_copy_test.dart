import 'package:blisten/models/book.dart';
import 'package:blisten/models/chapter.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('changing mode preserves playback metadata and chapter order', () {
    final source = Book(
      bvid: 'BV1xx411c7mD',
      aid: 1,
      title: '全场',
      pic: 'cover',
      author: '上传者',
      mid: 42,
      authorFace: 'face',
      desc: '简介',
      duration: 7200,
      pages: 2,
      upName: '上传者',
      pubdate: 123,
      play: 20,
      like: 2,
      coin: 3,
      favorite: 4,
      chapters: [
        Chapter(cid: 11, page: 1, part: '上半场', duration: 3600),
        Chapter(cid: 12, page: 2, part: '下半场', duration: 3600),
      ],
    );
    final concert = source.withContentMode(ContentMode.concert);
    expect(concert.contentMode, ContentMode.concert);
    expect(source.contentMode, ContentMode.audiobook);
    expect(concert.bvid, 'BV1xx411c7mD');
    expect(concert.chapters!.map((c) => c.cid), [11, 12]);
    expect(concert.authorFace, 'face');
    expect(concert.upName, '上传者');
    expect(
      [concert.play, concert.like, concert.coin, concert.favorite],
      [20, 2, 3, 4],
    );
    expect(concert.duration, 7200);
  });
}
