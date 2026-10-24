import 'package:flutter/foundation.dart';

import '../../models/content_mode.dart';

/// 全局底部 Tab 切换（供空态"去发现"等跨页面跳转使用）
class HomeTabs {
  HomeTabs._();
  static final ValueNotifier<int> index = ValueNotifier<int>(0);

  static final ValueNotifier<ContentMode?> discoverMode = ValueNotifier(null);

  static void openDiscover(ContentMode mode) {
    discoverMode.value = mode;
    index.value = 1;
  }

  static void switchTo(int i) => index.value = i;
}