import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/nav/home_tabs.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../models/content_mode.dart';
import '../widgets/book_cards.dart';
import '../widgets/shelf_common.dart';

class FavoritesPage extends StatefulWidget {
  final bool embedded;
  final bool active;
  final ContentMode? mode;
  const FavoritesPage({
    super.key,
    this.embedded = false,
    this.active = true,
    this.mode,
  });
  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<ContentMode>? _order;
  @override
  void didUpdateWidget(FavoritesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _order = null;
  }

  @override
  Widget build(BuildContext context) {
    final books = context.watch<ShelfStore>().books;
    final groups = {
      for (final mode in ContentMode.values)
        mode: books.where((b) => b.book.contentMode == mode).toList(),
    };
    _order ??= ContentMode.values.toList()
      ..sort((a, b) {
        final count = groups[b]!.length.compareTo(groups[a]!.length);
        return count == 0 ? a.index.compareTo(b.index) : count;
      });
    Widget card(ShelfBook sb) => BookGridItem(
      book: sb.book,
      badge: sb.hasProgress ? ShelfProgressBadge(percent: sb.percent) : null,
      onTap: () => playFromShelf(context, sb),
      onLongPress: () => _manage(context, sb),
    );
    final body = books.isEmpty && widget.mode == null
        ? const EmptyShelfView(
            showImport: true,
            showMascot: true,
            title: '收藏还是空的',
            subtitle: '在详情页点击收藏，把喜欢的内容放在这里',
          )
        : widget.mode != null && groups[widget.mode]!.isNotEmpty
        ? GridView.builder(
            key: PageStorageKey('favorites-${widget.mode!.name}'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            gridDelegate: bookGridDelegate(context),
            itemCount: groups[widget.mode]!.length,
            itemBuilder: (_, i) => card(groups[widget.mode]![i]),
          )
        : ListView(
            key: PageStorageKey('favorites-${widget.mode?.name ?? 'all'}'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              for (final mode
                  in widget.mode == null ? _order! : [widget.mode!]) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${mode.label} · ${groups[mode]!.length} 项收藏',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMain,
                          ),
                        ),
                      ),
                      if (groups[mode]!.isNotEmpty && widget.mode == null)
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FavoritesPage(mode: mode),
                            ),
                          ),
                          child: const Text('查看全部'),
                        ),
                    ],
                  ),
                ),
                if (groups[mode]!.isEmpty)
                  Row(
                    children: [
                      const Expanded(child: Text('还没有收藏')),
                      TextButton(
                        onPressed: () => _discover(context, mode),
                        child: Text('去发现${mode.label}'),
                      ),
                    ],
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: bookGridDelegate(context),
                    itemCount: widget.mode == null
                        ? groups[mode]!.length.clamp(0, 6)
                        : groups[mode]!.length,
                    itemBuilder: (_, i) => card(groups[mode]![i]),
                  ),
              ],
            ],
          );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(
              title: Text(
                widget.mode == null ? '我的收藏' : '${widget.mode!.label}收藏',
              ),
            ),
            body: body,
          );
  }

  void _discover(BuildContext context, ContentMode mode) {
    if (!widget.embedded && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    HomeTabs.openDiscover(mode);
  }

  Future<void> _manage(BuildContext context, ShelfBook book) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('移动到其他频道'),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            ListTile(
              title: const Text('移出收藏'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'remove') {
      await confirmRemoveFromShelf(context, book);
      return;
    }
    if (choice != 'move') return;
    final target = await showDialog<ContentMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('移动到其他频道'),
        children: [
          for (final mode in ContentMode.values.where(
            (m) => m != book.book.contentMode,
          ))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, mode),
              child: Text(
                '${mode.label}：${mode.resumesPosition ? '再次选择时断点续播' : '再次选择时从头播放'}',
              ),
            ),
        ],
      ),
    );
    if (target == null || !context.mounted) return;
    await context.read<ShelfStore>().moveToMode(book.book.bvid, target);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已移到${target.label}，进度、已听状态与缓存保留；当前播放不变')),
      );
    }
  }
}
