import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/storage/cache_store.dart';
import 'package:flutter_test/flutter_test.dart';
// Exercise the actual file checks through the path_provider boundary.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getExternalStoragePath() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native usability reflects actual bytes without removing the cache index', () async {
    const entry = CacheEntry(bvid: 'native-capability', cid: 101,
        bookTitle: '缓存能力测试', chapterTitle: '第一章');
    final cache = CacheStore.instance;
    final previousPaths = PathProviderPlatform.instance;
    final root = await Directory.systemTemp.createTemp('blisten-cache-capability-');
    PathProviderPlatform.instance = _Paths(root.path);
    SharedPreferences.setMockInitialValues({
      'abts_cache_index': jsonEncode([entry.toJson()]),
    });
    addTearDown(() async {
      await cache.clearAll();
      await root.delete(recursive: true);
      PathProviderPlatform.instance = previousPaths;
    });

    final file = await cache.fileOf(entry);
    await File('test/fixtures/cache-silence.m4a').copy(file.path);
    await cache.load();
    expect(cache.supported, isTrue);
    expect(cache.unsupportedReason, isNull);
    expect(await cache.isUsable(entry), isTrue);

    await file.writeAsBytes([]);
    expect(await cache.isUsable(entry), isFalse);
    expect(cache.isCached(entry.bvid, entry.cid), isTrue);

    await file.delete();
    expect(await cache.isUsable(entry), isFalse);
    expect(cache.isCached(entry.bvid, entry.cid), isTrue);
  });
}
