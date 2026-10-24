import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/nav/home_tabs.dart';
import '../core/theme/app_theme.dart';
import 'favorites_page.dart';
import 'recent_page.dart';
import 'cache_page.dart';
import 'follow_page.dart';

/// 个人资料库：四种视图共享导航，各自保留会话内滚动状态。
class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});
  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  final _visited = <LibraryView>{HomeTabs.libraryView.value};
  final _keys = List.generate(4, (_) => GlobalKey());
  final _bucket = PageStorageBucket();
  @override
  void initState() {
    super.initState();
    HomeTabs.libraryView.addListener(_changed);
    HomeTabs.index.addListener(_changed);
  }

  void _changed() {
    setState(() => _visited.add(HomeTabs.libraryView.value));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _keys[HomeTabs.libraryView.value.index].currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: Duration.zero,
          alignment: .5,
        );
      }
    });
  }

  @override
  void dispose() {
    HomeTabs.libraryView.removeListener(_changed);
    HomeTabs.index.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = HomeTabs.libraryView.value;
    final scale = MediaQuery.textScalerOf(context).scale(24) / 24;
    final height = math.max(56.0, 40 * scale + 16);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final slot = math.max(constraints.maxWidth / 4, 72 * scale);
                return SizedBox(
                  key: const ValueKey('library-header'),
                  height: height,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final view in LibraryView.values)
                          Semantics(
                            key: ValueKey('library-tab-${view.name}'),
                            selected: selected == view,
                            button: true,
                            child: InkWell(
                              key: _keys[view.index],
                              onTap: () => HomeTabs.openLibrary(view),
                              child: SizedBox(
                                width: slot,
                                height: height,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Positioned(
                                      top: 4,
                                      child: Baseline(
                                        baseline: 30 * scale,
                                        baselineType: TextBaseline.alphabetic,
                                        child: AnimatedDefaultTextStyle(
                                          duration: duration,
                                          style: TextStyle(
                                            fontSize: selected == view
                                                ? 24
                                                : 16,
                                            fontWeight: selected == view
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: selected == view
                                                ? AppTheme.actionText
                                                : AppTheme.textSub,
                                          ),
                                          child: Text(view.label),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 4,
                                      child: AnimatedContainer(
                                        duration: duration,
                                        width: selected == view ? 20 : 0,
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: AppTheme.actionText,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Expanded(
              child: PageStorage(
                bucket: _bucket,
                child: IndexedStack(
                  index: selected.index,
                  children: [
                    for (final view in LibraryView.values)
                      _visited.contains(view)
                          ? switch (view) {
                              LibraryView.favorites => FavoritesPage(
                                embedded: true,
                                active:
                                    selected == view &&
                                    HomeTabs.index.value == 0,
                              ),
                              LibraryView.recent => const RecentPage(
                                embedded: true,
                              ),
                              LibraryView.cache => const CachePage(
                                embedded: true,
                              ),
                              LibraryView.following => const FollowPage(
                                embedded: true,
                              ),
                            }
                          : const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
