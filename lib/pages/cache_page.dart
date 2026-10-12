import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/cache_store.dart';
import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../player/book_player.dart';
import '../widgets/book_cover.dart';
import 'player_page.dart';

/// 离线缓存管理：按书分组，点开看已缓存章节，可单个/批量删除、可直接播放
class CachePage extends StatelessWidget {
  const CachePage({super.key});

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
      ..sort((a, b) => grouped[b]!.first.cachedAt
          .compareTo(grouped[a]!.first.cachedAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('离线缓存'),
        actions: [
          if (all.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClearAll(context, cache),
              child: Text(
                '清空',
                style: TextStyle(color: AppTheme.accent, fontSize: 14),
              ),
            ),
        ],
      ),
      body: all.isEmpty && !caching && !showFail
          ? const _CacheEmpty()
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: books.length + 1 + (caching ? 1 : 0) + (showFail ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == 0) return _buildSummary(context, cache, all.length);
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
      BuildContext context, CacheStore cache, List<CacheTask> tasks) {
    final pct = (cache.queueProgress * 100).round();
    final cur = tasks.isEmpty ? null : tasks.first;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
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
                  color: AppTheme.accent,
                  value: cache.queueProgress > 0 ? cache.queueProgress : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '正在后台缓存',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(fontSize: 13, color: AppTheme.accent),
              ),
            ],
          ),
          if (cur != null) ...[
            const SizedBox(height: 8),
            Text(
              cur.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppTheme.textSub),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            () {
              final stat = cache.batchStat;
              if (stat.total > 0) {
                return '本批共 ${stat.total} 集，已完成 ${stat.done} 集'
                    '${stat.failed > 0 ? ' · 失败 ${stat.failed} 集' : ''}'
                    '${cache.queueLength > 0 ? ' · 排队 ${cache.queueLength} 集' : ''}'
                    ' · 可离开本页';
              }
              return '排队 ${cache.queueLength} 集 · 可离开本页';
            }(),
            style: TextStyle(fontSize: 11, color: AppTheme.textHint),
          ),
        ],
      ),
    );
  }

  /// 失败清单：以前失败只写日志（release 包里日志是空实现），
  /// 用户只看到「少了一集」，这里把原因亮出来并支持一键重试。
  Widget _buildFailureCard(
      BuildContext context, CacheStore cache, List<CacheFailure> failures) {
    final player = context.read<BookPlayer>();
    final danger = Theme.of(context).colorScheme.error;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
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
                  '${failures.length} 集缓存失败',
                  style: TextStyle(
                    fontSize: 14,
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
                      content: Text('已重新加入缓存队列（${failures.length} 集）'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Text(
                  '全部重试',
                  style: TextStyle(fontSize: 13, color: AppTheme.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...failures.take(5).map(
                (f) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${f.chapterTitle} · ${f.reason}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                  ),
                ),
              ),
          if (failures.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '还有 ${failures.length - 5} 集失败…',
                style: TextStyle(fontSize: 11, color: AppTheme.textHint),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '通常是网络波动或 B 站限流，稍后重试即可',
            style: TextStyle(fontSize: 11, color: AppTheme.textHint),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.sd_storage_rounded, size: 22, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已缓存 $count 集',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '占用 ${cache.totalSizeText} · 点击书籍查看已缓存章节',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookCard(
      BuildContext context, CacheStore cache, String bvid, List<CacheEntry> list) {
    final first = list.first;
    final size = list.fold<int>(0, (s, e) => s + e.sizeBytes);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showBookChapters(context, cache, bvid, list),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '已缓存 ${list.length} 集',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.accent),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            sizeText(size),
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textHint),
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
  Future<void> _showBookChapters(BuildContext context, CacheStore cache,
      String bvid, List<CacheEntry> initial) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      scrollControlDisabledMaxHeightRatio: 0.85,
      showDragHandle: true,
      builder: (ctx) => _BookChaptersSheet(
        bvid: bvid,
        title: initial.isEmpty ? '' : initial.first.bookTitle,
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
        content: Text('清空全部 ${cache.entries.length} 集离线缓存？此操作不可撤销。',
            style: TextStyle(color: AppTheme.textMain, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('清空', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (ok == true) await cache.clearAll();
  }
}

/// 单本书的已缓存章节弹窗
class _BookChaptersSheet extends StatelessWidget {
  final String bvid;
  final String title;
  const _BookChaptersSheet({required this.bvid, required this.title});

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheStore>();
    final list = cache.entriesOf(bvid);
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
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '已缓存 ${list.length} 集 · ${CachePage.sizeText(size)}',
                        style:
                            TextStyle(fontSize: 12, color: AppTheme.textSub),
                      ),
                    ],
                  ),
                ),
                if (list.isNotEmpty)
                  TextButton(
                    onPressed: () => _confirmDeleteAll(context, cache, list),
                    child: Text('删除全部',
                        style: TextStyle(color: AppTheme.textSub, fontSize: 13)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text('缓存已被清空',
                        style:
                            TextStyle(fontSize: 13, color: AppTheme.textHint)),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final e = list[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.offline_pin_rounded,
                            size: 20, color: AppTheme.accent),
                        title: Text(
                          e.chapterTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: AppTheme.textMain),
                        ),
                        subtitle: Text(
                          [e.durationText, e.sizeText]
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          style:
                              TextStyle(fontSize: 11, color: AppTheme.textHint),
                        ),
                        onTap: () => _playEntry(context, cache, e),
                        trailing: IconButton(
                          tooltip: '删除',
                          icon: Icon(Icons.delete_outline,
                              size: 20, color: AppTheme.textSub),
                          onPressed: () => cache.remove(e.bvid, e.cid),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 直接播放这一集（离线）
  Future<void> _playEntry(
      BuildContext context, CacheStore cache, CacheEntry e) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final player = BookPlayer.instance;
    final book = Book(
      bvid: e.bvid,
      aid: 0,
      title: e.bookTitle,
      pic: e.cover,
    );
    // 从缓存目录反查 cid 对应的章节信息
    final ok = await player.playCachedEntry(e.bvid, e.cid, book);
    navigator.pop();
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('缓存文件已失效，请重新缓存'),
            duration: Duration(seconds: 2)),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute(builder: (_) => const PlayerPage()),
    );
  }

  Future<void> _confirmDeleteAll(
      BuildContext context, CacheStore cache, List<CacheEntry> list) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('删除缓存'),
        content: Text('删除这 ${list.length} 集离线缓存？',
            style: TextStyle(color: AppTheme.textMain, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('删除', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (ok == true) await cache.removeBook(bvid);
  }
}

class _CacheEmpty extends StatelessWidget {
  const _CacheEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_for_offline_outlined,
                size: 52, color: AppTheme.textHint),
            const SizedBox(height: 14),
            Text(
              '还没有缓存任何内容',
              style: TextStyle(fontSize: 14, color: AppTheme.textMain),
            ),
            const SizedBox(height: 6),
            Text(
              '在书籍详情页点每集后面的下载图标，\n或用「批量缓存」一次存下多集，无网也能听',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textSub),
            ),
          ],
        ),
      ),
    );
  }
}