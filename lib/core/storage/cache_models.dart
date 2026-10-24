import '../../models/chapter.dart';
import '../../models/content_mode.dart';

/// 一条离线缓存记录（一个章节一个文件）
class CacheEntry {
  final String bvid;
  final ContentMode contentMode;
  final int cid;
  final String bookTitle;
  final String chapterTitle;
  final String cover;
  final int durationSec;
  final int sizeBytes;
  final int cachedAt;

  /// 分P序号（第几章）
  final int page;

  /// 章节标题（不含「第 N 章 · 」前缀）
  ///
  /// 离线时要用缓存索引重建出这一集的章节名，chapterTitle 是拼好的展示串，
  /// 拆不回原始标题，所以单独存一份。
  final String part;

  /// 该集在作品章节列表中的原始序号（**1 起**，0 表示老数据没有这个字段）。
  ///
  /// 缓存页要按「作品原本的顺序」展示，而 _entries 是按缓存先后追加的，
  /// 直接渲染会变成「先缓存的排前面」。用 1 起而不是 0 起，是为了让 0
  /// 能唯一表示「未知」，第一集本身序号是 1 而不是 0。
  final int order;

  const CacheEntry({
    required this.bvid,
    required this.cid,
    required this.bookTitle,
    required this.chapterTitle,
    this.cover = '',
    this.durationSec = 0,
    this.sizeBytes = 0,
    this.cachedAt = 0,
    this.page = 0,
    this.part = '',
    this.order = 0,
    this.contentMode = ContentMode.audiobook,
  });

  String get fileName => '$bvid-$cid.m4a';

  /// 还原成播放器的 Chapter（离线重建章节列表用）
  ///
  /// 老缓存记录没有单独存 part/page（那是后来才加的），只能从展示串
  /// 「2 · 第二季」里拆回来，否则会拼出「第 0 章 · 2 · 第二季」这种鬼东西。
  Chapter toChapter() {
    var p = page;
    var t = part;
    if (t.isEmpty) {
      final s = chapterTitle;
      final i = s.indexOf(' · ');
      if (i > 0) {
        t = s.substring(i + 3).trim();
        if (p <= 0) p = int.tryParse(s.substring(0, i).trim()) ?? 0;
      } else {
        t = s;
      }
    }
    if (p <= 0) p = 1;
    return Chapter(cid: cid, page: p, part: t, duration: durationSec);
  }

  /// 同一本书内的章节排序
  ///
  /// 双方都有原始序号就按序号；只要有一方是老数据（order == 0），
  /// 就整体退回「分P序号 → cid」，避免新老混排时顺序忽前忽后。
  static int compareByOrder(CacheEntry a, CacheEntry b) {
    if (a.order > 0 && b.order > 0) return a.order.compareTo(b.order);
    if (a.page != b.page) return a.page.compareTo(b.page);
    return a.cid.compareTo(b.cid);
  }

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
        'page': page,
        'part': part,
        'order': order,
        'contentMode': contentMode.name,
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
        page: int.tryParse('${m['page'] ?? 0}') ?? 0,
        part: m['part'] as String? ?? '',
        order: int.tryParse('${m['order'] ?? 0}') ?? 0,
        contentMode: ContentMode.fromJson(m['contentMode']),
      );
}

/// 队列中的一项下载任务
class CacheRequest {
  final String bvid;
  final ContentMode contentMode;
  final String bookTitle;
  final String cover;
  final int cid;
  final String chapterTitle;
  final int durationSec;
  final int page;
  final String part;
  final int order;

  const CacheRequest({
    required this.bvid,
    required this.bookTitle,
    required this.cover,
    required this.cid,
    required this.chapterTitle,
    required this.durationSec,
    this.page = 0,
    this.part = '',
    this.order = 0,
    this.contentMode = ContentMode.audiobook,
  });

  Map<String, dynamic> toJson() => {
        'bvid': bvid,
        'bookTitle': bookTitle,
        'cover': cover,
        'cid': cid,
        'chapterTitle': chapterTitle,
        'durationSec': durationSec,
        'page': page,
        'part': part,
        'order': order,
        'contentMode': contentMode.name,
      };

  factory CacheRequest.fromJson(Map<String, dynamic> m) => CacheRequest(
        bvid: m['bvid'] as String? ?? '',
        bookTitle: m['bookTitle'] as String? ?? '',
        cover: m['cover'] as String? ?? '',
        cid: int.tryParse('${m['cid'] ?? 0}') ?? 0,
        chapterTitle: m['chapterTitle'] as String? ?? '',
        durationSec: int.tryParse('${m['durationSec'] ?? 0}') ?? 0,
        page: int.tryParse('${m['page'] ?? 0}') ?? 0,
        part: m['part'] as String? ?? '',
        order: int.tryParse('${m['order'] ?? 0}') ?? 0,
        contentMode: ContentMode.fromJson(m['contentMode']),
      );
}

/// 下载中的任务状态
class CacheTask {
  final String bvid;
  final ContentMode contentMode;
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
    this.contentMode = ContentMode.audiobook,
  });

  String get key => '$bvid-$cid';
}

/// 一集缓存失败后的记录（页面展示 + 一键重试）
///
/// debugPrint 在 release 中仍可能输出，但不能替代用户可见的失败记录。
/// 批量缓存失败时保留这一集及可读原因，便于用户重试。
class CacheFailure {
  final String bvid;
  final ContentMode contentMode;
  final int cid;
  final String bookTitle;
  final String chapterTitle;
  final String reason;
  final int at;
  final int page;
  final String part;
  final int order;
  final String cover;
  final int durationSec;

  const CacheFailure({
    required this.bvid,
    required this.cid,
    required this.bookTitle,
    required this.chapterTitle,
    required this.reason,
    required this.at,
    this.page = 0,
    this.part = '',
    this.order = 0,
    this.cover = '',
    this.durationSec = 0,
    this.contentMode = ContentMode.audiobook,
  });

  Map<String, dynamic> toJson() => {
        'bvid': bvid,
        'cid': cid,
        'bookTitle': bookTitle,
        'chapterTitle': chapterTitle,
        'reason': reason,
        'at': at,
        'page': page,
        'part': part,
        'order': order,
        'contentMode': contentMode.name,
        'cover': cover,
        'durationSec': durationSec,
      };

  factory CacheFailure.fromJson(Map<String, dynamic> m) => CacheFailure(
        bvid: m['bvid'] as String? ?? '',
        cid: int.tryParse('${m['cid'] ?? 0}') ?? 0,
        bookTitle: m['bookTitle'] as String? ?? '',
        chapterTitle: m['chapterTitle'] as String? ?? '',
        reason: m['reason'] as String? ?? '缓存失败',
        at: int.tryParse('${m['at'] ?? 0}') ?? 0,
        page: int.tryParse('${m['page'] ?? 0}') ?? 0,
        part: m['part'] as String? ?? '',
        order: int.tryParse('${m['order'] ?? 0}') ?? 0,
        contentMode: ContentMode.fromJson(m['contentMode']),
        cover: m['cover'] as String? ?? '',
        durationSec: int.tryParse('${m['durationSec'] ?? 0}') ?? 0,
      );
}

/// 缓存相关的一条事件记录
///
/// 将「索引/磁盘/播放器」事件显示给用户；日志在 release 中也可能输出，
/// 因此事件和诊断输出都不能包含凭据或完整音源地址。
class CacheEvent {
  final int at;
  final String text;
  const CacheEvent(this.at, this.text);

  Map<String, dynamic> toJson() => {'at': at, 'text': text};

  factory CacheEvent.fromJson(Map<String, dynamic> m) => CacheEvent(
        int.tryParse('${m['at'] ?? 0}') ?? 0,
        m['text'] as String? ?? '',
      );
}

