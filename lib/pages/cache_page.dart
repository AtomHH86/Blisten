import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/cache_store.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../player/book_player.dart';
import '../widgets/book_cover.dart';
import 'player_page.dart';

/// 离线缓存管理：按书分组，点开看已缓存章节，可单个/批量删除、可直接播放
class CachePage extends StatelessWidget {
  final bool embedded;
  const CachePage({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheStore>();
    final all = cache.entries;
    final tasks = cache.tasks.where((t) => !t.done && !t.failed).toList();
    final failures = cache.failures;
    final caching = cache.pendingCount > 0;
    final showFail = failures.isNotEmpty;

    // 按书分组（保持最近缓存的顺序）
    final grouped = <String, List<CacheEntry>>{};
    for (final e in all) {
      grouped.putIfAbsent(e.bvid, () => []).add(e);
    }
    final books = grouped.keys.toList()
      ..sort(
        (a, b) =>
            grouped[b]!.first.cachedAt.compareTo(grouped[a]!.first.cachedAt),
      );

    return Scaffold(
      appBar: embedded
          ? null
          : AppBar(
              title: const Text('离线缓存'),
              actions: [
                if (all.isNotEmpty || caching || showFail || cache.clearing)
                  TextButton(
                    onPressed: cache.clearing
                        ? null
                        : () => _confirmClearAll(context, cache),
                    child: Text(
                      cache.clearing ? '清理中…' : '清空',
                      style: TextStyle(
                        color: AppTheme.actionText,
                        fontSize: 16,
                      ),
                    ),
                  ),
              ],
            ),
      body: all.isEmpty && !caching && !showFail
          ? const _CacheEmpty()
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount:
                  books.length + 1 + (caching ? 1 : 0) + (showFail ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Column(
                    children: [
                      if (embedded)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: cache.clearing
                                ? null
                                : () => _confirmClearAll(context, cache),
                            child: const Text('清空'),
                          ),
                        ),
                      _buildSummary(context, cache, all.length),
                    ],
                  );
                }
                var idx = i - 1;
                if (caching && idx == 0) {
                  return _buildProgressCard(context, cache, tasks);
                }
                if (caching) idx--;
                if (showFail && idx == 0) {
                  return _buildFailureCard(context, cache, failures);
                }
                if (showFail) idx--;
                final bvid = books[idx];
                return _buildBookCard(context, cache, bvid, grouped[bvid]!);
              },
            ),
    );
  }

  /// 后台缓存进度卡片
  Widget _buildProgressCard(
    BuildContext context,
    CacheStore cache,
    List<CacheTask> tasks,
  ) {
    final pct = (cache.queueProgress * 100).round();
    final cur = tasks.isEmpty ? null : tasks.first;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.actionText,
                  value: cache.queueProgress > 0 ? cache.queueProgress : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '正在后台缓存',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(fontSize: 14, color: AppTheme.actionText),
              ),
            ],
          ),
          if (cur != null) ...[
            const SizedBox(height: 8),
            Text(
              cur.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: AppTheme.textSub),
            ),
          ],
          const SizedBox(height: 6),
          Text(() {
            final stat = cache.batchStat;
            if (stat.total > 0) {
              return '本批共 ${stat.total} 项，已完成 ${stat.done} 项'
                  '${stat.failed > 0 ? ' · 失败 ${stat.failed} 项' : ''}'
                  '${cache.queueLength > 0 ? ' · 排队 ${cache.queueLength} 项' : ''}'
                  ' · 可离开本页';
            }
            return '排队 ${cache.queueLength} 项 · 可离开本页';
          }(), style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
        ],
      ),
    );
  }

  /// 失败清单：早期失败缺少界面反馈，用户只看到「少了一集」，
  /// 这里把原因亮出来并支持一键重试。
  Widget _buildFailureCard(
    BuildContext context,
    CacheStore cache,
    List<CacheFailure> failures,
  ) {
    final player = context.read<BookPlayer>();
    final danger = Theme.of(context).colorScheme.error;
    // 失败项同样按作品原顺序展示
    final sorted = failures.toList()
      ..sort(
        (a, b) => a.order == b.order
            ? a.cid.compareTo(b.cid)
            : a.order.compareTo(b.order),
      );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 16, color: danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${failures.length} 项缓存失败',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await cache.retryFailed(
                    resolveUrl: (bvid, cid) => player.resolveUrlFor(bvid, cid),
                    headers: player.downloadHeaders,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已重新加入缓存队列（${failures.length} 项）'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Text(
                  '全部重试',
                  style: TextStyle(fontSize: 14, color: AppTheme.actionText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...sorted
              .take(5)
              .map(
                (f) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${f.chapterTitle} · ${f.reason}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: AppTheme.textSub),
                  ),
                ),
              ),
          if (failures.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '还有 ${failures.length - 5} 项失败…',
                style: TextStyle(fontSize: 12, color: AppTheme.textHint),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '通常是网络波动或 B 站限流，稍后重试即可',
            style: TextStyle(fontSize: 12, color: AppTheme.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, CacheStore cache, int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.sd_storage_rounded, size: 22, color: AppTheme.actionText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UsableCacheCount(
                  builder: (count) => Text(
                    count == null ? '正在核验缓存…' : '已缓存 $count 条音频',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '占用 ${cache.totalSizeText} · 点击作品查看已缓存内容',
                  style: TextStyle(fontSize: 14, color: AppTheme.textSub),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookCard(
    BuildContext context,
    CacheStore cache,
    String bvid,
    List<CacheEntry> list,
  ) {
    final first = list.first;
    final size = list.fold<int>(0, (s, e) => s + e.sizeBytes);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showBookChapters(context, cache, bvid, list),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                BookCover(url: first.cover, width: 52, height: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        first.bookTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${context.watch<ShelfStore>().progressByBvid(bvid)?.book.contentMode.label ?? list.first.contentMode.label} · 已缓存 ${list.length} ${context.watch<ShelfStore>().progressByBvid(bvid)?.book.contentMode.unitLabel ?? list.first.contentMode.unitLabel}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.actionText,
                              ),
                            ),
                          ),
                          Text(
                            sizeText(size),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textHint,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 弹窗：这本书已缓存了哪些集，可播放/单删/全删
  Future<void> _showBookChapters(
    BuildContext context,
    CacheStore cache,
    String bvid,
    List<CacheEntry> initial,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      scrollControlDisabledMaxHeightRatio: 0.85,
      showDragHandle: true,
      builder: (ctx) => _BookChaptersSheet(
        bvid: bvid,
        title: initial.isEmpty ? '' : initial.first.bookTitle,
        unitLabel: initial.isEmpty ? '项' : initial.first.contentMode.unitLabel,
      ),
    );
  }

  static String sizeText(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / 1024 / 1024;
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _confirmClearAll(BuildContext context, CacheStore cache) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('清空缓存'),
        content: Text(
          '删除全部 ${cache.entries.length} 项离线缓存，并取消正在下载和排队中的任务？'
          '\n收藏和收听进度会保留。此操作不可撤销。',
          style: TextStyle(color: AppTheme.textMain, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('清空', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await cache.clearAll();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已清空全部缓存和下载任务')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('部分缓存未能清除，请重试')));
    }
  }
}

/// 单本书的已缓存章节弹窗
class _BookChaptersSheet extends StatefulWidget {
  final String bvid;
  final String title;
  final String unitLabel;
  const _BookChaptersSheet({
    required this.bvid,
    required this.title,
    required this.unitLabel,
  });

  @override
  State<_BookChaptersSheet> createState() => _BookChaptersSheetState();
}

class _BookChaptersSheetState extends State<_BookChaptersSheet> {
  bool _opening = false;
  String? _playError;
  String get bvid => widget.bvid;
  String get title => widget.title;
  String get unitLabel =>
      context
          .watch<ShelfStore>()
          .progressByBvid(bvid)
          ?.book
          .contentMode
          .unitLabel ??
      widget.unitLabel;

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheStore>();
    // 按作品原本的章节顺序展示，而不是缓存发生的先后顺序
    final list = cache.entriesOf(bvid)..sort(CacheEntry.compareByOrder);
    final size = list.fold<int>(0, (s, e) => s + e.sizeBytes);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '已缓存 ${list.length} $unitLabel · ${CachePage.sizeText(size)}',
                        style: TextStyle(fontSize: 14, color: AppTheme.textSub),
                      ),
                    ],
                  ),
                ),
                if (list.isNotEmpty)
                  TextButton(
                    onPressed: () => _confirmDeleteAll(context, cache, list),
                    child: Text(
                      '删除全部',
                      style: TextStyle(color: AppTheme.textSub, fontSize: 14),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_opening) const LinearProgressIndicator(),
          if (_playError != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _playError!,
                  style: TextStyle(color: AppTheme.error),
                ),
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      '缓存已被清空',
                      style: TextStyle(fontSize: 14, color: AppTheme.textHint),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final e = list[i];
                      final st = _statusOf(context, e);
                      return ListTile(
                        dense: false,
                        leading: Icon(
                          st.done
                              ? Icons.check_circle_rounded
                              : Icons.offline_pin_rounded,
                          size: 20,
                          color: st.done
                              ? AppTheme.textHint
                              : AppTheme.actionText,
                        ),
                        title: Text(
                          e.chapterTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            color: st.done
                                ? AppTheme.textHint
                                : AppTheme.textMain,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                e.durationText,
                                e.sizeText,
                              ].where((s) => s.isNotEmpty).join(' · '),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textHint,
                              ),
                            ),
                            if (st.text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Row(
                                  children: [
                                    Icon(
                                      st.done
                                          ? Icons.task_alt_rounded
                                          : Icons.timelapse_rounded,
                                      size: 12,
                                      color: st.done
                                          ? AppTheme.success
                                          : AppTheme.textSub,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        st.text,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: st.done
                                              ? AppTheme.success
                                              : AppTheme.textSub,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (!st.done && st.progress > 0)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  right: 8,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: st.progress,
                                    minHeight: 3,
                                    backgroundColor: AppTheme.divider,
                                    color: AppTheme.actionText,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        onTap: _opening
                            ? null
                            : () => _playEntry(context, cache, e),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '重新缓存',
                              icon: Icon(
                                Icons.refresh_rounded,
                                size: 20,
                                color: AppTheme.textSub,
                              ),
                              onPressed: cache.clearing
                                  ? null
                                  : () => _confirmRecache(context, cache, e),
                            ),
                            IconButton(
                              tooltip: '删除',
                              icon: Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: AppTheme.textSub,
                              ),
                              onPressed: cache.clearing
                                  ? null
                                  : () => _confirmDeleteOne(context, cache, e),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 这一集的收听状态：是否听完 / 听到哪了
  ({bool done, String text, double progress}) _statusOf(
    BuildContext context,
    CacheEntry e,
  ) {
    final shelf = context.watch<ShelfStore>().byBvid(e.bvid);
    if (shelf == null) return (done: false, text: '未听', progress: 0);
    // 播放器已标记听完
    if (shelf.doneCids.contains(e.cid)) {
      return (done: true, text: '已听完', progress: 1);
    }
    if (shelf.lastCid == e.cid && shelf.positionMs > 0) {
      // 章节时长优先用进度里记录的，没有就退回缓存时的时长
      final durMs = shelf.chapterDurationMs > 0
          ? shelf.chapterDurationMs
          : e.durationSec * 1000;
      final pos = shelf.positionMs;
      if (durMs <= 0) {
        return (done: false, text: '听到 ${_fmtMs(pos)}', progress: 0);
      }
      final p = (pos / durMs).clamp(0.0, 1.0);
      // 和播放器一致：到 95% 以上就算听完
      if (p >= 0.95) return (done: true, text: '已听完', progress: 1);
      return (
        done: false,
        text: '听到 ${(p * 100).round()}% · ${_fmtMs(pos)} / ${_fmtMs(durMs)}',
        progress: p,
      );
    }
    return (done: false, text: '未听', progress: 0);
  }

  static String _fmtMs(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 删除单集缓存前的二次确认
  Future<void> _confirmRecache(
    BuildContext context,
    CacheStore cache,
    CacheEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新缓存'),
        content: Text(
          '删除「${entry.chapterTitle}」的当前缓存并重新下载？'
          '\n重新下载完成前，这一项将无法离线收听。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('重新缓存'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final player = context.read<BookPlayer>();
    try {
      await cache.recache(
        entry,
        resolveUrl: player.resolveUrlFor,
        headers: player.downloadHeaders,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未能重新缓存，请重试')));
    }
  }

  /// 删除单集缓存前的二次确认
  Future<void> _confirmDeleteOne(
    BuildContext context,
    CacheStore cache,
    CacheEntry e,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          '删除这一${context.read<ShelfStore>().progressByBvid(e.bvid)?.book.contentMode.unitLabel ?? e.contentMode.unitLabel}的缓存',
        ),
        content: Text(
          '「${e.chapterTitle}」${e.sizeText.isEmpty ? '' : '（${e.sizeText}）'}\n'
          '删除后需要重新缓存才能离线收听。',
          style: TextStyle(color: AppTheme.textMain, fontSize: 16, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '删除',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await cache.remove(e.bvid, e.cid);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缓存未能删除，请重试')));
    }
  }

  /// 直接播放这一集（离线）
  Future<void> _playEntry(
    BuildContext context,
    CacheStore cache,
    CacheEntry e,
  ) async {
    final route = ModalRoute.of(context);
    if (_opening || route?.isCurrent != true) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final player = context.read<BookPlayer>();
    final book = Book(
      bvid: e.bvid,
      aid: 0,
      title: e.bookTitle,
      pic: e.cover,
      contentMode:
          context.read<ShelfStore>().progressByBvid(e.bvid)?.book.contentMode ??
          e.contentMode,
    );
    setState(() {
      _opening = true;
      _playError = null;
    });
    try {
      final result = await player.playCachedEntry(e.bvid, e.cid, book);
      if (!mounted || route?.isCurrent != true) return;
      if (result == CachePlayOutcome.fileMissing ||
          result == CachePlayOutcome.failed) {
        setState(
          () => _playError = result == CachePlayOutcome.fileMissing
              ? '缓存文件已丢失，请重新缓存'
              : '播放失败，请检查网络后点选章节重试',
        );
        return;
      }
      // 此时只有请求所属的当前弹层可以关闭，不能 pop 后来打开的页面。
      navigator.pop();
      navigator.push(MaterialPageRoute(builder: (_) => const PlayerPage()));
      if (result == CachePlayOutcome.okOnline) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('离线播放失败，已改为在线播放（缓存仍保留）'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      if (!mounted || route?.isCurrent != true) return;
      setState(() => _playError = '播放失败，请检查网络后点选章节重试');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _confirmDeleteAll(
    BuildContext context,
    CacheStore cache,
    List<CacheEntry> list,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('删除缓存'),
        content: Text(
          '删除这 ${list.length} $unitLabel离线缓存？',
          style: TextStyle(color: AppTheme.textMain, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('删除', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await cache.removeBook(bvid);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('部分缓存未能删除，请重试')));
    }
  }
}

class _CacheEmpty extends StatelessWidget {
  const _CacheEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download_for_offline_outlined,
                size: 52,
                color: AppTheme.textHint,
              ),
              const SizedBox(height: 14),
              Text(
                '还没有缓存任何内容',
                style: TextStyle(fontSize: 16, color: AppTheme.textMain),
              ),
              const SizedBox(height: 6),
              Text(
                '在作品详情页点下载图标，\n或用「批量缓存」保存内容，无网也能听',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTheme.textSub),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 核验真实文件，未知时保留加载态，不将索引数量当成可用音频数量。
class UsableCacheCount extends StatefulWidget {
  final Widget Function(int? count) builder;
  const UsableCacheCount({super.key, required this.builder});
  @override
  State<UsableCacheCount> createState() => _UsableCacheCountState();
}

class _UsableCacheCountState extends State<UsableCacheCount> {
  String? _signature;
  Future<int>? _future;
  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheStore>();
    final entries = cache.entries;
    final active = cache.tasks
        .where((t) => !t.done)
        .map((t) => '${t.bvid}/${t.cid}')
        .toSet();
    active.addAll(cache.failures.map((f) => '${f.bvid}/${f.cid}'));
    final signature =
        '${entries.map((e) => '${e.bvid}/${e.cid}/${e.cachedAt}').join(',')}|${active.join(',')}';
    if (_signature != signature) {
      _signature = signature;
      _future = Future.wait(
        entries.where((e) => !active.contains('${e.bvid}/${e.cid}')).map((
          e,
        ) async {
          try {
            final file = await cache.fileOf(e);
            return await file.exists() && await file.length() > 0;
          } catch (_) {
            return false;
          }
        }),
      ).then((usable) => usable.where((ok) => ok).length);
    }
    return FutureBuilder<int>(
      future: _future,
      builder: (_, snapshot) => widget.builder(
        snapshot.connectionState == ConnectionState.done ? snapshot.data : null,
      ),
    );
  }
}
