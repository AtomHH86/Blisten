import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/cache_store.dart';
import '../core/theme/app_theme.dart';
import '../widgets/book_cover.dart';

/// 离线缓存管理：查看已缓存章节、占用空间、删除
class CachePage extends StatelessWidget {
  const CachePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheStore>();
    final all = cache.entries;

    // 按书分组
    final grouped = <String, List<CacheEntry>>{};
    for (final e in all) {
      grouped.putIfAbsent(e.bvid, () => []).add(e);
    }

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
      body: all.isEmpty
          ? Center(
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
                      style:
                          TextStyle(fontSize: 14, color: AppTheme.textMain),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '在播放页点「缓存」选集，下载后无网也能听',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 12, color: AppTheme.textSub),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sd_storage_rounded,
                          size: 22, color: AppTheme.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '已缓存 ${all.length} 集',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textMain,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '占用 ${cache.totalSizeText}',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.textSub),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                for (final entry in grouped.entries)
                  ..._buildBookGroup(context, cache, entry.key, entry.value),
              ],
            ),
    );
  }

  List<Widget> _buildBookGroup(BuildContext context, CacheStore cache,
      String bvid, List<CacheEntry> list) {
    final first = list.first;
    final size = list.fold<int>(0, (s, e) => s + e.sizeBytes);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
        child: Row(
          children: [
            BookCover(url: first.cover, width: 34, height: 34),
            const SizedBox(width: 10),
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
                  Text(
                    '${list.length} 集 · ${_sizeText(size)}',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSub),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '删除这本书的缓存',
              icon: Icon(Icons.delete_outline, size: 20, color: AppTheme.textSub),
              onPressed: () => _confirmRemoveBook(context, cache, first),
            ),
          ],
        ),
      ),
      for (final e in list)
        ListTile(
          dense: true,
          leading: Icon(Icons.check_circle_rounded,
              size: 18, color: AppTheme.accent),
          title: Text(
            e.chapterTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: AppTheme.textMain),
          ),
          subtitle: Text(
            [e.durationText, e.sizeText].where((s) => s.isNotEmpty).join(' · '),
            style: TextStyle(fontSize: 11, color: AppTheme.textHint),
          ),
          trailing: IconButton(
            tooltip: '删除',
            icon: Icon(Icons.close_rounded, size: 18, color: AppTheme.textHint),
            onPressed: () => cache.remove(e.bvid, e.cid),
          ),
        ),
      const Divider(height: 1),
    ];
  }

  static String _sizeText(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / 1024 / 1024;
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _confirmRemoveBook(
      BuildContext context, CacheStore cache, CacheEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('删除缓存'),
        content: Text('删除《${e.bookTitle}》的全部离线缓存？',
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
    if (ok == true) await cache.removeBook(e.bvid);
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