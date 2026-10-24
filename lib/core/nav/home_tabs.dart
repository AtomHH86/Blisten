import 'package:flutter/foundation.dart';

import '../../models/content_mode.dart';

enum LibraryView {
  favorites,
  recent,
  cache,
  following;

  String get label => switch (this) {
    favorites => '收藏',
    recent => '在听',
    cache => '缓存',
    following => '关注',
  };
}

/// 全局底部 Tab 切换（供空态"去发现"等跨页面跳转使用）
class HomeTabs {
  HomeTabs._();
  static final ValueNotifier<int> index = ValueNotifier<int>(0);

  static final ValueNotifier<ContentMode?> discoverMode = ValueNotifier(null);

  static void openDiscover(ContentMode mode) {
    discoverMode.value = mode;
    index.value = 1;
  }

  static final ValueNotifier<LibraryView> libraryView = ValueNotifier(
    LibraryView.favorites,
  );

  static void openLibrary(LibraryView view) {
    libraryView.value = view;
    index.value = 0;
  }

  static void switchTo(int i) => index.value = i;
}
