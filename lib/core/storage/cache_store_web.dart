import 'package:flutter/foundation.dart';

import '../../models/chapter.dart';
import '../../models/content_mode.dart';
import 'cache_models.dart';

export 'cache_models.dart';

/// Web 当前只支持在线播放，不创建离线索引、任务或音频文件。
class CacheStore extends ChangeNotifier {
  CacheStore._();
  static final CacheStore instance = CacheStore._();

  bool get supported => false;
  String get unsupportedReason => '网页版暂不支持离线音频缓存';

  List<CacheEntry> get entries => const [];
  List<CacheTask> get tasks => const [];
  List<CacheFailure> get failures => const [];
  List<CacheEvent> get events => const [];
  bool get busy => false;
  bool get clearing => false;
  int get queueLength => 0;
  int get queueDone => 0;
  int get queueFailed => 0;
  int get pendingCount => 0;
  double get queueProgress => 0;
  ({int done, int total, int failed}) get batchStat =>
      (done: 0, total: 0, failed: 0);
  int get totalSize => 0;
  String get totalSizeText => '0 MB';

  Future<String?> Function(String bvid, int cid)? resumeResolver;
  Map<String, String> resumeHeaders = const {};
  void Function()? onProgressChanged;
  void Function()? onQueueFinished;

  Future<void> load() async {}

  /// 共享启动流程可以调用；Web 不读取原生队列，也不调用解析器。
  void enableResume({
    required Future<String?> Function(String bvid, int cid) resolver,
    required Map<String, String> headers,
  }) {}

  bool isCached(String bvid, int cid) => false;
  Future<bool> isUsable(CacheEntry entry) async => false;
  List<CacheEntry> entriesOf(String bvid) => [];
  List<Chapter> chaptersOf(String bvid) => [];
  int countOf(String bvid) => 0;
  String? pathOf(String bvid, int cid) => null;
  CacheTask? taskOf(String bvid, int cid) => null;
  Future<String?> cacheFilePath(String bvid, int cid) async => null;
  List<({String bvid, String title, String cover, int count, int bytes, int cachedAt})>
      cachedBooks() => [];
  Future<int> freeSpace() async => -1;
  Future<String> dirPath() async => '';
  Future<({int count, int bytes})> diskUsage() async => (count: 0, bytes: 0);

  Future<void> enqueue({
    required String bvid,
    required String bookTitle,
    required String cover,
    ContentMode contentMode = ContentMode.audiobook,
    required List<({int cid, String chapterTitle, int durationSec, int page, String part, int order})>
        items,
    required Future<String?> Function(String bvid, int cid) resolveUrl,
    required Map<String, String> headers,
  }) async => throw UnsupportedError(unsupportedReason);

  Future<void> retryFailed({
    required Future<String?> Function(String bvid, int cid) resolveUrl,
    required Map<String, String> headers,
  }) async => throw UnsupportedError(unsupportedReason);

  Future<bool> download({
    required String bvid,
    required int cid,
    required String url,
    required String bookTitle,
    required String chapterTitle,
    required String cover,
    required int durationSec,
    required Map<String, String> headers,
    ContentMode contentMode = ContentMode.audiobook,
    int page = 0,
    String part = '',
    int order = 0,
    int? expectBytes,
    void Function(double progress)? onProgress,
  }) async => throw UnsupportedError(unsupportedReason);

  Future<void> recache(CacheEntry entry, {
    required Future<String?> Function(String bvid, int cid) resolveUrl,
    required Map<String, String> headers,
  }) async => throw UnsupportedError(unsupportedReason);

  void logEvent(String text) {}
  void clearEvents() {}
  void clearFailures() {}
  void clearFinishedTasks() {}
  void clearTask(String bvid, int cid) {}
  Future<void> cancelQueued(String bvid, int cid) async {}
  Future<void> remove(String bvid, int cid) async {}
  Future<void> dropIfBroken(String bvid, int cid) async {}
  Future<void> removeBook(String bvid) async {}
  Future<void> clearAll() async {}
}
