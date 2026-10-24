import 'dart:convert';

import 'package:blisten/core/storage/follow_store.dart';
import 'package:blisten/models/up_user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'abts_follows': '[]'});
    await FollowStore.instance.load();
  });

  test('legacy followed UP defaults to audiobook context', () {
    final up = UpUser.fromJson({'mid': 42, 'name': 'Legacy UP'});
    expect(up.toJson()['contentMode'], 'audiobook');
  });

  for (final mode in ['music', 'concert']) {
    test('followed UP retains $mode after preferences reload', () async {
      final store = FollowStore.instance;
      await store.toggle(UpUser.fromJson({
        'mid': 42, 'name': 'Synthetic UP', 'contentMode': mode,
      }));
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('abts_follows')!) as List;
      expect((saved.single as Map)['contentMode'], mode);
      await store.load();
      expect(store.byMid(42)!.toJson()['contentMode'], mode);
      expect(store.length, 1);
    });
  }
}
