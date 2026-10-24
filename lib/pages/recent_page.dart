import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../player/book_player.dart';
import '../widgets/book_cover.dart';
import '../widgets/shelf_common.dart';
import 'book_detail_page.dart';
import 'player_page.dart';

/// 最近收听：按最近收听时间排序的在听列表
class RecentPage extends StatelessWidget {
  const RecentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final shelf = context.watch<ShelfStore>();
    final items = shelf.recentBooks.where((b) => b.hasProgress).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('最近收听')),
      body: items.isEmpty
          ? const EmptyShelfView(
              icon: Icons.headphones_outlined,
              title: '还没有收听记录',
              subtitle: '听书、歌曲、演唱会和儿童内容的本机进度会显示在这里，无需先收藏；仅保留最近记录。',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(
                height: 20,
                thickness: 0.5,
                color: AppTheme.divider,
              ),
              itemBuilder: (context, i) => _RecentTile(
                  key: ValueKey(items[i].book.bvid), sb: items[i]),
            ),
    );
  }
}

class _RecentTile extends StatefulWidget {
  final ShelfBook sb;
  const _RecentTile({super.key, required this.sb});

  @override
  State<_RecentTile> createState() => _RecentTileState();
}

class _RecentTileState extends State<_RecentTile> {
  bool _opening = false;
  int _operationId = 0;
  ShelfBook get sb => widget.sb;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<BookPlayer>();
    final isCurrent = player.book?.bvid == sb.book.bvid &&
        player.book?.contentMode == sb.book.contentMode;
    final chapter = sb.lastChapterIndex + 1;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _opening ? null : () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookDetailPage(bvid: sb.book.bvid, contentMode: sb.book.contentMode),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            BookCover(url: sb.book.pic, width: 56, height: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sb.book.cleanTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '第 $chapter ${sb.book.contentMode.unitLabel} · ${sb.progressText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: sb.percent,
                      minHeight: 4,
                      backgroundColor: AppTheme.surfaceHigh,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppTheme.actionText),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '清除收听记录',
              onPressed: () => _clearRecord(context, player),
              icon: Icon(Icons.delete_outline, color: AppTheme.textSub),
            ),
            IconButton(
              tooltip: !sb.book.contentMode.resumesPosition
                  ? '从头播放'
                  : isCurrent ? '打开播放页' : '继续收听',
              onPressed: _opening ? null : () => _resume(player),
              icon: Icon(
                _opening ? Icons.hourglass_top_rounded : isCurrent && player.isPlaying
                    ? Icons.equalizer_rounded
                    : Icons.play_circle_fill_rounded,
                size: 36,
                color: AppTheme.actionText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearRecord(BuildContext context, BookPlayer player) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除收听记录'),
        content: Text('清除《${sb.book.cleanTitle}》的收听进度和已听标记？'
            '\n如果它正在播放或加载，将停止该作品。收藏和离线缓存会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('清除')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final operationId = ++_operationId;
    final route = ModalRoute.of(context);
    setState(() => _opening = true);
    try {
      await player.clearListeningRecord(sb.book.bvid);
      if (!context.mounted || route?.isCurrent != true) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清除收听记录')));
    } catch (_) {
      if (!context.mounted || route?.isCurrent != true) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('清除失败，请重试')));
    } finally {
      if (mounted && operationId == _operationId) setState(() => _opening = false);
    }
  }

  Future<void> _resume(BookPlayer player) async {
    final route = ModalRoute.of(context);
    if (_opening || route?.isCurrent != true) return;
    final operationId = ++_operationId;
    final target = sb;
    setState(() => _opening = true);
    try {
      final alreadyLoaded = player.book?.bvid == target.book.bvid &&
          player.book?.contentMode == target.book.contentMode &&
          player.loaded && target.book.contentMode.resumesPosition;
      if (!alreadyLoaded) {
        player.flushProgress();
        final ok = await player.resumeShelf(target);
        if (!mounted || operationId != _operationId || route?.isCurrent != true) return;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('播放失败，请检查网络后重试')),
          );
          return;
        }
      }
      if (!mounted || operationId != _operationId || route?.isCurrent != true) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PlayerPage()),
      );
    } catch (_) {
      if (!mounted || operationId != _operationId || route?.isCurrent != true) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('播放失败，请检查网络后重试')),
      );
    } finally {
      if (mounted && operationId == _operationId) setState(() => _opening = false);
    }
  }
}
