/// 应用元信息（版本号与 pubspec.yaml 保持一致）
class AppMeta {
  AppMeta._();

  static const String name = '阿B听书';
  static const String version = '0.1.0';

  /// 副标题 / 一句话介绍
  static const String tagline = '免登录、无广告、专注收听的 B 站有声小说播放器';

  /// 开源仓库
  static const String repoUrl = 'https://github.com/fengqiao57/abts';

  /// 官网
  static const String siteUrl = 'https://abts.pages.dev/';

  /// 开源协议
  static const String licenseUrl = '$repoUrl/blob/main/LICENSE';

  /// 问题反馈
  static const String issuesUrl = '$repoUrl/issues';
}