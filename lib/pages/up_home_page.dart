import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/follow_store.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../models/up_user.dart';
import '../services/bili_api.dart';
import '../services/umeng_analytics.dart';
import '../utils/format.dart';
import '../widgets/book_cover.dart';
import 'book_detail_page.dart';

/// UP 主主页：关注后只听这一个人的有声内容
class UpHomePage extends StatefulWidget {
  final UpUser up;
  const UpHomePage({super.key, required this.up});

  @override
  State<UpHomePage> createState() => _UpHomePageState();
}

class _UpHomePageState extends State<UpHomePage> {
  final _bili = BiliApi.instance;

  List<Book> _books = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 1;
  String? _error;

  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _books = [];
      _page = 1;
      _noMore = false;
    });
    try {
      final list = await _bili.upAudios(widget.up, page: 1, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _books = list;
        _loading = false;
        if (list.length < _pageSize) _noMore = true;
      });
      AppAnalytics.onEvent('up_open', {'count': list.length});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败，请稍后重试';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _noMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final list = await _bili.upAudios(widget.up,
          page: next, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _page = next;
        _books = [..._books, ...list];
        _loadingMore = false;
        if (list.isEmpty || list.length < _pageSize) _noMore = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleFollow() async {
    final store = context.read<FollowStore>();
    final now = await store.toggle(widget.up);
    if (!mounted) return;
    AppAnalytics.onEvent(now ? 'up_follow' : 'up_unfollow');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(now ? '已关注 ${widget.up.name}' : '已取消关注'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final following =
        context.watch<FollowStore>().isFollowing(widget.up.mid);

    return Scaffold(
      appBar: AppBar(title: Text(widget.up.name)),
      body: Column(
        children: [
          _buildHeader(following),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader(bool following) {
    final up = widget.up;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.surfaceHigh,
            backgroundImage: up.face.isNotEmpty
                ? NetworkImage(up.face)
                : null,
            child: up.face.isEmpty
                ? Icon(Icons.person_rounded, size: 30, color: AppTheme.accent)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  up.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (up.fans > 0) '${Fmt.count(up.fans)} 粉丝',
                    if (up.videos > 0) '${up.videos} 投稿',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                ),
                if (up.sign.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    up.sign,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textHint),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _toggleFollow,
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              following ? '已关注' : '+ 关注',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.textHint),
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(fontSize: 13, color: AppTheme.textSub)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_books.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic_off_outlined, size: 48, color: AppTheme.textHint),
              const SizedBox(height: 12),
              Text(
                '没有找到该 UP 主的有声内容',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSub),
              ),
            ],
          ),
        ),
      );
    }

    final shelf = context.watch<ShelfStore>();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _books.length + 1,
      itemBuilder: (context, i) {
        if (i == _books.length) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppTheme.accent),
                ),
              ),
            );
          }
          if (_noMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text('— 没有更多了 —',
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textHint)),
              ),
            );
          }
          return ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: TextButton(
                    onPressed: _loadMore,
                    child: Text('加载更多',
                        style: TextStyle(color: AppTheme.accent)),
                  ),
                ),
              ),
            ],
          );
        }
        final b = _books[i];
        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BookDetailPage(bvid: b.bvid),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                BookCover(url: b.pic, width: 72, height: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        b.cleanTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textMain,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (b.durationText.isNotEmpty) b.durationText,
                          '${Fmt.count(b.play)} 播放',
                          if (shelf.isOnShelf(b.bvid)) '已在书架',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSub),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
              ],
            ),
          ),
        );
      },
    );
  }
}