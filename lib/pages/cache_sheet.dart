import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/cache_store.dart';
import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../player/book_player.dart';
import '../services/umeng_analytics.dart';

/// 缓存选集：勾选章节后批量下载，下载完可离线播放
///
/// 两种入口：
/// - 播放页：传入 [book]（当前书）与预选章节
/// - 详情页：同样传入 [book]，章节取自详情数据
class CacheSheet extends StatefulWidget {
  final Book? book;
  final int? preselectIndex;
  const CacheSheet({super.key, this.book, this.preselectIndex});

  static Future<void> show(BuildContext context,
      {Book? book, int? preselectIndex}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      scrollControlDisabledMaxHeightRatio: 0.9,
      showDragHandle: true,
      builder: (_) => CacheSheet(
          book: book, preselectIndex: preselectIndex),
    );
  }

  @override
  State<CacheSheet> createState() => _CacheSheetState();
}

class _CacheSheetState extends State<CacheSheet> {
  final Set<int> _selected = {};
  bool _running = false;
  bool _initDone = false;

  Book? get _book => widget.book ?? context.read<BookPlayer>().book;

  List<Chapter> get _chapters {
    final explicit = widget.book?.chapters;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return context.read<BookPlayer>().chapters;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _initDone = true;
      });
    });
  }

  /// 缓存选中章节（不依赖播放器的当前状态，直接用列表里的书与章节）
  Future<void> _start() async {
    if (_running || _selected.isEmpty) return;
    final book = _book;
    final chapters = _chapters;
    if (book == null || chapters.isEmpty) return;

    final list = _selected.toList()..sort();
    setState(() => _running = true);
    AppAnalytics.onEvent('cache_start', {'count': list.length});

    final cache = context.read<CacheStore>();
    final player = context.read<BookPlayer>();
    final headers = player.downloadHeaders;

    int ok = 0;
    for (final i in list) {
      if (!mounted) return;
      if (i < 0 || i >= chapters.length) continue;
      final c = chapters[i];
      if (cache.isCached(book.bvid, c.cid)) {
        ok++;
        continue;
      }
      final url = await player.resolveUrlFor(book.bvid, c.cid);
      if (url == null) {
        if (mounted) setState(() {});
        continue;
      }
      final done = await cache.download(
        bvid: book.bvid,
        cid: c.cid,
        url: url,
        bookTitle: book.cleanTitle,
        chapterTitle: '${c.page} · ${c.part}',
        cover: book.pic,
        durationSec: c.duration,
        headers: headers,
      );
      if (done) ok++;
      // 逐个下载，及时刷新进度
      if (mounted) setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    if (!mounted) return;
    setState(() => _running = false);
    final total = list.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok == total
            ? '已缓存 $ok 集，可离线收听'
            : '缓存完成 $ok/$total 集，部分失败请检查网络'),
        duration: const Duration(seconds: 2),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheStore>();
    final book = _book;
    final chapters = _chapters;

    if (!_initDone || chapters.isEmpty || book == null) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      );
    }

    final bvid = book.bvid;

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
              '${book.cleanTitle} · 共 ${chapters.length} 集\n'
              '已缓存 ${cache.countOf(bvid)} 集 · 占用 ${cache.totalSizeText}',
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
                final cached = cache.isCached(bvid, c.cid);
                final task = cache.taskOf(bvid, c.cid);
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