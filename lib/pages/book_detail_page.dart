import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/network/bili_client.dart';
import '../core/storage/cache_store.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../models/content_mode.dart';
import '../models/chapter.dart';
import '../models/up_user.dart';
import '../player/book_player.dart';
import '../services/bili_api.dart';
import '../services/umeng_analytics.dart';
import '../utils/format.dart';
import '../widgets/book_cover.dart';
import '../widgets/shelf_common.dart';
import 'cache_sheet.dart';
import 'player_page.dart';
import 'up_home_page.dart';

/// 书籍详情页：书籍信息 + 章节目录 + 收听入口
class BookDetailPage extends StatefulWidget {
  final String bvid;
  final ContentMode contentMode;
  final int? initialPage;
  final Book? initialBook;
  final BiliApi? api;
  const BookDetailPage({super.key, required this.bvid,
    this.contentMode = ContentMode.audiobook, this.initialPage,
    this.initialBook, this.api});

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  late final _bili = widget.api ?? BiliApi.instance;
  int _requestId = 0;

  Book? _book;
  ContentMode get _contentMode => context.read<ShelfStore>()
      .progressByBvid(widget.bvid)?.book.contentMode ?? widget.contentMode;
  Book? get _effectiveBook => _book?.withContentMode(_contentMode);
  bool _loading = true;
  bool _playPending = false;
  String? _error;

  /// 目录排序：默认正序
  bool _reverse = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialBook != null) {
      _book = widget.initialBook!.withContentMode(_contentMode);
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final book = await _bili.detail(widget.bvid, mode: _contentMode);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _book = book;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = e is BiliApiException ? e.message : '加载失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ShelfStore>();
    return Scaffold(
      appBar: AppBar(title: Text(switch (_contentMode) {
        ContentMode.audiobook => '听书详情',
        ContentMode.music => '歌曲详情',
        ContentMode.concert => '演唱会详情',
        ContentMode.children => '儿童内容详情',
      })),
      body: _loading
          ?  Center(
              child: CircularProgressIndicator(color: AppTheme.actionText),
            )
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
           Icon(Icons.error_outline, size: 48, color: AppTheme.textHint),
          const SizedBox(height: 12),
          Text(_error!,
              style:  TextStyle(fontSize: 13, color: AppTheme.textSub)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final book = _effectiveBook!;
    final player = context.watch<BookPlayer>();
    final shelf = context.watch<ShelfStore>();
    final onShelf = shelf.isOnShelf(book.bvid);
    final shelfBook = shelf.progressByBvid(book.bvid);
    final chapters = book.chapters ?? [];

    final isCurrentBook = player.book?.bvid == book.bvid &&
        player.book?.contentMode == book.contentMode;
    final currentIdx = isCurrentBook ? player.index : -1;
    final cidIndex = chapters.indexWhere((c) => c.cid == shelfBook?.lastCid);
    final resumeIndex = cidIndex >= 0 ? cidIndex : (shelfBook?.lastChapterIndex ?? 0);
    final resumeMs = shelfBook?.positionMs ?? 0;
    final hasProgress = book.contentMode.resumesPosition &&
        widget.initialPage == null &&
        ((shelfBook?.positionMs ?? 0) > 0 ||
            resumeIndex > 0);
    // 已听章节：优先用逐章记录（听满 95% 或播完即打标），
    // 旧版本没有逐章数据时回退到「上次听到的章节序号」
    final hasDoneRecords = (shelfBook?.doneCids.isNotEmpty ?? false);
    final lastListened = isCurrentBook
        ? player.index
        : (hasProgress ? resumeIndex : -1);
    final doneCount = shelf.doneCount(book.bvid);

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _load();
              if (!mounted) return;
              // 刷新书架元数据
              final fresh = _effectiveBook;
              if (fresh != null && onShelf) {
                await context
                    .read<ShelfStore>()
                    .add(fresh, withProgress: shelf.byBvid(fresh.bvid));
              }
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _buildHeader(book),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                       Icon(Icons.format_list_bulleted,
                          size: 18, color: AppTheme.actionText),
                      const SizedBox(width: 8),
Text(
                          '目录（${chapters.length} ${book.contentMode.unitLabel}）',
                          style:  TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                          ),
                        ),
                      if (doneCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '已听 $doneCount',
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.actionText),
                          ),
                        ),
                      TextButton.icon(
                        onPressed: chapters.isEmpty
                            ? null
                            : () => setState(() => _reverse = !_reverse),
                        icon: Icon(
                          _reverse
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 16,
                          color: AppTheme.textSub,
                        ),
                        label: Text(
                          _reverse ? '倒序' : '正序',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textSub),
                        ),
                      ),
                      IconButton(
                        onPressed: chapters.isEmpty
                            ? null
                            : () => CacheSheet.show(context, book: book),
                        tooltip: '批量缓存',
                        icon:  Icon(Icons.download_for_offline_outlined,
                            color: AppTheme.textSub),
                      ),
                      IconButton(
                        onPressed: chapters.isEmpty || _playPending ? null : () => _playFrom(0),
                        tooltip: '从头播放',
                        icon:  Icon(Icons.replay,
                            color: AppTheme.textSub),
                      ),
                    ],
                  ),
                ),
                ..._orderedIndexes(chapters.length).map((i) {
                  // 有逐章记录时以记录为准，否则退回序号推导
                  final listened = hasDoneRecords
                      ? shelf.isChapterDone(book.bvid, chapters[i].cid)
                      : (lastListened >= 0 && i < lastListened);
                  return _ChapterTile(
                    index: i,
                    chapter: chapters[i],
                    listened: listened,
                    isCurrent: i == currentIdx || chapters[i].page == widget.initialPage,
                    isPlaying:
                        i == currentIdx && isCurrentBook && player.isPlaying,
                    bvid: book.bvid,
                    onTap: _playPending ? null : () => _playFrom(i),
                    onCache: () => _cacheOne(chapters[i]),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        _buildBottomBar(
            player, book, onShelf, resumeIndex, resumeMs, hasProgress, chapters),
      ],
    );
  }

  Widget _buildHeader(Book book) {
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 380 ||
          MediaQuery.textScalerOf(context).scale(16) > 24;
      final information = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            book.cleanTitle,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _meta('${book.pages} ${book.contentMode.unitLabel}', Icons.library_books_outlined),
              _meta(book.durationText, Icons.schedule),
              _meta(Fmt.count(book.play), Icons.play_arrow_rounded),
              _meta(book.like.toString(), Icons.thumb_up_alt_outlined),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _openUp(book),
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppTheme.surfaceHigh,
                    backgroundImage: book.authorFace.isNotEmpty ? NetworkImage(book.authorFace) : null,
                    child: book.authorFace.isEmpty ? const Icon(Icons.person, size: 16) : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    book.author.isEmpty ? '未知 UP 主' : 'UP 主 · ${book.author}',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSub),
                  )),
                  // UP 主名可点，进入他的主页只看他的作品
                  if (book.mid != 0)
                    Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textHint),
                ],
              ),
            ),
          ),
          Text(Fmt.date(book.pubdate), style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
        ],
      );
      final cover = BookCover(url: book.pic, width: 110, height: 146);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Center(child: cover), const SizedBox(height: 16), information],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [cover, const SizedBox(width: 16), Expanded(child: information)],
              ),
      );
    });
  }

  Widget _meta(String text, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSub),
        const SizedBox(width: 3),
        Text(text,
            style:  TextStyle(fontSize: 12, color: AppTheme.textSub)),
      ],
    );
  }

  Widget _buildBottomBar(
    BookPlayer player,
    Book book,
    bool onShelf,
    int resumeIndex,
    int resumeMs,
    bool hasProgress,
    List chapters,
  ) {
    final nowPlaying = player.loaded && player.book?.bvid == book.bvid &&
        player.book?.contentMode == book.contentMode &&
        book.contentMode != ContentMode.music && widget.initialPage == null;
    final requestedPage = widget.initialPage;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            IconButton.outlined(
              tooltip: onShelf ? '移出收藏' : '添加到收藏',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => _toggleShelf(onShelf),
              icon: Icon(
                onShelf
                    ? Icons.collections_bookmark_rounded
                    : Icons.bookmark_add_outlined,
                color: onShelf ? AppTheme.actionText : AppTheme.textSub,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: nowPlaying
                  ? _buildNowPlaying(player, book)
                  : FilledButton(
                      onPressed: _playPending ? null : () =>
                          _startPlay(hasProgress, resumeIndex, resumeMs),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                hasProgress
                                    ? Icons.play_arrow_rounded
                                    : Icons.headset,
                                size: 22,
                              ),
                              const SizedBox(width: 6),
                              Flexible(child: Text(
                                _playPending ? '加载中…' : requestedPage != null
                                    ? '播放第 $requestedPage ${book.contentMode.unitLabel}'
                                    : (hasProgress ? '继续收听' : '开始收听'),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600),
                              )),
                            ],
                          ),
                          if (hasProgress)
                            Text(
                              '第 ${resumeIndex + 1} ${book.contentMode.unitLabel} · ${_msText(resumeMs)}',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w400),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 本书正在播放：底部显示当前播放迷你条（点击回到播放页）
  Widget _buildNowPlaying(BookPlayer player, Book book) {
    final chapter = player.currentChapter;
    return Material(
      color: AppTheme.surfaceHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _playPending ? null : _openPlayer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              BookCover(url: book.pic, width: 38, height: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      player.error != null ? '暂时无法播放' : (player.isPlaying ? '正在播放' : '已暂停'),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.actionText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      chapter == null
                          ? book.cleanTitle
                          : '第 ${chapter.page} ${book.contentMode.unitLabel} · ${chapter.part}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textMain),
                    ),
                  ],
                ),
              ),
              if (player.loading)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.actionText),
                  ),
                )
              else
                IconButton(
                  tooltip: player.error != null ? '重试播放' : (player.isPlaying ? '暂停' : '播放'),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: player.error != null ? player.retryPlayback : player.togglePlay,
                  icon: Icon(
                    player.error != null ? Icons.refresh_rounded : (player.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                    color: AppTheme.actionText,
                    size: 28,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPlayer() {
    if (_playPending || ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerPage()),
    );
  }

  void _toggleShelf(bool onShelf) async {
    final shelf = context.read<ShelfStore>();
    if (onShelf) {
      final saved = shelf.byBvid(widget.bvid);
      if (saved != null) await confirmRemoveFromShelf(context, saved);
      return;
    } else {
      await shelf.add(_effectiveBook!);
      AppAnalytics.onEvent('shelf_add_manual');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(onShelf ? '已移除收藏' : '已加入收藏'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// 点击 UP 主名进入他的主页（只看这一个人的内容）
  void _openUp(Book book) {
    if (book.mid == 0 || book.author.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该作品没有 UP 主信息')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UpHomePage(
          contentMode: book.contentMode,
          api: _bili,
          up: UpUser(
            mid: book.mid,
            name: book.author,
            face: book.authorFace,
          ),
        ),
      ),
    );
  }

  /// 毫秒 → h:mm:ss / mm:ss（精确到秒）
  static String _msText(int ms) {
    if (ms <= 0) return '00:00';
    final p = Duration(milliseconds: ms);
    final h = p.inHours;
    final m = p.inMinutes % 60;
    final s = p.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// 目录显示顺序：默认正序，可切换倒序
  List<int> _orderedIndexes(int count) {
    final list = List<int>.generate(count, (i) => i);
    if (_reverse) return list.reversed.toList();
    return list;
  }

  Future<void> _startPlay(bool hasProgress, int resumeIndex, int resumeMs) async {
    final book = _effectiveBook!;
    final requestedIndex = (book.chapters ?? <Chapter>[])
        .indexWhere((chapter) => chapter.page == widget.initialPage);
    await _submitPlay((player) {
      if (requestedIndex >= 0) {
        return player.playBook(book, resumeIndex: requestedIndex,
            resumeCid: book.chapters![requestedIndex].cid);
      } else if (!book.contentMode.resumesPosition) {
        return player.playBook(book, resume: false);
      } else if (hasProgress) {
        return player.playBook(book, resumeIndex: resumeIndex, resumeMs: resumeMs,
            resumeCid: context.read<ShelfStore>().progressByBvid(book.bvid)?.lastCid);
      }
      return player.playBook(book);
    });
  }

  /// 缓存单集到本地（供离线收听）
  Future<void> _cacheOne(Chapter c) async {
    final book = _effectiveBook;
    if (book == null) return;
    final cache = context.read<CacheStore>();
    if (cache.isCached(book.bvid, c.cid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('第 ${c.page} ${book.contentMode.unitLabel}已缓存'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    final player = context.read<BookPlayer>();
    final messenger = ScaffoldMessenger.of(context);
    final url = await player.resolveUrlFor(book.bvid, c.cid);
    if (!mounted) return;
    if (url == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('获取下载地址失败，请检查网络'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final chapters = book.chapters ?? const <Chapter>[];
    final idx = chapters.indexWhere((x) => x.cid == c.cid);
    final ok = await cache.download(
      bvid: book.bvid,
      contentMode: book.contentMode,
      cid: c.cid,
      url: url,
      bookTitle: book.cleanTitle,
      chapterTitle: '${c.page} · ${c.part}',
      cover: book.pic,
      durationSec: c.duration,
      headers: player.downloadHeaders,
      page: c.page,
      part: c.part,
      order: idx >= 0 ? idx + 1 : 0,
      // 按 132kbps 音轨粗估（一小时约 60MB），与批量缓存保持一致
      expectBytes: c.duration > 0 ? (c.duration * 16500) + 2097152 : null,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? '第 ${c.page} ${book.contentMode.unitLabel}已缓存，可离线收听' : '缓存失败，请稍后重试'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _playFrom(int index) async {
    final book = _effectiveBook!;
    await _submitPlay((player) => player.playBook(book, resumeIndex: index,
        resumeCid: book.chapters![index].cid), chapterIndex: index);
  }

  Future<void> _submitPlay(Future<bool> Function(BookPlayer) submit,
      {int? chapterIndex}) async {
    final route = ModalRoute.of(context);
    if (_playPending || route?.isCurrent != true) return;
    final player = context.read<BookPlayer>();
    final book = _effectiveBook!;
    setState(() => _playPending = true);
    try {
      player.flushProgress();
      final ok = await submit(player);
      if (!mounted || route?.isCurrent != true) return;
      if (!ok) {
        _showPlayFailure();
      } else if (chapterIndex == null) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PlayerPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(player.isPlaying
              ? '正在播放第 ${chapterIndex + 1} ${book.contentMode.unitLabel}…'
              : '已加载第 ${chapterIndex + 1} ${book.contentMode.unitLabel}，当前已暂停'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (_) {
      if (mounted && route?.isCurrent == true) _showPlayFailure();
    } finally {
      if (mounted) setState(() => _playPending = false);
    }
  }

  void _showPlayFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('播放失败，请检查网络后重试')),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final int index;
  final Chapter chapter;
  final bool listened;
  final bool isCurrent;
  final bool isPlaying;
  final String bvid;
  final VoidCallback? onTap;
  final VoidCallback onCache;

  const _ChapterTile({
    required this.index,
    required this.chapter,
    required this.listened,
    required this.isCurrent,
    required this.isPlaying,
    required this.bvid,
    required this.onTap,
    required this.onCache,
  });

  /// 标题自带序号（01xxx / 第 1 章 / P1 / 1 · xxx）时不再重复加序号
  static final RegExp _ownIndex = RegExp(
    r'^\s*(?:第\s*[0-9一二三四五六七八九十百千零两]+\s*[章集回话期节]'
    r'|[Pp]\s*[0-9]{1,4}\b'
    r'|[0-9]{1,4}\s*[.·、:：)\-—]'
    r'|[0-9]{1,4}(?=\s*[^\s0-9]))',
  );

  bool get _hasOwnIndex => _ownIndex.hasMatch(chapter.part.trim());

  @override
  Widget build(BuildContext context) {
    final Color titleColor;
    if (isCurrent) {
      titleColor = AppTheme.actionText;
    } else if (listened) {
      titleColor = AppTheme.textHint;
    } else {
      titleColor = AppTheme.textMain;
    }
    final numberColor = isCurrent
        ? AppTheme.actionText
        : (listened ? AppTheme.textHint : AppTheme.textSub);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (isPlaying)
               Icon(Icons.graphic_eq_rounded,
                  size: 18, color: AppTheme.actionText)
            else if (_hasOwnIndex)
              SizedBox(
                width: 18,
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: listened
                          ? AppTheme.textHint.withValues(alpha: 0.35)
                          : AppTheme.divider,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                width: 18,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: numberColor),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                chapter.part,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: titleColor,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (listened && !isCurrent) ...[
              Icon(Icons.check_rounded, size: 15, color: AppTheme.textHint),
              const SizedBox(width: 6),
            ],
            const SizedBox(width: 8),
            Text(
              chapter.durationText,
              style: TextStyle(fontSize: 12, color: AppTheme.textHint),
            ),
            const SizedBox(width: 6),
            _CacheButton(bvid: bvid, cid: chapter.cid, onTap: onCache),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// 章节目录行尾的缓存按钮：未缓存显示下载图标，已缓存显示「已缓存」
class _CacheButton extends StatelessWidget {
  final String bvid;
  final int cid;
  final VoidCallback onTap;

  const _CacheButton({
    required this.bvid,
    required this.cid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheStore>();
    final cached = cache.isCached(bvid, cid);
    final task = cache.taskOf(bvid, cid);
    final busy = task != null && !task.done && !task.failed;

    if (busy) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.actionText,
                value: task.progress > 0 ? task.progress : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(task.progress * 100).round()}%',
              style: TextStyle(fontSize: 10, color: AppTheme.actionText),
            ),
          ],
        ),
      );
    }

    return Tooltip(
      message: cached ? '本分 P 已缓存' : '缓存本分 P',
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Center(child: cached
            ? Text(
                '已缓存',
                style: TextStyle(fontSize: 11, color: AppTheme.actionText),
              )
            : Icon(Icons.download_rounded,
                size: 20, color: AppTheme.textHint)),
      ),
    ));
  }
}