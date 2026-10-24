import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../widgets/book_cards.dart';
import '../widgets/shelf_common.dart';

/// 我的书架：与书架同源的独立页面
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final books = context.watch<ShelfStore>().books;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: [
          if (books.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${books.length} 项',
                  style: TextStyle(color: AppTheme.textSub, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
      body: books.isEmpty
          ? const EmptyShelfView(
              icon: Icons.collections_bookmark_outlined,
              showImport: true,
              showMascot: true,
              title: '收藏还是空的',
              subtitle: '听书播放 1 分钟后自动加入；歌曲、演唱会和儿童内容请在详情页手动收藏',
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              gridDelegate: bookGridDelegate(context),
              itemCount: books.length,
              itemBuilder: (context, i) {
                final sb = books[i];
                return BookGridItem(
                  book: sb.book,
                  badge: sb.positionMs > 0
                      ? ShelfProgressBadge(percent: sb.percent)
                      : null,
                  onTap: () => playFromShelf(context, sb),
                  onLongPress: () => confirmRemoveFromShelf(context, sb),
                );
              },
            ),
    );
  }
}
