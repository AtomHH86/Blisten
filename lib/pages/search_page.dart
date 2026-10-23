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
  String _searchedKeyword = '';

  /// 0 = 当前模式视频，1 = UP 主
  int _tab = 0;

  List<Book> _results = [];
  List<UpUser> _ups = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _noMore = false;
  String? _error;

  int _page = 1;
  int _total = 0;
  static const int _pageSize = 20;
  bool _hasSearched = false;
  bool _switching = false;
  int? _pendingTab;

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
    final mode = _mode;
    final tab = _tab;
    FocusScope.of(context).unfocus();
    if (recordHistory) context.read<SearchHistoryStore>().add(kw);
    setState(() {
      _searchedKeyword = kw;
      _loading = true;
      _loadingMore = false;
      _switching = false;
      _pendingTab = null;
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
      final ups = tab == 1
          ? await _bili.searchUser(kw, pageSize: _pageSize)
          : <UpUser>[];
      final books = tab == 0
          ? await _bili.search(
              kw,
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
        _noMore = tab == 1 ? ups.length < _pageSize : rawCount < _pageSize;
      });
      AppAnalytics.onEvent(tab == 1 ? 'search_up' : 'search',
          {'has_result': (tab == 1 ? ups.isNotEmpty : books.isNotEmpty) ? 1 : 0});
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = '搜索失败，请稍后重试';
      });
    }
  }

  void _switchMode(ContentMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    if (_hasSearched) {
      if (_controller.text.trim().isNotEmpty) {
        _search(recordHistory: false);
      } else {
        _clearSearch();
      }
    }
  }

  /// 先加载目标标签，再一起替换列表与标签，保持原来的无闪屏切换。
  Future<void> _switchTab(int tab) async {
    if (_pendingTab == tab || _tab == tab) return;
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    final requestId = ++_requestId;
    final mode = _mode;
    setState(() {
      _switching = true;
      _pendingTab = tab;
      _loadingMore = false;
    });
    try {
      var rawCount = _pageSize;
      var total = 0;
      final ups = tab == 1
          ? await _bili.searchUser(kw, pageSize: _pageSize)
          : <UpUser>[];
      final books = tab == 0
          ? await _bili.search(kw, mode: mode, pageSize: _pageSize,
              onFirstPage: (t) => total = t,
              onRawCount: (c) => rawCount = c)
          : <Book>[];
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _tab = tab;
        _results = books;
        _ups = ups;
        _searchedKeyword = kw;
        _page = 1;
        _total = total;
        _error = null;
        _loading = false;
        _switching = false;
        _pendingTab = null;
        _noMore = tab == 1 ? ups.length < _pageSize : rawCount < _pageSize;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _switching = false;
        _pendingTab = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载失败，请稍后重试')),
      );
    }
  }

  /// 上拉分页保留首次请求的关键词与模式，切换后的旧响应不追加。
  Future<void> _loadMore() async {
    final kw = _searchedKeyword;
    if (kw.isEmpty || _loading || _loadingMore || _switching || _noMore || _tab == 1) return;
    if (_total > 0 && _page * _pageSize >= _total) {
      setState(() => _noMore = true);
      return;
    }
    final requestId = _requestId;
    final mode = _mode;
    final nextPage = _page + 1;
    setState(() => _loadingMore = true);
    try {
      var rawCount = _pageSize;
      final list = await _bili.search(
        kw,
        mode: mode,
        page: nextPage,
        pageSize: _pageSize,
        onRawCount: (c) => rawCount = c,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _page = nextPage;
        final seen = _results.map((b) => b.bvid).toSet();
        _results = [..._results, ...list.where((b) => seen.add(b.bvid))];
        _loadingMore = false;
        _noMore = rawCount < _pageSize;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('加载更多失败，上滑重试'),
          duration: const Duration(seconds: 1),
          action: SnackBarAction(label: '重试', onPressed: _loadMore),
        ),
      );
    }
  }

  void _clearSearch() {
    ++_requestId;
    _controller.clear();
    setState(() {
      _hasSearched = false;
      _switching = false;
      _pendingTab = null;
      _loading = false;
      _loadingMore = false;
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
            tooltip: '回到发现页',
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
              foregroundColor: Colors.white,
              child: const Icon(Icons.arrow_upward_rounded),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Container(
              height: 50,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: AppTheme.accentGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.22),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
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
                    hintText: switch (_mode) {
                      ContentMode.audiobook => '搜索书名 / 作者 / 主播',
                      ContentMode.music => '搜索歌名 / 歌手 / UP 主',
                      ContentMode.concert => '搜索演唱会 / 歌手 / UP 主',
                    },
                    hintStyle: TextStyle(
                        fontSize: 14, color: AppTheme.textHint),
                    prefixIcon: Icon(Icons.manage_search_rounded,
                        color: AppTheme.accent),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(Icons.cancel_rounded,
                                color: AppTheme.textHint, size: 18),
                            onPressed: _clearSearch,
                          ),
                    // 关闭主题自带的浅色填充与边框，内层只承接渐变描边
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
            child: Row(
              children: ContentMode.values.map((mode) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Text(mode.label),
                    selected: _mode == mode,
                    onSelected: (_) => _switchMode(mode),
                  ),
                ),
              )).toList(),
            ),
          ),
          // 搜索框在上、切换在下；搜索出结果后才出现
          if (_hasSearched) _buildTabs(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 听书 / UP主 切换（搜索框下方，搜索后才出现）
  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider, width: 0.5),
              ),
              child: Row(
                children: List.generate(2, (i) {
                  final active = _tab == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _switchTab(i),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              active ? AppTheme.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          i == 0 ? '${_mode.label}结果' : 'UP主',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w400,
                            color:
                                active ? Colors.white : AppTheme.textSub,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          if (_switching)
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent)),
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
      return _ErrorState(
        icon: Icons.cloud_off_outlined,
        message: _error!,
        onTap: _hasSearched ? _search : null,
      );
    }
    if (!_hasSearched) {
      return _buildSuggest();
    }
    if (_tab == 1) {
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
                ? Icon(Icons.person, color: AppTheme.accent)
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
            onPressed: () => follows.toggle(up),
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 30),
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
              size: 15, color: AppTheme.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13, color: AppTheme.textSub),
                children: [
                  const TextSpan(text: '“'),
                  TextSpan(
                    text: _searchedKeyword,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent,
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

  /// 列表尾部：加载中 / 到底了
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
        const SizedBox(height: 32),
        Center(
          child: Column(
            children: [
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: [AppTheme.accentSoft, AppTheme.accentLilac],
                ).createShader(rect),
                child: const Icon(Icons.auto_stories_rounded, size: 40),
              ),
              const SizedBox(height: 6),
              Text(
                '发现 · 收听 · 一路在听',
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
        Icon(icon, size: 18, color: AppTheme.accent),
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
            Text(
              label,
              style: TextStyle(fontSize: 13, color: AppTheme.textMain),
            ),
            if (onDelete != null)
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded,
                      size: 14, color: AppTheme.textHint),
                ),
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
      1 => AppTheme.accentSoft,
      2 => AppTheme.accent,
      3 => AppTheme.accentViolet,
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
              width: 18,
              height: 18,
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
                  color: top ? AppTheme.surface : AppTheme.textSub,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: top ? FontWeight.w600 : FontWeight.w400,
                color: AppTheme.textMain,
              ),
            ),
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
    );
  }
}