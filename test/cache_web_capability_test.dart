import 'package:blisten/core/storage/cache_store_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Observe the real Web store at the preferences platform boundary.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _Preferences extends InMemorySharedPreferencesStore {
  _Preferences() : super.withData({
    'flutter.abts_cache_index': '[{"bvid":"native-cache","cid":101}]',
    'flutter.abts_cache_pending': '[{"bvid":"pending-cache","cid":102}]',
    'flutter.abts_cache_events': '[{"at":1,"text":"native event"}]',
  });

  int reads = 0;
  int writes = 0;
  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    return super.getAll();
  }
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes++;
    return super.setValue(valueType, key, value);
  }
  @override
  Future<bool> remove(String key) async {
    writes++;
    return super.remove(key);
  }
  @override
  Future<bool> clear() async {
    writes++;
    return super.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = CacheStore.instance;
  const entry = CacheEntry(bvid: 'native-cache', cid: 101,
      bookTitle: '缓存能力测试', chapterTitle: '第一章');
  late _Preferences preferences;
  late SharedPreferencesStorePlatform previousPreferences;
  var resolverCalls = 0;

  Future<String?> resolve(String bvid, int cid) async {
    resolverCalls++;
    return 'https://example.invalid/audio.m4a';
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previousPreferences = SharedPreferencesStorePlatform.instance;
    preferences = _Preferences();
    SharedPreferencesStorePlatform.instance = preferences;
    resolverCalls = 0;
  });
  tearDown(() {
    SharedPreferencesStorePlatform.instance = previousPreferences;
  });

  test('Web load and resume leave native cache data untouched and remain empty', () async {
    final before = await preferences.getAll();
    preferences.reads = 0;
    await cache.load();
    cache.enableResume(resolver: resolve, headers: {});
    cache.logEvent('player requested cache');
    await cache.clearAll();
    cache.clearEvents();
    await Future<void>.value();

    expect(cache.supported, isFalse);
    expect(cache.unsupportedReason, isNotEmpty);
    expect(cache.entries, isEmpty);
    expect(cache.tasks, isEmpty);
    expect(cache.failures, isEmpty);
    expect(cache.events, isEmpty);
    expect(cache.pendingCount, 0);
    expect(cache.busy, isFalse);
    expect(cache.isCached(entry.bvid, entry.cid), isFalse);
    expect(await cache.isUsable(entry), isFalse);
    expect(await cache.cacheFilePath(entry.bvid, entry.cid), isNull);
    expect(cache.cachedBooks(), isEmpty);
    expect(resolverCalls, 0);
    expect(preferences.reads, 0);
    expect(preferences.writes, 0);
    expect(await preferences.getAll(), before);
  });

  test('Web enqueue rejects work before resolving URLs or recording tasks', () async {
    await expectLater(cache.enqueue(
      bvid: entry.bvid, bookTitle: entry.bookTitle, cover: '',
      items: [(cid: entry.cid, chapterTitle: entry.chapterTitle,
        durationSec: 90, page: 1, part: '第一章', order: 1)],
      resolveUrl: resolve, headers: {},
    ), throwsUnsupportedError);
    expect(resolverCalls, 0);
    expect(cache.tasks, isEmpty);
    expect(cache.entries, isEmpty);
    expect(cache.pendingCount, 0);
    expect(preferences.writes, 0);
  });

  test('Web download, retry and recache cannot report success', () async {
    var progressCalls = 0;
    await expectLater(cache.download(
      bvid: entry.bvid, cid: entry.cid,
      url: 'https://example.invalid/audio.m4a',
      bookTitle: entry.bookTitle, chapterTitle: entry.chapterTitle,
      cover: '', durationSec: 90, headers: {},
      onProgress: (_) => progressCalls++,
    ), throwsUnsupportedError);
    await expectLater(cache.retryFailed(resolveUrl: resolve, headers: {}),
        throwsUnsupportedError);
    await expectLater(cache.recache(entry, resolveUrl: resolve, headers: {}),
        throwsUnsupportedError);
    expect(progressCalls, 0);
    expect(resolverCalls, 0);
    expect(cache.entries, isEmpty);
    expect(cache.batchStat, (done: 0, total: 0, failed: 0));
    expect(preferences.writes, 0);
  });
}
