import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条离线缓存记录（一个章节一个文件）
class CacheEntry {
  final String bvid;
  final int cid;
  final String bookTitle;
  final String chapterTitle;
  final String cover;
  final int durationSec;
  final int sizeBytes;
  final int cachedAt;

  const CacheEntry({
    required this.bvid,
    required this.cid,
    required this.bookTitle,
    required this.chapterTitle,
    this.cover = '',
    this.durationSec = 0,
    this.sizeBytes = 0,
    this.cachedAt = 0,
  });

  String get fileName => '$bvid-$cid.m4a';

  String get sizeText {
    if (sizeBytes <= 0) return '';
    final mb = sizeBytes / 1024 / 1024;
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get durationText {
    if (durationSec <= 0) return '';
    final h = durationSec ~/ 3600;
    final m = (durationSec % 3600) ~/ 60;
    if (h > 0) return '$h 小时 $m 分';
    return '$m 分';
  }

  Map<String, dynamic> toJson() => {
        'bvid': bvid,
        'cid': cid,
        'bookTitle': bookTitle,
        'chapterTitle': chapterTitle,
        'cover': cover,
        'durationSec': durationSec,
        'sizeBytes': sizeBytes,
        'cachedAt': cachedAt,
      };

  factory CacheEntry.fromJson(Map<String, dynamic> m) => CacheEntry(
        bvid: m['bvid'] as String? ?? '',
        cid: int.tryParse('${m['cid'] ?? 0}') ?? 0,
        bookTitle: m['bookTitle'] as String? ?? '',
        chapterTitle: m['chapterTitle'] as String? ?? '',
        cover: m['cover'] as String? ?? '',
        durationSec: int.tryParse('${m['durationSec'] ?? 0}') ?? 0,
        sizeBytes: int.tryParse('${m['sizeBytes'] ?? 0}') ?? 0,
        cachedAt: int.tryParse('${m['cachedAt'] ?? 0}') ?? 0,
      );
}

/// 下载中的任务状态
class CacheTask {
  final String bvid;
  final int cid;
  final String title;
  double progress; // 0~1
  bool done;
  bool failed;
  String? error;

  CacheTask({
    required this.bvid,
    required this.cid,
    required this.title,
    this.progress = 0,
    this.done = false,
    this.failed = false,
    this.error,
  });

  String get key => '$bvid-$cid';
}

/// 离线缓存：下载音频到应用私有目录 + 元数据持久化
class CacheStore extends ChangeNotifier {
  CacheStore._();
  static final CacheStore instance = CacheStore._();

  static const _key = 'abts_cache_index';

  final List<CacheEntry> _entries = [];
  final Map<String, CacheTask> _tasks = {};

  /// 缓存根目录（应用外部私有目录，卸载即清理）
  Directory? _dir;
  final Dio _dio = Dio();

  List<CacheEntry> get entries => List.unmodifiable(_entries);

  /// 正在下载的任务
  List<CacheTask> get tasks => List.unmodifiable(_tasks.values);

  bool get busy => _tasks.values.any((t) => !t.done && !t.failed);

  int get totalSize => _entries.fold(0, (s, e) => s + e.sizeBytes);

  String get totalSizeText {
    final b = totalSize;
    if (b <= 0) return '0 MB';
    final mb = b / 1024 / 1024;
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<Directory> _root() async {
    if (_dir != null) return _dir!;
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/audio_cache');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final arr = jsonDecode(raw) as List;
        _entries
          ..clear()
          ..addAll(arr.map(
              (e) => CacheEntry.fromJson((e as Map).cast<String, dynamic>())));
      } catch (_) {}
    }
    // 清理磁盘上已被删掉的孤儿文件
    unawaited(_sweepOrphans());
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_entries.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  /// 删除记录里没有、但磁盘上残留的文件
  Future<void> _sweepOrphans() async {
    try {
      final dir = await _root();
      final keep = _entries.map((e) => e.fileName).toSet();
      for (final f in dir.listSync()) {
        if (f is File && !keep.contains(_basename(f.path))) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static String _basename(String p) => p.split(Platform.pathSeparator).last;

  bool isCached(String bvid, int cid) {
    return _entries.any((e) => e.bvid == bvid && e.cid == cid);
  }

  List<CacheEntry> entriesOf(String bvid) =>
      _entries.where((e) => e.bvid == bvid).toList();

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
  }) async {
    if (isCached(bvid, cid)) return true;
    final task = CacheTask(bvid: bvid, cid: cid, title: chapterTitle);
    _tasks[task.key] = task;
    notifyListeners();

    File? tmp;
    try {
      final dir = await _root();
      final name = CacheEntry(
        bvid: bvid,
        cid: cid,
        bookTitle: bookTitle,
        chapterTitle: chapterTitle,
      ).fileName;
      final target = File('${dir.path}/$name');
      tmp = File('${target.path}.part');

      await _dio.download(
        url,
        tmp.path,
        options: Options(
          headers: headers,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 10),
        ),
        onReceiveProgress: (r, t) {
          if (t > 0) task.progress = (r / t).clamp(0.0, 1.0);
          notifyListeners();
        },
      );

      final size = await tmp.length();
      if (size <= 0) throw StateError('下载内容为空');

      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
      tmp = null;

      _entries.removeWhere((e) => e.bvid == bvid && e.cid == cid);
      _entries.add(
        CacheEntry(
          bvid: bvid,
          cid: cid,
          bookTitle: bookTitle,
          chapterTitle: chapterTitle,
          cover: cover,
          durationSec: durationSec,
          sizeBytes: size,
          cachedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _save();
      task
        ..progress = 1
        ..done = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[CacheStore] 下载失败 $bvid/$cid: $e');
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
      task
        ..failed = true
        ..error = '$e';
      notifyListeners();
      return false;
    }
  }

  /// 清除某个任务的记录（下载完成后调用，避免列表里堆积）
  void clearTask(String bvid, int cid) {
    _tasks.remove('$bvid-$cid');
    notifyListeners();
  }

  /// 删除单条缓存（含磁盘文件）
  Future<void> remove(String bvid, int cid) async {
    _entries.removeWhere((e) => e.bvid == bvid && e.cid == cid);
    await _save();
    try {
      final dir = await _root();
      final f = File(
          '${dir.path}/${CacheEntry(bvid: bvid, cid: cid, bookTitle: '', chapterTitle: '').fileName}');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 删除某本书的全部缓存
  Future<void> removeBook(String bvid) async {
    final targets = entriesOf(bvid);
    _entries.removeWhere((e) => e.bvid == bvid);
    await _save();
    try {
      final dir = await _root();
      for (final e in targets) {
        final f = File('${dir.path}/${e.fileName}');
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  /// 清空全部缓存
  Future<void> clearAll() async {
    _entries.clear();
    await _save();
    try {
      final dir = await _root();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {}
  }
}