/// 应用元信息（版本号与 pubspec.yaml 保持一致）
///
/// ⚠️ 每次发版必须和 pubspec.yaml 的 version 一起改，否则「检查更新」会误判：
/// 这里是拿本地版本去和 GitHub Release 的 tag 比大小。
class AppMeta {
  AppMeta._();

  static const String name = 'B听';
  static const String version = '1.1.0';

  /// 副标题 / 一句话介绍
  static const String tagline = '闭上眼听 B 站';

  /// 开源仓库
  static const String repoUrl = 'https://github.com/AtomHH86/Blisten';

  /// 官网
  static const String siteUrl = '';

  /// 原项目来源与保留的 MIT 许可证
  static const String upstreamUrl = 'https://github.com/fengqiao57/abts';
  static const String licenseUrl = '$upstreamUrl/blob/main/LICENSE';

  /// 问题反馈
  static const String issuesUrl = '$repoUrl/issues';
}