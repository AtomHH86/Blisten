import 'package:blisten/models/book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old saved books remain audiobooks after a save/load round trip', () {
    final book = Book.fromJson({
      'bvid': 'BV1xx411c7mD',
      'aid': 1,
      'title': '旧书籍',
      'pic': '',
      'duration': 3600,
    });
    expect(book.toJson()['contentMode'], 'audiobook');
    expect(book.duration, 3600);
  });

  for (final mode in ['music', 'concert']) {
    test('$mode survives saving the existing Book model', () {
      final original = {
        'bvid': 'BV1xx411c7mD',
        'aid': 1,
        'title': '现场',
        'pic': '',
        'contentMode': mode,
      };
      final saved = Book.fromJson(original).toJson();
      expect(saved['contentMode'], mode);
      expect(Book.fromJson(saved).toJson()['contentMode'], mode);
    });
  }

  test('unrecognized saved mode falls back to audiobook', () {
    final book = Book.fromJson({
      'bvid': 'BV1xx411c7mD',
      'title': '旧书籍',
      'contentMode': 'unknown',
    });
    expect(book.toJson()['contentMode'], 'audiobook');
  });
}
