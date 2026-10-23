import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../utils/format.dart';
import 'book_cover.dart';

/// 网格为标题和作者预留随系统字体缩放的高度，窄屏降低列数。
SliverGridDelegateWithFixedCrossAxisCount bookGridDelegate(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final scaler = MediaQuery.textScalerOf(context);
  final columns = width < 360 || scaler.scale(14) > 19 ? 2 : 3;
  final tileWidth = (width - 24 - 12 * (columns - 1)) / columns;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisSpacing: 16,
    crossAxisSpacing: 12,
    mainAxisExtent: tileWidth * 1.2 + scaler.scale(14) * 2.6 + scaler.scale(12) * 1.3 + 16,
  );
}

/// 网格卡片：封面 + 书名 + 作者（书架/发现页通用）
class BookGridItem extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? badge;

  const BookGridItem({
    super.key,
    required this.book,
    required this.onTap,
    this.onLongPress,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                BookCover(url: book.pic),
                if (badge != null)
                  Positioned(bottom: 6, right: 6, child: badge!),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.cleanTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:  TextStyle(
              fontSize: 14,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:  TextStyle(fontSize: 12, color: AppTheme.textSub),
          ),
        ],
      ),
    );
  }
}

/// 列表行：横向封面 + 信息（搜索/书架详情列表）
class BookListTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final String? subtitle;
  final String? trailing;

  const BookListTile({
    super.key,
    required this.book,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            BookCover(
              url: book.pic,
              width: MediaQuery.textScalerOf(context).scale(14) > 19 ? 64 : 80,
              height: 64,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.cleanTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:  TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        book.pages > 1
                            ? Icons.library_books_outlined
                            : Icons.menu_book_outlined,
                        size: 14,
                        color: AppTheme.textSub,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          subtitle ?? '${book.pages} ${book.contentMode.unitLabel} · ${book.durationText}',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                        ),
                      ),
                    ],
                  ),
                  if (trailing != null) ...[
                    const SizedBox(height: 4),
                    Text(trailing!, style: TextStyle(fontSize: 12, color: AppTheme.textSub)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 播放量标签（放在封面角落）
class PlayBadge extends StatelessWidget {
  final int play;
  const PlayBadge({super.key, required this.play});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow_rounded, size: 12, color: Colors.white),
          Text(
            Fmt.count(play),
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ],
      ),
    );
  }
}