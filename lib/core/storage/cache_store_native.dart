import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/chapter.dart';
import '../../models/content_mode.dart';
import 'cache_media_validation.dart';
import 'cache_models.dart';

export 'cache_models.dart';

/// 离线缓存：下载音频到应用私有目录 + 元数据持久化
class CacheStore extends ChangeNotifier {
  CacheStore._();
  static final CacheStore instance = CacheStore._();

  bool get supported => true;
  String? get unsupportedReason => null;

  static const _key = 'abts_cache_index';
  static const _pendingKey = 'abts_cache_pending';
  static const _eventsKey = 'abts_cache_events';

  /// 最近的缓存事件（排查用，跨重启保留）
  final List<CacheEvent> _events = [];
  List<CacheEvent> get events => List.unmodifiable(_events);

  /// 记一条事件；只记关键动作，不记下载进度，避免刷屏和频繁写盘
  void logEvent(String text) {
    _events.insert(0, CacheEvent(
        DateTime.now().millisecondsSinceEpoch, text));
    if (_events.length > 60) _events.removeLast();
    unawaited(_persistEvents());
  }

  void clearEvents() {
    _events.clear();
    unawaited(_persistEvents());
  }

  Future<void> _persistEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _eventsKey,
        jsonEncode(_events.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _loadEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_eventsKey);
      if (raw == null) return;
      final arr = jsonDecode(raw) as List;
      _events
        ..clear()
        ..addAll(arr.map((e) => CacheEvent.fromJson((e as Map).cast<String, dynamic>())));
    } catch (_) {}
  }

  final List<CacheEntry> _entries = [];
  final Map<String, CacheTask> _tasks = {};

  /// 本批次已完成 / 失败的集数，用于让进度条在一整批里单调递增
  /// （之前只统计「当前还挂在 _tasks 里的任务」，每下完一集进度就会掉回 0）
  int _batchTotal = 0;
  int _batchDone = 0;
  int _batchFailed = 0;

  /// 本批次失败的集（可一键重试）
  final List<CacheFailure> _failures = [];
  List<CacheFailure> get failures => List.unmodifiable(_failures);

  /// 跨进程重启后仍需下载的项
  final List<CacheRequest> _pendingOnDisk = [];

  /// 正在下载的那一项（出队但未完成），落盘时用它保住书名等信息
  CacheRequest? _active;

  /// 缓存根目录
  ///
  /// 放在**应用内部私有目录**（与 SharedPreferences 索引同一分区、同一生命周期），
  /// 而不是外部的 `/Android/data/<pkg>/` 目录。外部目录在部分覆盖安装 /
  /// 系统清理场景下会被清空，而内部 SharedPreferences 不会，
  /// 结果就是「列表里还有、文件却没了」。
  Directory? _dir;
  final Dio _dio = Dio();
  Future<void> _ready = Future<void>.value();
  Future<void>? _loadingFuture;
  Future<void>? _clearing;
  Future<void>? _pendingWrite;
  int _generation = 0;
  Completer<void> _generationCanceled = Completer<void>();
  final Set<CancelToken> _cancelTokens = {};
  final Set<Future<bool>> _writers = {};
  bool get clearing => _clearing != null;

  List<CacheEntry> get entries => List.unmodifiable(_entries);

  /// 正在下载的任务
  List<CacheTask> get tasks => List.unmodifiable(_tasks.values);

  bool get busy => _tasks.values.any((t) => !t.done && !t.failed);

  // ---------- 后台缓存队列 ----------

  /// 队列中的待下载项（由页面入队，下载在 CacheStore 内串行执行，
  /// 因此离开弹窗、切页面、回到桌面都不会中断）
  final List<CacheRequest> _queue = [];
  Future<void>? _drainFuture;

  /// 由入队方（播放/详情页）注入：解析下载地址与下载请求头
  Future<String?> Function(String bvid, int cid)? _resolveUrl;
  Map<String, String> _headers = const {};

  /// 启动后续传用（由 main 注入，避免 core 层依赖网络层）
  Future<String?> Function(String bvid, int cid)? resumeResolver;
  Map<String, String> resumeHeaders = const {};

  /// 两集之间至少间隔这么久，连续取 playurl 容易被风控
  static const _itemGap = Duration(milliseconds: 1500);
  /// 解析地址失败后的重试次数
  static const _urlAttempts = 2;

  int get queueLength => _queue.length;
  int get queueDone => _batchDone;
  int get queueFailed => _batchFailed;

  /// 仍在进行中的数量：排队中的 + 正在下载的 1 个
  int get pendingCount =>
      _queue.length + (_tasks.values.any((t) => !t.done && !t.failed) ? 1 : 0);

  /// 队列总进度（0~1）；一批任务内单调递增，没有任务时为 0
  double get queueProgress {
    final total = _batchTotal;
    if (total <= 0) return 0;
    var acc = _batchDone.toDouble();
    for (final t in _tasks.values) {
      if (!t.done && !t.failed) acc += t.progress;
    }
    return (acc / total).clamp(0.0, 1.0);
  }

  /// 批量进度描述，用于页面与通知栏
  ({int done, int total, int failed}) get batchStat =>
      (done: _batchDone, total: _batchTotal, failed: _batchFailed);

  /// 入队一批下载任务并立即在后台开始执行
  Future<void> enqueue({
    required String bvid,
    required String bookTitle,
    required String cover,
    ContentMode contentMode = ContentMode.audiobook,
    required List<({int cid, String chapterTitle, int durationSec, int page, String part, int order})>
        items,
    required Future<String?> Function(String bvid, int cid) resolveUrl,
    required Map<String, String> headers,
  }) async {
    if (items.isEmpty) return;
    final generation = await _prepareWork();
    if (generation == null || generation != _generation || clearing) return;
    _resolveUrl = resolveUrl;
    _headers = headers;
    var added = 0;
    for (final it in items) {
      if (isCached(bvid, it.cid)) continue;
      final key = '$bvid-${it.cid}';
      if (_tasks.containsKey(key)) continue;
      if (_queue.any((e) => e.bvid == bvid && e.cid == it.cid)) continue;
      _tasks[key] = CacheTask(
        bvid: bvid,
        cid: it.cid,
        title: it.chapterTitle,
        contentMode: contentMode,
      );
      _queue.add(CacheRequest(
        bvid: bvid,
        bookTitle: bookTitle,
        cover: cover,
        cid: it.cid,
        chapterTitle: it.chapterTitle,
        durationSec: it.durationSec,
        page: it.page,
        part: it.part,
        order: it.order,
        contentMode: contentMode,
      ));
      added++;
    }
    if (added == 0) return;
    // 合并到同一批统计里，保证进度条不因多次入队而归零
    _batchTotal += added;
    // 同批次重试时清掉这些集的失败记录
    _failures.removeWhere(
        (f) => f.bvid == bvid && items.any((i) => i.cid == f.cid));
    await _persistPending();
    if (generation != _generation) return;
    notifyListeners();
    unawaited(_drain());
  }

  /// 一键重试本批次失败的集
  Future<void> retryFailed({
    required Future<String?> Function(String bvid, int cid) resolveUrl,
    required Map<String, String> headers,
  }) async {
    if (_failures.isEmpty) return;
    final grouped = <String,
        List<({int cid, String chapterTitle, int durationSec, int page, String part, int order})>>{};
    final titles = <String, String>{};
    final modes = <String, ContentMode>{};
    final covers = <String, String>{};
    for (final f in _failures) {
      grouped.putIfAbsent(f.bvid, () => []).add((
            cid: f.cid,
            chapterTitle: f.chapterTitle,
            durationSec: f.durationSec,
            page: f.page,
            part: f.part,
            order: f.order,
          ));
      titles[f.bvid] = f.bookTitle;
      modes[f.bvid] = f.contentMode;
      covers[f.bvid] = f.cover;
    }
    _failures.clear();
    for (final e in grouped.entries) {
      await enqueue(
        bvid: e.key,
        bookTitle: titles[e.key] ?? '',
        contentMode: modes[e.key] ?? ContentMode.audiobook,
        cover: covers[e.key] ?? '',
        items: e.value,
        resolveUrl: resolveUrl,
        headers: headers,
      );
    }
  }

  void clearFailures() {
    if (_failures.isEmpty) return;
    _failures.clear();
    notifyListeners();
  }

  /// 取消排队中（尚未开始）的任务
  Future<void> cancelQueued(String bvid, int cid) async {
    if (!_queue.any((e) => e.bvid == bvid && e.cid == cid)) return;
    _queue.removeWhere((e) => e.bvid == bvid && e.cid == cid);
    if (_tasks.remove('$bvid-$cid') != null) _batchTotal--;
    notifyListeners();
    await _persistPending();
  }

  /// 清空任务记录（全部完成后调用，避免列表里堆积）
  void clearFinishedTasks() {
    _tasks.removeWhere((_, t) => t.done || t.failed);
    notifyListeners();
  }

  Future<int?> _prepareWork() async {
    while (_clearing != null) {
      await _clearing;
    }
    final generation = _generation;
    await _ready;
    return generation == _generation ? generation : null;
  }

  Future<void> _drain() {
    final active = _drainFuture;
    if (active != null) return active;
    if (_queue.isEmpty) return Future<void>.value();
    final work = _runDrain(_generation, _generationCanceled.future);
    _drainFuture = work;
    void finished() {
      if (identical(_drainFuture, work)) _drainFuture = null;
    }
    unawaited(work.then((_) => finished(), onError: (Object _, StackTrace _) => finished()));
    return work;
  }

  Future<void> _runDrain(int generation, Future<void> canceled) async {
    bool current() => generation == _generation;
    try {
      var first = true;
      while (current() && _queue.isNotEmpty) {
        if (!first) {
          // 间隔可被清空操作唤醒，醒来后再次检查队列和代次。
          await Future.any([Future<void>.delayed(_itemGap), canceled]);
        }
        if (!current() || _queue.isEmpty) return;
        first = false;
        final item = _queue.removeAt(0);
        final key = '${item.bvid}-${item.cid}';
        final task = _tasks[key];
        if (task == null) continue;
        _active = item;
        task
          ..done = false
          ..failed = false
          ..progress = 0
          ..error = null;
        notifyListeners();

        final url = await _resolveWithRetry(item, generation, canceled);
        if (!current()) return;
        if (url == null) {
          _recordFailure(item, '网络繁忙，未能获取下载地址，请重试');
          _tasks.remove(key);
          _active = null;
          await _persistPending();
          if (!current()) return;
          notifyListeners();
          _onQueueProgress();
          continue;
        }
        final ok = await download(
          bvid: item.bvid, cid: item.cid, url: url,
          bookTitle: item.bookTitle, chapterTitle: item.chapterTitle,
          cover: item.cover, durationSec: item.durationSec, headers: _headers,
          page: item.page, part: item.part, order: item.order,
          contentMode: item.contentMode,
          expectBytes: item.durationSec > 0 ? item.durationSec * 16500 + 2097152 : null,
          onProgress: (p) {
            if (!current() || !identical(_tasks[key], task)) return;
            task.progress = p;
            notifyListeners();
            _onQueueProgress();
          },
        );
        if (!current()) return;
        if (ok) {
          _batchDone++;
        } else {
          _recordFailure(item, task.error ?? '缓存失败，请重试');
        }
        _tasks.remove(key);
        _active = null;
        await _persistPending();
        if (!current()) return;
        notifyListeners();
        _onQueueProgress();
      }
    } catch (e) {
      if (current()) logEvent('缓存队列未完成：${e.runtimeType}');
    } finally {
      if (current()) {
        _active = null;
        if (_queue.isEmpty && _tasks.isEmpty && _failures.isEmpty) {
          _batchTotal = 0;
          _batchDone = 0;
          _batchFailed = 0;
        }
        notifyListeners();
        _onQueueDone();
      }
    }
  }

  /// URL 请求可能无法中止；清空时停止等待，迟到结果不再进入下载路径。
  Future<String?> _resolveWithRetry(CacheRequest item, int generation,
      Future<void> canceled) async {
    final resolver = _resolveUrl;
    for (var i = 0; i < _urlAttempts; i++) {
      if (i > 0) {
        await Future.any([Future<void>.delayed(Duration(milliseconds: 2000 * i)), canceled]);
      }
      if (generation != _generation) return null;
      try {
        final url = await Future.any<String?>([
          Future<String?>.sync(() => resolver?.call(item.bvid, item.cid)),
          canceled.then((_) => null),
        ]);
        if (generation != _generation) return null;
        if (url != null && url.isNotEmpty) return url;
      } catch (_) {
        if (generation != _generation) return null;
      }
    }
    return null;
  }

  void _recordFailure(CacheRequest item, String reason) {
    _failures.removeWhere(
        (f) => f.bvid == item.bvid && f.cid == item.cid);
    _failures.add(CacheFailure(
      bvid: item.bvid,
      cid: item.cid,
      bookTitle: item.bookTitle,
      chapterTitle: item.chapterTitle,
      reason: reason,
      at: DateTime.now().millisecondsSinceEpoch,
      page: item.page,
      part: item.part,
      order: item.order,
      contentMode: item.contentMode,
      cover: item.cover,
      durationSec: item.durationSec,
    ));
    _batchFailed++;
  }

  /// 队列进度变化回调（用于刷新通知栏）
  void Function()? onProgressChanged;
  /// 队列全部结束回调
  void Function()? onQueueFinished;

  void _onQueueProgress() => onProgressChanged?.call();
  void _onQueueDone() => onQueueFinished?.call();

  int get totalSize => _entries.fold(0, (s, e) => s + e.sizeBytes);

  String get totalSizeText {
    final b = totalSize;
    if (b <= 0) return '0 MB';
    final mb = b / 1024 / 1024;
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// 缓存根目录（供播放时定位文件）
  Future<Directory> audioDir() async {
    if (_dir != null) return _dir!;
    Directory d;
    try {
      final base = await getApplicationSupportDirectory();
      d = Directory('${base.path}/audio_cache');
    } catch (_) {
      // 内部目录拿不到时退回外部私有目录
      final base =
          await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      d = Directory('${base.path}/audio_cache');
    }
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  Future<Directory> _root() => audioDir();

  /// 某个缓存条目对应的文件路径
  Future<File> fileOf(CacheEntry e) async {
    final d = await audioDir();
    return File('${d.path}/${e.fileName}');
  }

  /// 检查是否有可用音频，供共享界面使用，不将原生文件对象暴露到界面。
  Future<bool> isUsable(CacheEntry entry) async {
    try {
      final file = await fileOf(entry);
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  /// 剩余可用空间（字节）；拿不到时返回 -1
  Future<int> freeSpace() async {
    try {
      final v = await const MethodChannel('abts/storage')
          .invokeMethod<int>('freeBytes');
      return v ?? -1;
    } catch (_) {
      return -1;
    }
  }

  Future<void> load() {
    final active = _loadingFuture;
    if (active != null) return active;
    final work = _loadAndReconcile();
    _ready = work;
    _loadingFuture = work;
    void finished() {
      if (identical(_loadingFuture, work)) _loadingFuture = null;
    }
    unawaited(work.then((_) => finished(), onError: (Object _, StackTrace _) => finished()));
    return work;
  }

  Future<void> _loadAndReconcile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    await _loadEvents();
    _entries.clear();
    if (raw != null) {
      try {
        final arr = jsonDecode(raw) as List;
        _entries
          ..clear()
          ..addAll(arr.map(
              (e) => CacheEntry.fromJson((e as Map).cast<String, dynamic>())));
      } catch (_) {}
    }
    // 读取上次没下完的队列，等 main 注入 resolver 后自动续传
    final rawPending = prefs.getString(_pendingKey);
    _pendingOnDisk.clear();
    if (rawPending != null) {
      try {
        final arr = jsonDecode(rawPending) as List;
        _pendingOnDisk.addAll(arr.map(
            (e) => CacheRequest.fromJson((e as Map).cast<String, dynamic>())));
      } catch (_) {}
    }
    // 清理磁盘上已被删掉的孤儿文件 + 校验索引与文件一致
    await _reconcile();
  }

  /// 注入续传所需的地址解析器与请求头，并在有未完成队列时自动开始
  void enableResume({
    required Future<String?> Function(String bvid, int cid) resolver,
    required Map<String, String> headers,
  }) {
    resumeResolver = resolver;
    resumeHeaders = headers;
    unawaited(_resumePending());
  }

  /// 启动后自动续传上次未完成的缓存队列
  ///
  /// 进程被杀 / 用户划掉重进时队列不会丢，联网后接着下。
  Future<void> _resumePending() async {
    final generation = await _prepareWork();
    if (generation == null || generation != _generation || clearing) return;
    if (_pendingOnDisk.isEmpty || _queue.isNotEmpty) return;
    final items = _pendingOnDisk.toList();
    _pendingOnDisk.clear();
    var added = 0;
    for (final it in items) {
      if (it.bvid.isEmpty || it.cid == 0) continue;
      if (isCached(it.bvid, it.cid)) continue;
      if (_queue.any((e) => e.bvid == it.bvid && e.cid == it.cid)) continue;
      _tasks['${it.bvid}-${it.cid}'] = CacheTask(
        bvid: it.bvid,
        cid: it.cid,
        title: it.chapterTitle,
        contentMode: it.contentMode,
      );
      _queue.add(it);
      added++;
    }
    if (added == 0) return;
    _batchTotal += added;
    _resolveUrl = resumeResolver;
    _headers = resumeHeaders;
    debugPrint('[CacheStore] 续传上次未完成的 $added 集缓存');
    await _persistPending();
    if (generation != _generation) return;
    notifyListeners();
    unawaited(_drain());
  }

  /// 把尚未完成的队列落盘，保证重启后能续传
  Future<void> _persistPending() {
    final all = <CacheRequest>[..._pendingOnDisk, ..._queue];
    final active = _active;
    if (active != null && !all.any((e) => e.bvid == active.bvid && e.cid == active.cid)) {
      all.add(active);
    }
    return _writePreference(_pendingKey,
        all.isEmpty ? null : jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  /// 在调用时捕获快照并顺序写入，清空后的空快照始终排在旧写入之后。
  Future<void> _writePreference(String key, String? value) {
    final previous = _pendingWrite;
    final write = () async {
      if (previous != null) {
        try { await previous; } catch (_) { /* 后续保存仍需继续。 */ }
      }
      final prefs = await SharedPreferences.getInstance();
      final saved = value == null ? await prefs.remove(key) : await prefs.setString(key, value);
      if (!saved) throw StateError('缓存信息保存失败');
    }();
    _pendingWrite = write;
    void finished() {
      if (identical(_pendingWrite, write)) _pendingWrite = null;
    }
    unawaited(write.then((_) => finished(), onError: (Object _, StackTrace _) => finished()));
    return write;
  }

  Future<void> _save() async {
    await _writePreference(_key, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  /// 启动时对账：让「索引」与「磁盘文件」保持一致，杜绝幽灵条目
  ///
  /// 两个方向都要处理：
  /// 1. 索引里有、磁盘上没有 → 记录失效，从列表移除（否则用户点播放才发现没了）；
  /// 2. 磁盘上有、索引里没有 → 孤儿文件（多为上次下载中断），直接删掉。
  /// 同时尝试把旧版本放在外部目录的缓存迁移到新的内部目录。
  Future<void> _reconcile() async {
    try {
      // ① 旧版迁移：从外部目录搬到内部目录，尽量保住用户已有的缓存
      await _migrateFromExternal();

      final dir = await audioDir();
      // ② 索引 → 磁盘：文件没了就摘掉记录
      final alive = <CacheEntry>[];
      for (final e in _entries) {
        try {
          final f = File('${dir.path}/${e.fileName}');
          // 0 字节同样算损坏（多半是写盘被打断留下的残次品）
          if (await f.exists() && await f.length() > 0) {
            alive.add(e);
          } else {
            debugPrint('[CacheStore] 缓存文件已丢失，移除记录 ${e.bvid}/${e.cid}');
          }
        } catch (_) {
          alive.add(e);
        }
      }
      final dropped = _entries.length - alive.length;
      _entries
        ..clear()
        ..addAll(alive);

      // ③ 磁盘 → 索引：孤儿文件清掉（含 .part 下载残片）
      final keep = _entries.map((e) => e.fileName).toSet();
      var orphans = 0;
      for (final f in dir.listSync()) {
        if (f is File && !keep.contains(_basename(f.path))) {
          try {
            f.deleteSync();
            orphans++;
          } catch (_) {}
        }
      }
      if (orphans > 0) logEvent('清理孤儿文件 $orphans 个');

      if (dropped > 0) {
        debugPrint('[CacheStore] 清理失效缓存记录 $dropped 条');
        logEvent('启动对账：${_entries.length} 条记录中 $dropped 条文件已丢失，已移除');
        await _save();
      } else if (_entries.isNotEmpty) {
        logEvent('启动对账：${_entries.length} 条记录与磁盘一致');
      }
    } catch (e) {
      debugPrint('[CacheStore] 对账失败: $e');
      logEvent('启动对账异常：$e');
    }
  }

  /// 旧版本把音频放在外部目录，这里搬到内部目录。
  ///
  /// 安全策略：**先复制 → 校验大小一致 → 才删除源文件**。
  /// 任何一步失败都保留源文件，绝不做「移动失败但源也没了」的操作。
  Future<void> _migrateFromExternal() async {
    try {
      final extBase = await getExternalStorageDirectory();
      if (extBase == null) return;
      final oldDir = Directory('${extBase.path}/audio_cache');
      if (!await oldDir.exists()) return;

      final files = oldDir.listSync().whereType<File>().toList();
      if (files.isEmpty) return;

      final newDir = await audioDir();
      var moved = 0;
      final failed = <String>[];
      for (final f in files) {
        final name = _basename(f.path);
        if (name.endsWith('.part')) {
          try {
            f.deleteSync();
          } catch (_) {}
          continue;
        }
        final target = File('${newDir.path}/$name');
        if (await target.exists()) {
          // 目标已存在且大小一致，源文件可以安全丢弃
          try {
            final s1 = await f.length();
            final s2 = await target.length();
            if (s1 == s2) {
              await f.delete();
              moved++;
            } else {
              failed.add(name);
            }
          } catch (_) {
            failed.add(name);
          }
          continue;
        }
        try {
          final srcSize = await f.length();
          await f.copy(target.path);
          final dstSize = await target.length();
          if (dstSize != srcSize || srcSize <= 0) {
            // 校验不通过：删掉半成品，保留源文件
            try {
              await target.delete();
            } catch (_) {}
            failed.add(name);
            debugPrint('[CacheStore] 迁移校验失败 $name（$srcSize -> $dstSize）');
            continue;
          }
          await f.delete();
          moved++;
        } catch (e) {
          failed.add(name);
          debugPrint('[CacheStore] 迁移失败 $name: $e');
        }
      }
      debugPrint('[CacheStore] 迁移完成：成功 $moved，失败 ${failed.length}');
      // 只有全部搬完才删除旧目录
      if (moved > 0 && oldDir.listSync().isEmpty) {
        try {
          await oldDir.delete(recursive: true);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[CacheStore] 迁移异常: $e');
    }
  }

  /// 缓存目录的实际路径（展示给用户排查用）
  Future<String> dirPath() async => (await audioDir()).path;

  /// 磁盘上真实的缓存文件数量与体积（用于与索引对账展示）
  Future<({int count, int bytes})> diskUsage() async {
    try {
      final dir = await audioDir();
      var count = 0;
      var bytes = 0;
      for (final f in dir.listSync()) {
        if (f is File) {
          count++;
          bytes += f.lengthSync();
        }
      }
      return (count: count, bytes: bytes);
    } catch (_) {
      return (count: 0, bytes: 0);
    }
  }

  static String _basename(String p) => p.split(Platform.pathSeparator).last;

  bool isCached(String bvid, int cid) {
    return _entries.any((e) => e.bvid == bvid && e.cid == cid);
  }

  List<CacheEntry> entriesOf(String bvid) =>
      _entries.where((e) => e.bvid == bvid).toList();

  /// 用缓存索引重建某本书的章节列表（**离线时的兜底数据源**）
  ///
  /// 离线不是另一套播放逻辑，只是「取不到在线数据源时改用本地索引」。
  /// 这里返回这本书已缓存的所有集，按作品原始章节顺序排列，
  /// 让目录、上一篇/下一篇在无网时依然可用。
  List<Chapter> chaptersOf(String bvid) {
    final list = entriesOf(bvid)..sort(CacheEntry.compareByOrder);
    return list.map((e) => e.toChapter()).toList();
  }

  /// 缓存里出现过的所有书籍（离线时给发现页/书架页兜底）
  ///
  /// 按最近缓存时间倒序，并带出该书已缓存的集数。
  List<({String bvid, String title, String cover, int count, int bytes, int cachedAt})>
      cachedBooks() {
    final g = <String, List<CacheEntry>>{};
    for (final e in _entries) {
      g.putIfAbsent(e.bvid, () => []).add(e);
    }
    final out = g.entries.map((kv) {
      final list = kv.value..sort(CacheEntry.compareByOrder);
      return (
        bvid: kv.key,
        title: list.first.bookTitle,
        cover: list.first.cover,
        count: list.length,
        bytes: list.fold<int>(0, (s, e) => s + e.sizeBytes),
        cachedAt: list.last.cachedAt,
      );
    }).toList();
    out.sort((a, b) => b.cachedAt.compareTo(a.cachedAt));
    return out;
  }

  int countOf(String bvid) => entriesOf(bvid).length;

  String? pathOf(String bvid, int cid) {
    for (final e in _entries) {
      if (e.bvid == bvid && e.cid == cid) return e.fileName;
    }
    return null;
  }

  CacheTask? taskOf(String bvid, int cid) => _tasks['$bvid-$cid'];

  /// 下载一个章节到本地
  ///
  /// [headers] 必须带 UA/Referer，否则 CDN 会 403。
  /// 返回 true 表示成功。
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
    /// 分P序号，用于缓存页按作品原顺序展示
    int page = 0,
    /// 章节标题（不含「第 N 章 · 」前缀），离线重建章节列表时要用
    String part = '',
    /// 在章节列表中的原始下标，用于缓存页排序
    int order = 0,
    /// 预计大小（字节），用于下载前的空间检查
    int? expectBytes,
    /// 下载进度回调（0~1）
    void Function(double progress)? onProgress,
  }) async {
    final generation = await _prepareWork();
    if (generation == null || generation != _generation || clearing) return false;
    if (isCached(bvid, cid)) return true;
    final request = CacheRequest(
      bvid: bvid, cid: cid, bookTitle: bookTitle, chapterTitle: chapterTitle,
      cover: cover, durationSec: durationSec, page: page, part: part,
      order: order, contentMode: contentMode,
    );
    final work = _downloadToFile(request, url, headers, generation,
        expectBytes: expectBytes, onProgress: onProgress);
    _writers.add(work);
    try {
      return await work;
    } finally {
      _writers.remove(work);
    }
  }

  Future<bool> _downloadToFile(CacheRequest request, String url,
      Map<String, String> headers, int generation,
      {int? expectBytes, void Function(double)? onProgress}) async {
    final bvid = request.bvid;
    final cid = request.cid;
    final key = '$bvid-$cid';
    final task = _tasks.putIfAbsent(key, () => CacheTask(
        bvid: bvid, cid: cid, title: request.chapterTitle, contentMode: request.contentMode));
    bool current() => generation == _generation && identical(_tasks[key], task);
    final cancel = CancelToken();
    _cancelTokens.add(cancel);
    File? tmp;
    notifyListeners();
    try {
      if (expectBytes != null && expectBytes > 0) {
        final free = await freeSpace();
        if (!current()) return false;
        if (free >= 0 && free < expectBytes * 1.2) throw StateError('存储空间不足');
      }
      final dir = await _root();
      if (!current()) return false;
      final target = File('${dir.path}/$key.m4a');
      tmp = File('${target.path}.part');
      final response = await _dio.download(
        url, tmp.path, cancelToken: cancel,
        options: Options(headers: headers, followRedirects: true,
          receiveTimeout: const Duration(minutes: 10)),
        onReceiveProgress: (received, total) {
          if (!current()) return;
          if (total > 0) {
            task.progress = (received / total).clamp(0.0, 1.0);
            onProgress?.call(task.progress);
          }
          notifyListeners();
        },
      );
      if (!current()) return false;
      final size = await validateCacheDownload(tmp,
          statusCode: response.statusCode,
          contentType: response.headers.value(Headers.contentTypeHeader),
          contentLength: int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? ''));
      if (!current()) return false;
      final exists = await target.exists();
      if (!current()) return false;
      if (exists) await target.delete();
      if (!current()) return false;
      await tmp.rename(target.path);
      tmp = null;
      if (!current()) return false;
      _entries.removeWhere((e) => e.bvid == bvid && e.cid == cid);
      _entries.add(CacheEntry(
        bvid: bvid, cid: cid, bookTitle: request.bookTitle,
        chapterTitle: request.chapterTitle, cover: request.cover,
        durationSec: request.durationSec, sizeBytes: size,
        cachedAt: DateTime.now().millisecondsSinceEpoch,
        page: request.page, part: request.part, order: request.order,
        contentMode: request.contentMode,
      ));
      await _save();
      if (!current()) return false;
      task..progress = 1..done = true;
      notifyListeners();
      return true;
    } catch (e) {
      if (current() && !(e is DioException && CancelToken.isCancel(e))) {
        debugPrint('[CacheStore] 下载失败 $bvid/$cid: ${e.runtimeType}');
        task..failed = true..error = _describeError(e);
        notifyListeners();
      }
      return false;
    } finally {
      _cancelTokens.remove(cancel);
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) { /* clearAll 会等待写入结束后再删除整个目录。 */ }
    }
  }

  /// 把底层异常翻译成用户看得懂的原因
  static String _describeError(Object e) {
    if (e is FormatException) return '音频文件不完整或格式异常，请重新缓存';
    final s = '$e';
    if (s.contains('ENOSPC') ||
        s.contains('No space left') ||
        s.contains('空间不足')) {
      return '存储空间不足';
    }
    if (s.contains('404') || s.contains('403')) {
      return '下载链接已失效，请重试';
    }
    if (s.contains('SocketException') ||
        s.contains('Connection') ||
        s.contains('timeout')) {
      return '网络中断，请检查网络';
    }
    return '下载失败，请稍后重试';
  }

  /// 显式替换单条旧缓存；入队时保留原始作品与分 P 元数据。
  Future<void> recache(CacheEntry entry, {
    required Future<String?> Function(String bvid, int cid) resolveUrl,
    required Map<String, String> headers,
  }) async {
    await remove(entry.bvid, entry.cid);
    clearTask(entry.bvid, entry.cid);
    await enqueue(
      bvid: entry.bvid, bookTitle: entry.bookTitle, cover: entry.cover,
      contentMode: entry.contentMode,
      items: [(cid: entry.cid, chapterTitle: entry.chapterTitle,
        durationSec: entry.durationSec, page: entry.page,
        part: entry.part, order: entry.order)],
      resolveUrl: resolveUrl, headers: headers,
    );
  }

  /// 清除某个任务的记录（下载完成后调用，避免列表里堆积）
  void clearTask(String bvid, int cid) {
    _tasks.remove('$bvid-$cid');
    notifyListeners();
  }

  /// 删除单条缓存（含磁盘文件）
  Future<void> remove(String bvid, int cid) async {
    final file = await fileOf(CacheEntry(
        bvid: bvid, cid: cid, bookTitle: '', chapterTitle: ''));
    // File.exists() also returns false for a directory at this path. Do not
    // mistake an obstructed path for a successful removal or start recaching.
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      await file.delete();
    }
    _entries.removeWhere((e) => e.bvid == bvid && e.cid == cid);
    await _save();
  }

  /// 某集的缓存文件对象（路径与下载写盘时完全一致）
  Future<File?> _fileOf(String bvid, int cid) async {
    if (bvid.isEmpty || cid == 0) return null;
    final name =
        CacheEntry(bvid: bvid, cid: cid, bookTitle: '', chapterTitle: '').fileName;
    final dir = await audioDir();
    return File('${dir.path}/$name');
  }

  /// 取某集的缓存音频绝对路径；文件不存在或为空字节则返回 null（并按需摘掉失效记录）
  ///
  /// 这是**唯一**判断「缓存文件在不在」的地方。之前播放器自己拼路径查一次
  /// `exists()`、CacheStore 里又拼一次查一次，两处结论会相反——真机上出现过
  /// 同一秒内「文件不存在」和「文件完好」两条记录，因为播放器那处的异常被
  /// `catch (_) {}` 吞掉后直接当成文件丢了。现在只保留这一处判断，且失败原因
  /// 一定写进事件日志。
  Future<String?> cacheFilePath(String bvid, int cid) async {
    if (bvid.isEmpty || cid == 0) return null;
    try {
      final f = await _fileOf(bvid, cid);
      if (f == null) return null;
      final exists = await f.exists();
      final len = exists ? await f.length() : 0;
      if (exists && len > 0) return f.path;
      logEvent('缓存缺失 $bvid/$cid：${f.path}（存在=$exists 长度=$len）');
    } catch (e) {
      // 检查不出来就当作「不知道」，绝不能因此删用户的缓存
      logEvent('缓存检查异常 $bvid/$cid：$e');
      return null;
    }
    await dropIfBroken(bvid, cid);
    return null;
  }

  /// 播放本地缓存失败时的处理：**只有文件确实损毁（不存在或 0 字节）才删索引**
  ///
  /// 之前这里直接 `remove`，导致播放器 `open()` 抛一个瞬时异常就会把用户
  /// 几百 MB 的离线文件删掉——实测真机上《三体》一集 194MB 缓存就是这样
  /// 凭空消失的。打开失败绝大多数是播放器瞬时状态问题，文件本身是好的，
  /// 保留它最多下次多回退一次在线播放，代价远小于误删数据。
  Future<void> dropIfBroken(String bvid, int cid) async {
    if (bvid.isEmpty || cid == 0) return;
    try {
      final f = await _fileOf(bvid, cid);
      if (f != null && await f.exists() && await f.length() > 0) {
        logEvent('文件完好，保留缓存 $bvid/$cid');
        return; // 文件完好，保留用户的离线缓存
      }
      logEvent('文件确实丢失，移除记录 $bvid/$cid');
    } catch (e) {
      // 拿不到目录就保守处理：不删
      logEvent('检查文件异常，保留缓存 $bvid/$cid：$e');
      return;
    }
    await remove(bvid, cid);
  }

  /// 删除某本书的全部缓存
  Future<void> removeBook(String bvid) async {
    final targets = entriesOf(bvid);
    for (final entry in targets) {
      // Persist each confirmed deletion, retaining any item that failed.
      await remove(entry.bvid, entry.cid);
    }
  }

  /// 清空完成意味着旧写入已停止，文件、索引和待恢复队列均已清除。
  Future<void> clearAll() {
    final active = _clearing;
    if (active != null) return active;
    final done = Completer<void>();
    _clearing = done.future;
    unawaited(_clearAll().then(done.complete, onError: done.completeError));
    return done.future;
  }

  Future<void> _clearAll() async {
    ++_generation;
    _generationCanceled.complete();
    _generationCanceled = Completer<void>();
    for (final token in _cancelTokens) {
      token.cancel('清空缓存');
    }
    _queue.clear();
    _pendingOnDisk.clear();
    _active = null;
    _tasks.clear();
    _failures.clear();
    _batchTotal = 0;
    _batchDone = 0;
    _batchFailed = 0;
    notifyListeners();
    try {
      await _ready; // 对账/迁移也可能写文件，必须先收束。
      final drain = _drainFuture;
      if (drain != null) await drain;
      await Future.wait(_writers.toList());
      _pendingOnDisk.clear(); // load 在取消期间读到的旧恢复项也不能保留。
      await _persistPending();
      final dir = await audioDir();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
      if (Platform.isAndroid) {
        final extBase = await getExternalStorageDirectory();
        if (extBase != null) {
          final old = Directory('${extBase.path}/audio_cache');
          if (await old.exists()) await old.delete(recursive: true);
        }
      }
      _entries.clear();
      await _save();
      await _persistPending();
    } finally {
      _clearing = null;
      notifyListeners();
      _onQueueDone();
    }
  }
}
