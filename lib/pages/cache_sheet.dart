import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/cache_store.dart';
import '../core/theme/app_theme.dart';
import '../player/book_player.dart';
import '../services/umeng_analytics.dart';

/// 缓存选集：勾选章节后批量下载，下载完可离线播放
class CacheSheet extends StatefulWidget {
  /// 仅做「播放页缓存」时传入，用于预选当前章节
  final int? preselectIndex;
  const CacheSheet({super.key, this.preselectIndex});

  static Future<void> show(BuildContext context, {int? preselectIndex}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      scrollControlDisabledMaxHeightRatio: 0.9,
      showDragHandle: true,
      builder: (_) => CacheSheet(preselectIndex: preselectIndex),
    );
  }

  @override
  State<CacheSheet> createState() => _CacheSheetState();
}

class _CacheSheetState extends State<CacheSheet> {
  final Set<int> _selected = {};
  bool _running = false;
  bool _initDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        final p = context.read<BookPlayer>();
        final i = widget.preselectIndex ?? p.index;
        if (i >= 0 && i < p.chapters.length) _selected.add(i);
        _initDone = true;
      });
    });
  }

  Future<void> _start() async {
    if (_running || _selected.isEmpty) return;
    final player = context.read<BookPlayer>();
    final chapters = player.chapters;
    final list = _selected.toList()..sort();
    setState(() => _running = true);
    AppAnalytics.onEvent('cache_start', {'count': list.length});

    int ok = 0;
    for (final i in list) {
      if (i < 0 || i >= chapters.length) continue;
      final done = await player.cacheChapter(chapters[i]);
      if (done) ok++;
      // 逐个下载，及时刷新进度
      if (mounted) setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    if (!mounted) return;
    setState(() => _running = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok == list.length
            ? '已缓存 $ok 集，可离线收听'
            : '缓存完成 $ok/${list.length} 集，部分失败请检查网络'),
        duration: const Duration(seconds: 2),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<BookPlayer>();
    final cache = context.watch<CacheStore>();
    final chapters = player.chapters;

    if (!_initDone || chapters.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      );
    }

    final running = _running;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                Icon(Icons.download_for_offline_outlined,
                    size: 20, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text(
                  '缓存选集',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: running
                      ? null
                      : () {
                          setState(() {
                            if (_selected.length == chapters.length) {
                              _selected.clear();
                            } else {
                              _selected
                                ..clear()
                                ..addAll(List.generate(chapters.length, (i) => i));
                            }
                          });
                        },
                  child: Text(
                    _selected.length == chapters.length ? '取消全选' : '全选',
                    style: TextStyle(
                      fontSize: 13,
                      color: running ? AppTheme.textHint : AppTheme.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '已缓存 ${cache.countOf(player.book?.bvid ?? '')} 集 · '
              '共占用 ${cache.totalSizeText}',
              style: TextStyle(fontSize: 12, color: AppTheme.textSub),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: chapters.length,
              itemBuilder: (context, i) {
                final c = chapters[i];
                final cached = cache.isCached(player.book?.bvid ?? '', c.cid);
                final task = cache.taskOf(player.book?.bvid ?? '', c.cid);
                final busy = task != null && !task.done && !task.failed;
                return CheckboxListTile(
                  value: _selected.contains(i),
                  onChanged: running
                      ? null
                      : (v) => setState(() {
                            if (v == true) {
                              _selected.add(i);
                            } else {
                              _selected.remove(i);
                            }
                          }),
                  dense: true,
                  title: Text(
                    '${c.page} · ${c.part}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: cached ? AppTheme.textHint : AppTheme.textMain,
                    ),
                  ),
                  subtitle: Text(
                    busy
                        ? '下载中 ${(task.progress * 100).round()}%'
                        : cached
                            ? '已缓存'
                            : c.durationText,
                    style: TextStyle(
                      fontSize: 12,
                      color: busy || cached ? AppTheme.accent : AppTheme.textSub,
                    ),
                  ),
                  secondary: cached && !busy
                      ? Icon(Icons.offline_pin_rounded,
                          size: 20, color: AppTheme.accent)
                      : null,
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (running || _selected.isEmpty) ? null : _start,
                  icon: running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    running
                        ? '正在缓存…'
                        : '缓存选中的 ${_selected.length} 集',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}