import 'dart:convert';

import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/book.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'explicit import may update the saved mode without clearing progress',
    () async {
      SharedPreferences.setMockInitialValues({
        'abts_shelf': jsonEncode([
          {
            'book': {'bvid': 'BV1yy411c7mD', 'title': '旧听书条目'},
            'positionMs': 12000,
            'lastCid': 20,
          },
        ]),
      });
      final shelf = ShelfStore.instance;
      await shelf.load();
      await shelf.add(
        Book.fromJson({
          'bvid': 'BV1yy411c7mD',
          'title': '歌曲',
          'contentMode': 'music',
        }),
        updateContentMode: true,
      );
      final stored = shelf.byBvid('BV1yy411c7mD')!;
      expect(stored.book.toJson()['contentMode'], 'music');
      expect(stored.positionMs, 12000);
    },
  );
}
