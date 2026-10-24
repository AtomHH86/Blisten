import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/storage/shelf_store.dart';
import '../core/nav/home_tabs.dart';
import '../models/book.dart';
import '../utils/format.dart';
import '../pages/player_page.dart';
import '../player/book_player.dart';
import '../widgets/book_cover.dart';

/// 底部迷你播放条
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _syncSpin(bool playing) {
    if (playing) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      if (_spin.isAnimating) _spin.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<BookPlayer>();
    final recent = context.watch<ShelfStore>().recentBooks;
    // stop() retains book metadata, but no longer represents a playable session.
    final hasSession =
        player.book != null &&
        (player.loaded || player.loading || player.error != null);
    final preview = !hasSession && recent.isNotEmpty ? recent.first : null;
    final book = hasSession ? player.book : preview?.book;
    final chapter = hasSession ? player.currentChapter : null;
    final playing = player.loaded && player.isPlaying;
    _syncSpin(
      playing &&
          !player.loading &&
          !player.buffering &&
          player.error == null &&
          !MediaQuery.disableAnimationsOf(context) &&
          !MediaQuery.accessibleNavigationOf(context),
    );
    if (book == null) {
      return Material(
        color: AppTheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Expanded(child: Text('还没有收听内容')),
              TextButton(
                onPressed: () => HomeTabs.switchTo(1),
                child: const Text('去发现'),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: AppTheme.surface,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PlayerPage(preview: preview)),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.divider)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _buildDisc(book),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      book.cleanTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMain,
                      ),
                    ),
                    if (player.error != null ||
                        chapter != null ||
                        preview != null)
                      if (chapter != null &&
                          preview == null &&
                          player.error == null)
                        ValueListenableBuilder<Duration>(
                          valueListenable: player.positionTick,
                          builder: (_, position, _) => Text(
                            '第 ${chapter.page} ${book.contentMode.unitLabel} · ${Fmt.duration(position)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSub,
                            ),
                          ),
                        )
                      else
                        Text(
                          player.error != null
                              ? '播放失败，可重试'
                              : '第 ${preview!.lastChapterIndex + 1} ${book.contentMode.unitLabel} · ${preview.positionText}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSub,
                          ),
                        ),
                  ],
                ),
              ),
              _buildButton(player, preview),
            ],
          ),
        ),
      ),
    );
  }

  /// 封面只负责进入播放页，播放操作由右侧独立按钮承担。
  Widget _buildDisc(Book book) => SizedBox(
    width: 48,
    height: 48,
    child: ExcludeSemantics(
      child: RotationTransition(
        key: const ValueKey('mini-player-disc'),
        turns: _spin,
        child: ClipOval(
          child: BookCover(
            url: book.pic,
            width: 48,
            height: 48,
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    ),
  );

  Widget _buildButton(BookPlayer player, ShelfBook? preview) {
    if (player.loading || (player.buffering && player.error == null)) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: AppTheme.accent,
            ),
          ),
        ),
      );
    }
    final enabled = player.book != null || preview != null;
    return IconButton.filled(
      style: IconButton.styleFrom(backgroundColor: AppTheme.accent),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: !enabled
          ? null
          : preview != null
          ? () => player.resumeShelf(preview)
          : player.error != null
          ? player.retryPlayback
          : player.togglePlay,
      icon: Icon(
        player.error != null
            ? Icons.refresh_rounded
            : (player.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded),
        color: enabled ? AppTheme.onPrimary : AppTheme.textHint,
        size: 32,
      ),
      tooltip: player.error != null ? '重试播放' : (player.isPlaying ? '暂停' : '播放'),
    );
  }
}
