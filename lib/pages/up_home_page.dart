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

/// UP 主主页：关注 + 只看这一个人的作品（分页上拉加载）
class UpHomePage extends StatefulWidget {
  final UpUser up;
  const UpHomePage({super.key, required this.up});

  @override
  State<UpHomePage> createState() => _UpHomePageState();
}

class _UpHomePageState extends State<UpHomePage> {
  final _bili = BiliApi.instance;
  final _scroll = ScrollController();

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
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
      final list =
          await _bili.upAudios(widget.up, page: 1, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _books = list;
        _loading = false;
        // 合集一次性返回全部；分页路径按整页判断
        _noMore = list.length < _pageSize;
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
      final list =
          await _bili.upAudios(widget.up, page: next, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _page = next;
        final seen = _books.map((b) => b.bvid).toSet();
        _books = [
          ..._books,
          ...list.where((b) => seen.add(b.bvid)),
        ];
        _loadingMore = false;
        if (list.length < _pageSize) _noMore = true;
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      color: AppTheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.surfaceHigh,
            backgroundImage: up.face.isNotEmpty ? NetworkImage(up.face) : null,
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
                // 粉丝/投稿只在有值时显示，避免出现「· ·」这种空信息
                if (up.fans > 0 || up.videos > 0)
                  Text(
                    [
                      if (up.fans > 0) '${Fmt.count(up.fans)} 粉丝',
                      if (up.videos > 0) '${up.videos} 投递稿件',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                  ),
                if (up.sign.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    up.sign,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textHint),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _toggleFollow,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
      return _message(
        icon: Icons.cloud_off_outlined,
        text: _error!,
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (_books.isEmpty) {
      // 明确告诉用户为什么没有内容，以及下一步怎么办
      return _message(
        icon: Icons.mic_off_outlined,
        text: '没能取到「${widget.up.name}」的有声内容\n'
            'B 站对未登录的 UP 空间接口有风控限制，\n可稍后重试或先登录账号再试',
        actionLabel: '重新加载',
        onAction: _load,
      );
    }

    final shelf = context.watch<ShelfStore>();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _books.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Text(
                '作品 ${_books.length} 个${_noMore ? '' : '（上拉加载更多）'}',
                style: TextStyle(fontSize: 12, color: AppTheme.textSub),
              ),
            );
          }
          if (i == _books.length + 1) {
            return _buildFooter();
          }
          final b = _books[i - 1];
          return InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BookDetailPage(bvid: b.bvid),
                ),
              );
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  BookCover(url: b.pic, width: 96, height: 60),
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
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (b.durationText.isNotEmpty)
                              Text(b.durationText,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSub)),
                            if (b.play > 0) ...[
                              const SizedBox(width: 8),
                              Text('${Fmt.count(b.play)} 播放',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textHint)),
                            ],
                            if (shelf.isOnShelf(b.bvid)) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('书架',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.accent)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('— 没有更多了 —',
              style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: TextButton(
          onPressed: _loadMore,
          child: Text('加载更多',
              style: TextStyle(color: AppTheme.accent, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String text,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: AppTheme.textHint),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSub, height: 1.7),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }
}