import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/cache_store.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../data/seed_books.dart';
import '../models/book.dart';
import '../models/content_mode.dart';
import '../player/book_player.dart';
import '../services/bili_api.dart';
import '../widgets/book_cards.dart';
import '../widgets/book_cover.dart';
import '../widgets/resource_import_dialog.dart';
import 'book_detail_page.dart';
import 'cache_page.dart';
import 'player_page.dart';
import 'search_page.dart';

/// 发现：分类浏览（热门/广播剧/评书…）+ 搜索入口 + 精选推荐兜底
/// 搜索跳转到独立搜索页（支持分页）
class DiscoverPage extends StatefulWidget {
  final BiliApi? api;
  const DiscoverPage({super.key, this.api});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _controller = TextEditingController();
  late final _bili = widget.api ?? BiliApi.instance;

  // 分类浏览
  int _cat = 0;
  bool _browseLoading = true;
  String? _browseError;
  List<Book> _browseBooks = [];
  final Map<int, List<Book>> _browseCache = {};
  int _browseRequestId = 0;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _loadBrowse();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _switchCategory(int i) {
    if (i == _cat) return;
    setState(() {
      _cat = i;
      _browseBooks = [];
    });
    _loadBrowse();
  }

  /// 分类浏览：从 B 站拉取该分类真实内容（带缓存，避免来回切换重复请求触发风控）
  Future<void> _loadBrowse({bool force = false}) async {
    // 先固定住本次请求对应的分类：await 之后 _cat 可能已被用户切走，
    // 若还用 _cat 写缓存/渲染，A 的结果会落到 B 的分类下。
    final catIndex = _cat;
    final requestId = ++_browseRequestId;
    _cancelToken?.cancel();
    final cancelToken = _cancelToken = CancelToken();
    if (!force && _browseCache.containsKey(catIndex)) {
      setState(() {
        _browseBooks = _browseCache[catIndex]!;
        _browseLoading = false;
        _browseError = null;
      });
      return;
    }
    final cat = DiscoverSeeds.categories[catIndex];
    setState(() {
      _browseLoading = true;
      _browseError = null;
    });
    try {
      // 错开自动请求，降低被风控的概率
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || requestId != _browseRequestId) return;
      // 热门推荐：有声小说按播放量排序的榜单；其余分类走关键词搜索
      Object? partialError;
      final list = catIndex == 0
          ? await _bili.rankHotNovel(cancelToken: cancelToken, onPartialFailure: (e) => partialError = e)
          : await _bili.search(cat.keyword, cancelToken: cancelToken, mode: cat.mode);
      if (!mounted || requestId != _browseRequestId) return;
      if (partialError == null) _browseCache[catIndex] = list;
      // 期间用户已切到别的分类就别覆盖当前界面
      if (_cat != catIndex) return;
      setState(() {
        _browseBooks = list;
        _browseError = partialError == null ? null : '部分内容加载失败，可重试';
        _browseLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _browseRequestId) return;
      if (_cat != catIndex) return;
      setState(() {
        _browseLoading = false;
        _browseError = '加载失败，请重试';
      });
    }
  }

  void _openSearch([String? keyword]) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchPage(
          api: _bili,
          initialKeyword: keyword,
          initialMode: DiscoverSeeds.categories[_cat].mode,
          autofocus: keyword == null || keyword.isEmpty,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
        actions: [IconButton(
          tooltip: '添加 B 站资源',
          onPressed: () => showResourceImportDialog(context,
              initialMode: DiscoverSeeds.categories[_cat].mode),
          icon: const Icon(Icons.add_link_rounded),
        )],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: InkWell(
                      onTap: _openSearch,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.outline),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search,
                                size: 18, color: AppTheme.textHint),
                            const SizedBox(width: 8),
                            Expanded(child: Text(
                              switch (DiscoverSeeds.categories[_cat].mode) {
                                ContentMode.audiobook => '搜索书名 / 作者 / 主播',
                                ContentMode.music => '搜索歌名 / 歌手 / UP 主',
                                ContentMode.concert => '搜索演唱会 / 歌手 / UP 主',
                                ContentMode.children => '搜索儿歌 / 动画 / 故事',
                              },
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textHint,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBrowseBody()),
        ],
      ),
    );
  }

  // ---------- 分类浏览视图 ----------
  Widget _buildBrowseBody() {
    final cat = DiscoverSeeds.categories[_cat];
    return Column(
      children: [
        // 分类栏
        SizedBox(
          height: 60 * MediaQuery.textScalerOf(context).scale(1),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: DiscoverSeeds.categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = DiscoverSeeds.categories[i];
              final selected = i == _cat;
              return Semantics(
                key: ValueKey('discover-category-$i'),
                selected: selected,
                button: true,
                child: GestureDetector(
                onTap: () => _switchCategory(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.accent : AppTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? AppTheme.accent : AppTheme.divider,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(c.icon,
                          size: 16,
                          color: selected
                              ? AppTheme.onPrimary
                              : AppTheme.textSub),
                      const SizedBox(width: 6),
                      Text(
                        c.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color:
                              selected ? AppTheme.onPrimary : AppTheme.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadBrowse(force: true),
            color: AppTheme.accent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: _buildBrowseChildren(cat),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildBrowseChildren(DiscoverCategory cat) {
    if (_browseLoading && _browseBooks.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 64),
          child: Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          ),
        ),
      ];
    }
    return [
      if (_browseLoading) const LinearProgressIndicator(),
      if (_browseError != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(Icons.cloud_off_outlined, size: 36, color: AppTheme.textHint),
              const SizedBox(height: 8),
              Text(
                _browseError!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSub),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _loadBrowse(force: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        ..._buildOfflineSection(),
      ],
      if (_browseBooks.isNotEmpty)
        ..._buildRealResults(cat)
      else if (_browseError == null && !_browseLoading)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(children: [
            Icon(Icons.search_off_rounded, size: 40, color: AppTheme.textHint),
            const SizedBox(height: 12),
            Text('暂时没有相关内容', style: TextStyle(color: AppTheme.textMain)),
            const SizedBox(height: 8),
            Text('可以换个分类，或搜索想听的内容',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSub)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _openSearch, child: const Text('去搜索')),
          ]),
        ),
      ..._buildAnchorsSection(cat),
    ];
  }

  /// 请求失败时单独检查真实缓存，提供已下载内容入口
  List<Widget> _buildOfflineSection() {
    final cached = context.watch<CacheStore>().cachedBooks();
    if (cached.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Row(
          children: [
            Icon(Icons.download_done_rounded, size: 17, color: AppTheme.actionText),
            const SizedBox(width: 6),
            Text('已缓存的内容',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain)),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CachePage())),
              child: Text('全部 ${cached.length} 项',
                  style: TextStyle(fontSize: 13, color: AppTheme.actionText)),
            ),
          ],
        ),
      ),
      ...cached.take(12).map((b) {
        final entries = context.read<CacheStore>().entriesOf(b.bvid);
        final mode = ShelfStore.instance.byBvid(b.bvid)?.book.contentMode ??
            (entries.isEmpty ? ContentMode.audiobook : entries.first.contentMode);
        final book = Book(bvid: b.bvid, aid: 0, title: b.title, pic: b.cover,
            contentMode: mode);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _OfflineBookTile(book: book, count: b.count),
        );
      }),
    ];
  }

  List<Widget> _buildRealResults(DiscoverCategory cat) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Row(
          children: [
            // 刷新按钮放在标题左侧（原闪电图标位置）
            IconButton(
              onPressed: () => _loadBrowse(force: true),
              icon: Icon(Icons.refresh_rounded,
                  size: 19, color: AppTheme.actionText),
              tooltip: '刷新',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _cat == 0 ? '热门榜单' : cat.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain,
                ),
              ),
            ),
            // 「更多」：带着当前分类关键词进搜索页看完整结果
            TextButton.icon(
              onPressed: () => _openMore(cat),
              icon: Icon(Icons.open_in_new_rounded,
                  size: 14, color: AppTheme.actionText),
              label: Text('更多',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.actionText)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
      ),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: MediaQuery.sizeOf(context).width < 360 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 2 : 3,
          mainAxisSpacing: 14,
          crossAxisSpacing: 12,
          childAspectRatio: 0.55,
        ),
        itemCount: _browseBooks.length,
        itemBuilder: (context, i) {
          final b = _browseBooks[i];
          return BookGridItem(book: b, onTap: () => _open(b));
        },
      ),
      const SizedBox(height: 12),
    ];
  }

  /// 「更多」：把分类关键词带进搜索页，可继续翻页看全部结果
  void _openMore(DiscoverCategory cat) {
    final kw = _cat == 0 ? '有声小说' : cat.keyword;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchPage(initialKeyword: kw, autofocus: false, initialMode: cat.mode, api: _bili),
      ),
    );
  }

  /// 精选主播：点击查看该主播相关的有声小说（进入独立搜索页）
  List<Widget> _buildAnchorsSection(DiscoverCategory cat) {
    if (cat.anchors.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Row(
          children: [
            Icon(Icons.mic_rounded, size: 18, color: AppTheme.actionText),
            const SizedBox(width: 6),
            Expanded(child: Text(
              '精选主播',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMain,
              ),
            )),
            Flexible(child: Text(
              '点击查看 TA 的作品',
              style: TextStyle(fontSize: 11, color: AppTheme.textHint),
            )),
          ],
        ),
      ),
      SizedBox(
        height: 96 + 40 * MediaQuery.textScalerOf(context).scale(1),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: cat.anchors.length,
          separatorBuilder: (_, _) => const SizedBox(width: 16),
          itemBuilder: (context, i) {
            final a = cat.anchors[i];
            return _AnchorTile(
              anchor: a,
              onTap: () => _openSearch(a.keyword),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
    ];
  }

  void _open(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BookDetailPage(bvid: book.bvid, contentMode: book.contentMode, api: _bili)),
    );
  }
}

/// 精选主播卡片：圆形头像 + 名字 + 代表作（无网络依赖）
class _AnchorTile extends StatelessWidget {
  final AnchorPick anchor;
  final VoidCallback onTap;

  const _AnchorTile({required this.anchor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = anchor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.accent,
                    AppTheme.accentSoft,
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                a.name.characters.first,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMain,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              a.works,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: AppTheme.textHint),
            ),
          ],
        ),
      ),
    );
  }
}
/// 已缓存书籍卡片，复用缓存播放路径
class _OfflineBookTile extends StatelessWidget {
  final Book book;
  final int count;
  const _OfflineBookTile({required this.book, required this.count});

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final cache = context.read<CacheStore>();
          final entries = cache.entriesOf(book.bvid)
            ..sort(CacheEntry.compareByOrder);
          if (entries.isEmpty) return;
          // 有续播记录且那一集还在缓存里，就接着上次的位置听
          final shelf = ShelfStore.instance.progressByBvid(book.bvid);
          final cid = (book.contentMode.resumesPosition && shelf != null &&
                  entries.any((e) => e.cid == shelf.lastCid))
              ? shelf.lastCid
              : entries.first.cid;
          final r = await BookPlayer.instance
              .playCachedEntry(book.bvid, cid, book);
          if (!context.mounted) return;
          switch (r) {
            case CachePlayOutcome.okOffline:
            case CachePlayOutcome.okOnline:
              navigator.push(
                  MaterialPageRoute(builder: (_) => const PlayerPage()));
              return;
            case CachePlayOutcome.fileMissing:
              messenger.showSnackBar(const SnackBar(
                  content: Text('缓存文件已丢失，请重新缓存')));
              return;
            case CachePlayOutcome.failed:
              messenger.showSnackBar(const SnackBar(
                  content: Text('暂时无法播放该缓存，请重试')));
              return;
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              BookCover(url: book.pic, width: 48, height: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.cleanTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.offline_pin_rounded,
                            size: 13, color: AppTheme.actionText),
                        const SizedBox(width: 4),
                        Text('已缓存 $count ${book.contentMode.unitLabel} · 离线可听',
                            style: TextStyle(
                                fontSize: 11.5, color: AppTheme.textSub)),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_arrow_rounded,
                  size: 26, color: AppTheme.actionText),
            ],
          ),
        ),
      ),
    );
  }
}