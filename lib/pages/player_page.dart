import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_meta.dart';
import '../core/network/api_config.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../player/book_player.dart';
import '../utils/format.dart';
import '../widgets/book_cover.dart';
import '../widgets/sleep_timer_controls.dart';
import 'book_detail_page.dart';
import 'cache_sheet.dart';

/// 全屏播放页：封面、进度与主要收听控制
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, this.preview});

  final ShelfBook? preview;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  double _dragValue = -1;
  final _speedFocus = FocusNode(debugLabel: '倍速');
  final _chapterFocus = FocusNode(debugLabel: '目录');
  final _timerFocus = FocusNode(debugLabel: '睡眠定时');

  /// 提前抓住播放器引用：在 dispose() 里再 context.read 会触发
  /// provider 的「查找已失活 widget 的祖先」断言。
  BookPlayer? _playerRef;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playerRef = context.read<BookPlayer>();
  }

  @override
  void dispose() {
    _playerRef?.flushProgress();
    _speedFocus.dispose();
    _chapterFocus.dispose();
    _timerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<BookPlayer>();

    final recent = context.watch<ShelfStore>().recentBooks;
    final preview = player.book == null && widget.preview != null
        ? recent.where((row) => row.book.bvid == widget.preview!.book.bvid).firstOrNull
        : null;
    if (preview != null) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(title: const Text('上次收听')),
        body: SafeArea(child: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            SizedBox(height: 240, child: _buildCover(preview.book)),
            const SizedBox(height: 24),
            Text(preview.book.cleanTitle, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, color: AppTheme.textMain)),
            const SizedBox(height: 12),
            Text('第 ${preview.lastChapterIndex + 1} ${preview.book.contentMode.unitLabel} · ${preview.positionText}'),
            const SizedBox(height: 24),
            IconButton.filled(
              tooltip: '播放', iconSize: 48,
              onPressed: () => player.resumeShelf(preview),
              icon: const Icon(Icons.play_arrow_rounded)),
          ]),
        ))),
      );
    }

    if (player.book == null || !player.loaded) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          title: const Text('播放'),
          leading: IconButton(
            tooltip: '返回上一页，继续收听',
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: player.loading
              ?  CircularProgressIndicator(color: AppTheme.actionText, semanticsLabel: '正在加载音频')
              : player.error != null
                  ? SingleChildScrollView(child: _buildPlaybackError(player))
                  : Text('尚未播放任何内容',
                      style: TextStyle(fontSize: 14, color: AppTheme.textSub)),
        ),
      );
    }

    final book = player.book!;
    final chapter = player.currentChapter;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          // 背景模糊封面
          Positioned.fill(
            child: book.pic.isEmpty
                ? Container(color: AppTheme.surface)
                : Image.network(
                    Book.normalizePic(book.pic),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Container(color: AppTheme.surface),
                  ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: _playerBlur,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppTheme.scrim),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildAppBar(player),
                      SizedBox(
                        height: math.max(120, math.min(
                          constraints.maxWidth - 64, constraints.maxHeight * 0.38)),
                        child: _buildCover(book),
                      ),
                      _buildTitle(book, chapter),
                      if (player.error != null) _buildPlaybackError(player),
                      _buildProgress(player, chapter),
                      _buildControls(player),
                      _buildActionRow(player),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackError(BookPlayer player) {
    return Semantics(
      liveRegion: true,
      child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 32, color: AppTheme.error),
          const SizedBox(height: 12),
          Text('暂时无法播放',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600,
                  color: AppTheme.textMain)),
          const SizedBox(height: 8),
          Text('请重试，或返回后选择其他内容。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppTheme.textSub)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: player.loading ? null : player.retryPlayback,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
      ),
    );
  }

  static final ImageFilter _playerBlur = ImageFilter.blur(
    sigmaX: 40,
    sigmaY: 40,
  );

  Widget _buildAppBar(BookPlayer player) {
    return Row(
      children: [
        IconButton(
          tooltip: '返回上一页，继续收听',
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          color: AppTheme.textMain,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 4),
        Expanded(child: Text(
          player.loading
              ? '加载中…'
              : player.isOffline
                  ? '离线播放中'
                  : '正在收听',
          style:  TextStyle(
              fontSize: 14,
              color: player.isOffline ? AppTheme.actionText : AppTheme.textSub),
        )),
        IconButton(
          tooltip: '分享原作品链接',
          icon: const Icon(Icons.share_outlined, size: 22),
          color: AppTheme.textSub,
          onPressed: () => _share(player),
        ),
      ],
    );
  }

  /// 分享原作品链接（哔哩哔哩）
  Future<void> _share(BookPlayer player) async {
    final b = player.book;
    if (b == null) return;
    final url = BiliEndpoints.video(b.bvid);
    try {
      await SharePlus.instance.share(
        ShareParams(
          subject: b.cleanTitle,
          text: '我在「${AppMeta.name}」收听《${b.cleanTitle}》\n$url',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分享失败，请稍后重试')),
      );
    }
  }

  Future<void> _showChapterSheet(BookPlayer player) async {
    final chapters = player.chapters;
    if (chapters.isEmpty) return;
    final shelf = context.read<ShelfStore>();
    final bvid = player.book?.bvid ?? '';
    await _showPanel(_chapterFocus, (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                     Icon(Icons.format_list_bulleted,
                        size: 18, color: AppTheme.actionText),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      '目录 · ${chapters.length} ${player.book!.contentMode.unitLabel}',
                      style:  TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    )),
                    IconButton(
                      tooltip: '从头播放',
                      icon:  Icon(Icons.replay, color: AppTheme.textSub),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        player.playChapterIndex(0);
                      },
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: chapters.length,
                  itemBuilder: (ctx, i) {
                    final c = chapters[i];
                    final active = i == player.index;
                    final done = bvid.isNotEmpty && shelf.isChapterDone(bvid, c.cid);
                    return ListTile(
                      selected: active,
                      dense: true,
                      leading: active
                          ?  Icon(Icons.graphic_eq_rounded,
                              size: 18, color: AppTheme.actionText)
                          : SizedBox(
                              width: 18,
                              child: done
                                  ? Icon(Icons.check_rounded,
                                      size: 15, color: AppTheme.textHint)
                                  : Text(
                                      '${i + 1}',
                                      textAlign: TextAlign.center,
                                      style:  TextStyle(
                                          fontSize: 13, color: AppTheme.textSub),
                                    ),
                            ),
                      title: Text(
                        '${c.page} · ${c.part}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w400,
                          color: active
                              ? AppTheme.actionText
                              : (done ? AppTheme.textHint : AppTheme.textMain),
                        ),
                      ),
                      trailing: Text(
                        c.durationText,
                        style:  TextStyle(
                            fontSize: 12, color: AppTheme.textHint),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        player.playChapterIndex(i);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCover(Book book) {
    final player = context.watch<BookPlayer>();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              BookCover(
                url: book.pic,
                borderRadius: BorderRadius.circular(20),
              ),
              if (player.loading)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child:  Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.actionText),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(Book book, dynamic chapter) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BookDetailPage(bvid: book.bvid, contentMode: book.contentMode),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      book.cleanTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style:  TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppTheme.textSub),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (chapter != null)
            Text(
              '第 ${chapter.page} ${book.contentMode.unitLabel} · ${chapter.part}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:  TextStyle(
                  fontSize: 13, color: AppTheme.textSub),
            ),
        ],
      ),
    );
  }

  /// 进度条：高频位置刷新走 ValueListenable，避免整页重建
  Widget _buildProgress(BookPlayer player, Chapter? chapter) {
    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionTick,
      builder: (context, tick, _) {
        final duration = player.currentDuration > Duration.zero
            ? player.currentDuration
            : Duration(seconds: chapter?.duration ?? 0);
        final position = _dragValue >= 0
            ? Duration(milliseconds: _dragValue.toInt())
            : tick;
        return _buildProgressContent(player, position, duration);
      },
    );
  }

  Widget _buildProgressContent(
      BookPlayer player, Duration position, Duration duration) {
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: AppTheme.actionText,
              inactiveTrackColor: AppTheme.divider,
              thumbColor: AppTheme.actionText,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              overlayColor: AppTheme.actionText.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              semanticFormatterCallback: (value) =>
                  '收听进度 ${Fmt.duration(Duration(milliseconds: (value * duration.inMilliseconds).round()))}',
              onChangeStart: duration <= Duration.zero ? null : (_) {
                _dragValue = position.inMilliseconds.toDouble();
              },
              onChanged: duration <= Duration.zero ? null : (v) {
                setState(() {
                  _dragValue = v * duration.inMilliseconds;
                });
              },
              onChangeEnd: duration <= Duration.zero ? null : (v) {
                final target = Duration(
                    milliseconds: (v * duration.inMilliseconds).round());
                setState(() => _dragValue = -1);
                player.seek(target);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(Fmt.duration(position),
                    style:  TextStyle(
                        fontSize: 12, color: AppTheme.textSub)),
                Text(Fmt.duration(duration),
                    style:  TextStyle(
                        fontSize: 12, color: AppTheme.textSub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BookPlayer player) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '上一${player.book!.contentMode.unitLabel}',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            iconSize: 32,
            color: player.hasPrev ? AppTheme.textMain : AppTheme.textHint,
            icon: const Icon(Icons.skip_previous_rounded),
            onPressed: player.hasPrev ? player.previous : null,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: '后退 15 秒',
            onPressed: () => player.seekRelative(-15),
            icon: _Seek15Icon(forward: false, color: AppTheme.textSub),
          ),
          Semantics(
            button: true,
            label: player.error != null ? '重试播放' : (player.isPlaying ? '暂停' : '播放'),
            child: Tooltip(
              message: player.error != null ? '重试播放' : (player.isPlaying ? '暂停' : '播放'),
              child: InkResponse(
                onTap: player.loading ? null :
                    (player.error != null ? player.retryPlayback : player.togglePlay),
                radius: 40,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppTheme.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    player.error != null ? Icons.refresh_rounded :
                    (player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    color: AppTheme.onPrimary,
                    size: 44,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: '前进 15 秒',
            onPressed: () => player.seekRelative(15),
            icon: _Seek15Icon(forward: true, color: AppTheme.textSub),
          ),
          IconButton(
            tooltip: '下一${player.book!.contentMode.unitLabel}',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            iconSize: 32,
            color: player.hasNext ? AppTheme.textMain : AppTheme.textHint,
            icon: const Icon(Icons.skip_next_rounded),
            onPressed: player.hasNext ? player.next : null,
          ),
        ],
      ),
    );
  }

  /// 倍速弹窗：0.5x ~ 3.0x 档位，点一下即选中
  Future<void> _showSpeedSheet(BookPlayer player) async {
    await _showPanel(_speedFocus, (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(
                          '${player.book!.contentMode.label}播放速度',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMain,
                          ),
                        )),
                        const SizedBox(width: 12),
                        Text(
                          '当前 ${player.rateLabel}',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.actionText),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in BookPlayer.speedSteps)
                          _speedTile(ctx, player, setSheet, r),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _speedTile(
      BuildContext ctx, BookPlayer player, StateSetter setSheet, double r) {
    final active = (r - player.rate).abs() < 0.001;
    return ListTile(
      selected: active,
      title: Text(
        _speedLabel(r),
        style: TextStyle(
          fontSize: 15,
          color: active ? AppTheme.actionText : AppTheme.textMain,
          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      trailing: active
          ? Icon(Icons.check, color: AppTheme.actionText)
          : null,
      onTap: () {
        player.setRate(r);
        setSheet(() {});
      },
    );
  }

  static String _speedLabel(double r) =>
      '${r % 1 == 0 ? r.toStringAsFixed(1) : r.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '')}x';

  Widget _buildActionRow(BookPlayer player) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          ActionChip(
            focusNode: _speedFocus,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            avatar:  Icon(Icons.speed_rounded,
                size: 16,
                color: player.rate != 1.0 ? AppTheme.actionText : AppTheme.textSub),
            label: Text(
              '倍速 ${player.rateLabel}',
              style: TextStyle(
                fontSize: 12,
                color: player.rate != 1.0 ? AppTheme.actionText : null,
                fontWeight: player.rate != 1.0 ? FontWeight.w700 : null,
              ),
            ),
            onPressed: () => _showSpeedSheet(player),
          ),
          ActionChip(
            focusNode: _chapterFocus,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            avatar:  Icon(Icons.format_list_bulleted,
                size: 16, color: AppTheme.actionText),
            label: Text(
              '目录 · ${player.chapters.length} ${player.book!.contentMode.unitLabel}',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: () => _showChapterSheet(player),
          ),
          ActionChip(
            focusNode: _timerFocus,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            avatar:  Icon(Icons.bedtime_outlined,
                size: 16, color: AppTheme.actionText),
            label: Text(
              player.stopAtChapterEnd
                  ? '播完自动暂停'
                  : player.sleepRemaining > Duration.zero
                      ? '睡眠 ${Fmt.sleepText(player.sleepRemaining)}'
                      : '睡眠定时',
              style: TextStyle(
                fontSize: 12,
                color: player.stopAtChapterEnd ? AppTheme.actionText : null,
                fontWeight:
                    player.stopAtChapterEnd ? FontWeight.w700 : null,
              ),
            ),
            onPressed: () => _showSleepSheet(player),
          ),
          ActionChip(
            materialTapTargetSize: MaterialTapTargetSize.padded,
            avatar:  Icon(Icons.download_for_offline_outlined,
                size: 16,
                color: player.currentCached ? AppTheme.actionText : AppTheme.textSub),
            label: Text(
              player.currentCached ? '已缓存' : '缓存',
              style: TextStyle(
                fontSize: 12,
                color: player.currentCached ? AppTheme.actionText : null,
                fontWeight: player.currentCached ? FontWeight.w700 : null,
              ),
            ),
            onPressed: () => CacheSheet.show(context, book: player.book),
          ),
        ],
      ),
    );
  }

  Future<void> _showPanel(FocusNode trigger, WidgetBuilder builder) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
        child: builder(ctx),
      ),
    );
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      trigger.requestFocus();
    }
  }

  Future<void> _showSleepSheet(BookPlayer player) => _showPanel(
    _timerFocus,
    (ctx) => SafeArea(
      top: false,
      child: SleepTimerControls(showTitle: true,
        onSelected: () => Navigator.of(ctx).pop()),
    ),
  );
}

/// 快进/快退 15 秒图标：圆形箭头叠加数字
/// forward 用同一个 replay 图标旋转 180°，保证两个方向外观一致
class _Seek15Icon extends StatelessWidget {
  final bool forward;
  final Color color;
  const _Seek15Icon({required this.forward, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: forward ? math.pi : 0,
            child: Icon(Icons.replay_rounded, size: 30, color: color),
          ),
          Text(
            '15',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}