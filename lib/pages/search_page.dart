import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/follow_store.dart';
import '../core/storage/search_history_store.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../data/seed_books.dart';
import '../models/book.dart';
import '../models/content_mode.dart';
import '../models/up_user.dart';
import '../services/bili_api.dart';
import '../services/umeng_analytics.dart';
import '../utils/format.dart';
import '../widgets/book_cards.dart';
import '../widgets/resource_import_dialog.dart';
import 'book_detail_page.dart';
import 'up_home_page.dart';

/// 独立搜索页：上拉加载下一页；未搜索时展示历史 + 热门
class SearchPage extends StatefulWidget {
  final String? initialKeyword;
  final bool autofocus;
  final ContentMode initialMode;
  final BiliApi? api;
  const SearchPage({super.key, this.initialKeyword, this.autofocus = false,
    this.initialMode = ContentMode.audiobook, this.api});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final _bili = widget.api ?? BiliApi.instance;
  late ContentMode _mode = widget.initialMode;
  int _requestId = 0;
  CancelToken? _cancelToken;
  String _searchedKeyword = '';

  /// UP 主是独立搜索分类；_mode 保留最近选择的内容模式。
  bool _searchUsers = false;

  List<Book> _results = [];
  List<UpUser> _ups = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _moreFailed = false;
  bool _noMore = false;
  String? _error;

  int _page = 1;
  int _total = 0;
  static const int _pageSize = 20;
  bool _hasSearched = false;

  final _scrollController = ScrollController();
  bool _showTopButton = false;
  static const double _topButtonThreshold = 560;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
    if (widget.initialKeyword != null && widget.initialKeyword!.isNotEmpty) {
      _controller.text = widget.initialKeyword!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _scrollController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      final beyond = pos.pixels > _topButtonThreshold;
      if (beyond != _showTopButton) {
        setState(() => _showTopButton = beyond);
      }
      if (pos.pixels >= pos.maxScrollExtent - 200) _loadMore();
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _search({bool recordHistory = true}) async {
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    final requestId = ++_requestId;
    _cancelToken?.cancel();
    final cancelToken = _cancelToken = CancelToken();
    final mode = _mode;
    final searchUsers = _searchUsers;
    FocusScope.of(context).unfocus();
    if (recordHistory) context.read<SearchHistoryStore>().add(kw);
    setState(() {
      _searchedKeyword = kw;
      _loading = true;
      _loadingMore = false;
      _moreFailed = false;
      _error = null;
      _results = [];
      _ups = [];
      _page = 1;
      _total = 0;
      _noMore = false;
      _hasSearched = true;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    try {
      var rawCount = _pageSize;
      var total = 0;
      final ups = searchUsers
          ? await _bili.searchUser(kw, cancelToken: cancelToken, pageSize: _pageSize)
          : <UpUser>[];
      final books = !searchUsers
          ? await _bili.search(
              kw,
              cancelToken: cancelToken,
              mode: mode,
              pageSize: _pageSize,
              onFirstPage: (t) => total = t,
              onRawCount: (c) => rawCount = c,
            )
          : <Book>[];
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _ups = ups;
        _results = books;
        _total = total;
        _loading = false;
        // 听书过滤后可能不足一页，分页以原始条数为准。
        _noMore = searchUsers ? ups.length < _pageSize : rawCount < _pageSize;
      });
      AppAnalytics.onEvent(searchUsers ? 'search_up' : 'search',
          {'has_result': (searchUsers ? ups.isNotEmpty : books.isNotEmpty) ? 1 : 0});
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = '搜索失败，请稍后重试';
      });
    }
  }

  void _selectCategory(ContentMode? mode) {
    final searchUsers = mode == null;
    if (_searchUsers == searchUsers && (searchUsers || _mode == mode)) return;
    setState(() {
      _searchUsers = searchUsers;
      if (mode != null) _mode = mode;
    });
    if (_hasSearched && _controller.text.trim().isNotEmpty) {
      _search(recordHistory: false);
    } else if (_controller.text.trim().isEmpty) {
      _clearSearch();
    }
  }

  /// 上拉分页保留首次请求的关键词与模式，切换后的旧响应不追加。
  Future<void> _loadMore({bool retry = false}) async {
    final kw = _searchedKeyword;
    if (kw.isEmpty || _loading || _loadingMore || _noMore || (_moreFailed && !retry)) return;
    if (!_searchUsers && _total > 0 && _page * _pageSize >= _total) {
      setState(() => _noMore = true);
      return;
    }
    final requestId = _requestId;
    final mode = _mode;
    final searchUsers = _searchUsers;
    final nextPage = _page + 1;
    final cancelToken = _cancelToken;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      var rawCount = _pageSize;
      final ups = searchUsers
          ? await _bili.searchUser(kw, cancelToken: cancelToken, page: nextPage, pageSize: _pageSize)
          : <UpUser>[];
      final books = !searchUsers
          ? await _bili.search(
              kw,
              cancelToken: cancelToken,
              mode: mode,
              page: nextPage,
              pageSize: _pageSize,
              onRawCount: (c) => rawCount = c,
            )
          : <Book>[];
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _page = nextPage;
        if (searchUsers) {
          final seen = _ups.map((up) => up.mid).toSet();
          _ups = [..._ups, ...ups.where((up) => seen.add(up.mid))];
        } else {
          final seen = _results.map((b) => b.bvid).toSet();
          _results = [..._results, ...books.where((b) => seen.add(b.bvid))];
        }
        _loadingMore = false;
        _noMore = searchUsers ? ups.length < _pageSize : rawCount < _pageSize;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
    }
  }

  void _clearSearch() {
    ++_requestId;
    _cancelToken?.cancel();
    _controller.clear();
    setState(() {
      _hasSearched = false;
      _loading = false;
      _loadingMore = false;
      _moreFailed = false;
      _error = null;
      _results = [];
      _ups = [];
      _searchedKeyword = '';
    });
  }

  void _searchWith(String kw) {
    _controller.text = kw;
    _search();
  }

  /// 清空历史前弹窗确认
  Future<void> _confirmClearHistory(
      BuildContext context, SearchHistoryStore history) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空搜索历史'),
        content: const Text('确定要清空全部搜索历史吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentViolet,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) await history.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: '添加 B 站资源',
            onPressed: () => showResourceImportDialog(context, initialMode: _mode),
            icon: const Icon(Icons.add_link_rounded),
          ),
          IconButton(
            tooltip: '返回上一页',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded,
                color: AppTheme.textSub),
          ),
        ],
      ),
      floatingActionButton: _showTopButton
          ? FloatingActionButton.small(
              tooltip: '返回顶部',
              heroTag: 'search-top',
              onPressed: _scrollToTop,
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.onPrimary,
              child: const Icon(Icons.arrow_upward_rounded),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.outline),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: AppTheme.surface,
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 15, color: AppTheme.textMain),
                  decoration: InputDecoration(
                    hintText: _searchUsers ? '搜索 UP 主名称' : switch (_mode) {
                      ContentMode.audiobook => '搜索书名 / 作者 / 主播',
                      ContentMode.music => '搜索歌名 / 歌手',
                      ContentMode.concert => '搜索演唱会 / 歌手',
                      ContentMode.children => '搜索儿歌 / 动画 / 故事',
                    },
                    hintStyle: TextStyle(
                        fontSize: 14, color: AppTheme.textHint),
                    prefixIcon: Icon(Icons.manage_search_rounded,
                        color: AppTheme.actionText),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空搜索',
                            icon: Icon(Icons.cancel_rounded,
                                color: AppTheme.textHint, size: 18),
                            onPressed: _clearSearch,
                          ),
                    // 输入框沿用外层清晰边界，避免叠加两层描边
                    filled: false,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final mode in ContentMode.values)
                  ChoiceChip(
                    key: ValueKey('search-category-${mode.name}'),
                    label: Text(mode.label),
                    selected: !_searchUsers && _mode == mode,
                    onSelected: (_) => _selectCategory(mode),
                  ),
                ChoiceChip(
                  key: const ValueKey('search-category-up'),
                  label: const Text('UP 主'),
                  selected: _searchUsers,
                  onSelected: (_) => _selectCategory(null),
                ),
              ],
            ),
          ),
          if (!_searchUsers && _mode == ContentMode.children &&
              MediaQuery.viewInsetsOf(context).bottom == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('儿歌、动画、故事 · 仅收听声音',
                style: TextStyle(fontSize: 12, color: AppTheme.textSub)),
            ),
          Expanded(child: _buildBody()),
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
      return _ErrorState(
        icon: Icons.cloud_off_outlined,
        message: _error!,
        onTap: _hasSearched ? _search : null,
      );
    }
    if (!_hasSearched) {
      return _buildSuggest();
    }
    if (_searchUsers) {
      if (_ups.isEmpty) {
        return _ErrorState(
          icon: Icons.person_search_outlined,
          message: '没有找到「$_searchedKeyword」相关的 UP 主',
        );
      }
      return _buildUpList();
    }
    if (_results.isEmpty) {
      return _ErrorState(
        icon: Icons.search_off_rounded,
        message: '没有找到「$_searchedKeyword」相关内容',
      );
    }
    final shelf = context.watch<ShelfStore>();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: _results.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) return _buildResultsHeader();
        if (i == _results.length + 1) return _buildFooter();
        final b = _results[i - 1];
        return BookListTile(
          book: b,
          subtitle: [
            if (b.pages > 1) '${b.pages} ${b.contentMode.unitLabel}',
            if (b.durationText.isNotEmpty) b.durationText,
            '${Fmt.count(b.play)} 播放',
          ].join(' · '),
          trailing: shelf.isOnShelf(b.bvid) ? '已收藏' : null,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BookDetailPage(bvid: b.bvid, contentMode: b.contentMode, api: _bili),
              ),
            );
          },
        );
      },
    );
  }

  /// UP 主搜索结果：关注后可直接只看这一个人的内容
  Widget _buildUpList() {
    final follows = context.watch<FollowStore>();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: _ups.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) return _buildResultsHeader();
        if (i == _ups.length + 1) return _buildFooter();
        final up = _ups[i - 1];
        final following = follows.isFollowing(up.mid);
        return ListTile(
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.surfaceHigh,
            backgroundImage:
                up.face.isNotEmpty ? NetworkImage(up.face) : null,
            child: up.face.isEmpty
                ? Icon(Icons.person, color: AppTheme.actionText)
                : null,
          ),
          title: Text(
            up.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMain,
            ),
          ),
          subtitle: Text(
            [
              if (up.fans > 0) '${Fmt.count(up.fans)} 粉丝',
              if (up.sign.isNotEmpty) up.sign,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: AppTheme.textSub),
          ),
          trailing: FilledButton.tonal(
            onPressed: () => follows.toggle(up.withContentMode(_mode)),
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              following ? '已关注' : '关注',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => UpHomePage(up: up, contentMode: _mode, api: _bili)),
            );
          },
        );
      },
    );
  }

  /// 结果列表的顶部提示条：当前关键词
  Widget _buildResultsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Icon(Icons.manage_search_rounded,
              size: 15, color: AppTheme.actionText),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13, color: AppTheme.textSub),
                children: [
                  const TextSpan(text: '“'),
                  TextSpan(
                    text: _searchedKeyword,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.actionText,
                    ),
                  ),
                  const TextSpan(text: '” 的搜索结果'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 列表尾部：失败重试 / 加载中 / 到底了
  Widget _buildFooter() {
    if (_moreFailed) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Text('加载更多失败', style: TextStyle(color: AppTheme.textSub)),
          TextButton(
            onPressed: () => _loadMore(retry: true),
            child: const Text('重试'),
          ),
        ]),
      );
    }
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
          child: Text(
            '— 已经到底啦 —',
            style: TextStyle(fontSize: 12, color: AppTheme.textHint),
          ),
        ),
      );
    }
    return const SizedBox(height: 12);
  }

  /// 未搜索时的建议区：搜索历史 + 热门搜索
  Widget _buildSuggest() {
    final history = context.watch<SearchHistoryStore>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (history.items.isNotEmpty) ...[
          _SectionHeader(
            title: '搜索历史',
            icon: Icons.history_rounded,
            trailing: IconButton(
              tooltip: '清空历史',
              onPressed: () => _confirmClearHistory(context, history),
              icon: Icon(Icons.delete_sweep_outlined,
                  color: AppTheme.textSub, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: history.items
                .map((k) => _KeywordChip(
                      label: k,
                      onTap: () => _searchWith(k),
                      onDelete: () => history.remove(k),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
        ],
        if (!_searchUsers) ...[
          _SectionHeader(
            title: '热门搜索',
            icon: Icons.local_fire_department_rounded,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: DiscoverSeeds.hotKeysFor(_mode)
                .asMap()
                .entries
                .map(
                  (e) => _RankChip(
                    rank: e.key + 1,
                    label: e.value,
                    onTap: () => _searchWith(e.value),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 32),
        Center(
          child: Column(
            children: [
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: [AppTheme.accentSoft, AppTheme.accentLilac],
                ).createShader(rect),
                child: Icon(
                  _searchUsers ? Icons.person_search_rounded : Icons.auto_stories_rounded,
                  size: 40,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _searchUsers ? '输入 UP 主名称，找到想听的创作者' : '发现 · 收听 · 一路在听',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.textHint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 建议区小标题
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.actionText),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMain,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// 关键词胶囊：历史条目带删除钮
class _KeywordChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _KeywordChip({
    required this.label,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.only(
          left: 14,
          right: onDelete == null ? 14 : 6,
          top: 8,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          color: AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.divider, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(
              label,
              style: TextStyle(fontSize: 13, color: AppTheme.textMain),
            )),
            if (onDelete != null)
              IconButton(
                tooltip: '删除搜索历史：$label',
                onPressed: onDelete,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(Icons.close_rounded,
                    size: 18, color: AppTheme.textHint),
              ),
          ],
        ),
      ),
    );
  }
}

/// 热门关键词：前置排名角标，前 3 名高亮
class _RankChip extends StatelessWidget {
  final int rank;
  final String label;
  final VoidCallback onTap;

  const _RankChip({
    required this.rank,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final top = rank <= 3;
    final rankColor = switch (rank) {
      1 => AppTheme.actionText,
      2 => AppTheme.actionText,
      3 => AppTheme.actionText,
      _ => AppTheme.textHint,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: top ? AppTheme.accent.withValues(alpha: 0.08) : AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: top ? rankColor.withValues(alpha: 0.45) : AppTheme.divider,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              padding: const EdgeInsets.all(3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: top ? rankColor : AppTheme.divider,
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: top ? AppTheme.bg : AppTheme.textSub,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: top ? FontWeight.w600 : FontWeight.w400,
                color: AppTheme.textMain,
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onTap;

  const _ErrorState({
    required this.icon,
    required this.message,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppTheme.textHint),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textSub),
          ),
          if (onTap != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onTap, child: const Text('重试')),
          ],
        ],
        ),
      ),
    );
  }
}