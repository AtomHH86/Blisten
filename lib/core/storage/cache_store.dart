import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// 缓存根目录
  ///
  /// 放在**应用内部私有目录**（与 SharedPreferences 索引同一分区、同一生命周期），
  /// 而不是外部的 `/Android/data/<pkg>/` 目录。外部目录在部分覆盖安装 /
  /// 系统清理场景下会被清空，而内部 SharedPreferences 不会，
  /// 结果就是「列表里还有、文件却没了」。
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
    // 清理磁盘上已被删掉的孤儿文件 + 校验索引与文件一致
    unawaited(_reconcile());
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_entries.map((e) => e.toJson()).toList()),
    );
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
          if (await File('${dir.path}/${e.fileName}').exists()) {
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
      for (final f in dir.listSync()) {
        if (f is File && !keep.contains(_basename(f.path))) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }

      if (dropped > 0) {
        debugPrint('[CacheStore] 清理失效缓存记录 $dropped 条');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _key,
          jsonEncode(_entries.map((e) => e.toJson()).toList()),
        );
      }
    } catch (e) {
      debugPrint('[CacheStore] 对账失败: $e');
    }
  }

  /// 旧版本把音频放在外部目录，这里尽量搬回内部目录，避免更新后缓存作废
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
      for (final f in files) {
        final name = _basename(f.path);
        if (name.endsWith('.part')) {
          try {
            f.deleteSync();
          } catch (_) {}
          continue;
        }
        final target = File('${newDir.path}/$name');
        if (await target.exists()) continue;
        try {
          await f.rename(target.path);
          moved++;
        } catch (_) {
          // 跨分区重命名失败则复制
          try {
            await f.copy(target.path);
            await f.delete();
            moved++;
          } catch (_) {}
        }
      }
      if (moved > 0) {
        debugPrint('[CacheStore] 已从外部目录迁移 $moved 个缓存文件');
      }
      if (oldDir.listSync().isEmpty) {
        try {
          await oldDir.delete(recursive: true);
        } catch (_) {}
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
    /// 预计大小（字节），用于下载前的空间检查
    int? expectBytes,
  }) async {
    if (isCached(bvid, cid)) return true;

    // 空间检查：按音频码率粗估所需大小，空间不足就别白跑一趟
    if (expectBytes != null && expectBytes > 0) {
      final free = await freeSpace();
      if (free >= 0 && free < expectBytes * 1.2) {
        debugPrint('[CacheStore] 空间不足：需要约 ${expectBytes ~/ 1024 ~/ 1024}MB，'
            '可用 ${free ~/ 1024 ~/ 1024}MB');
        return false;
      }
    }

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
        ..error = _describeError(e);
      notifyListeners();
      return false;
    }
  }

  /// 把底层异常翻译成用户看得懂的原因
  static String _describeError(Object e) {
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

  /// 清空全部缓存（内部目录 + 旧版遗留的外部目录）
  Future<void> clearAll() async {
    _entries.clear();
    await _save();
    try {
      final dir = await audioDir();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {}
    // 顺手清掉旧版外部目录，避免残留文件下次启动又被迁回来
    try {
      final extBase = await getExternalStorageDirectory();
      if (extBase != null) {
        final old = Directory('${extBase.path}/audio_cache');
        if (await old.exists()) await old.delete(recursive: true);
      }
    } catch (_) {}
  }
}