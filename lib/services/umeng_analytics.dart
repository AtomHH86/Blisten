/// 兼容原有事件调用的无操作接口。
///
/// B听不初始化统计 SDK，也不发送页面或行为数据。保留接口以避免改动播放业务。
class AppAnalytics {
  AppAnalytics._();

  static void onEvent(String name, [Map<String, dynamic>? params]) {}

  static void onPageStart(String name) {}

  static void onPageEnd(String name) {}
}
