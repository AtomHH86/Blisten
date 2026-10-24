import 'package:dio/dio.dart';

import '../core/app_meta.dart';

/// 检查更新：数据源走 GitHub Releases
///
/// 使用 B听独立项目的发布源；原项目链接保留用于来源致谢。
class UpdateResult {
  const UpdateResult({
    required this.configured,
    this.error,
    this.latestVersion,
    this.latestName,
    this.changelog,
    this.htmlUrl,
    this.apkUrl,
  });

  /// 是否已配置 GitHub 仓库（未配置时不会发起请求）
  final bool configured;
  final String? error;
  final String? latestVersion;
  final String? latestName;
  final String? changelog;
  final String? htmlUrl;
  final String? apkUrl;

  bool get hasNewer {
    if (!configured) return false;
    final v = latestVersion;
    if (v == null) return false;
    return _compareVersion(AppMeta.version, v) < 0;
  }
}

/// GitHub 语义化版本比较：等价返回 0，a 大返回 1，a 小返回 -1
int _compareVersion(String a, String b) {
  int toInt(String s) => int.tryParse(s.replaceAll(RegExp(r'\D'), '')) ?? 0;
  final pa = a.split('.');
  final pb = b.split('.');
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? toInt(pa[i]) : 0;
    final y = i < pb.length ? toInt(pb[i]) : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

class AppUpdate {
  AppUpdate._();

  /// GitHub 仓库（检查更新数据源）
  static const String githubOwner = 'AtomHH86';
  static const String githubRepo = 'Blisten';

  static bool get configured => githubOwner.isNotEmpty && githubRepo.isNotEmpty;

  static String get _downloadBase =>
      'https://github.com/$githubOwner/$githubRepo/releases/latest';

  /// 检查最新版本。
  ///
  /// 未配置仓库时直接返回 [configured=false]，不发起网络请求。
  static Future<UpdateResult> check({
    String owner = githubOwner,
    String repo = githubRepo,
  }) async {
    if (owner.isEmpty || repo.isEmpty) {
      return const UpdateResult(configured: false);
    }
    try {
      final resp = await Dio().get(
        'https://api.github.com/repos/$owner/$repo/releases/latest',
        options: Options(
          headers: {'Accept': 'application/vnd.github+json'},
          responseType: ResponseType.json,
        ),
      );
      return parseRelease(
        resp.data as Map? ?? {},
        fallbackUrl: 'https://github.com/$owner/$repo/releases/latest',
      );
    } catch (e) {
      return UpdateResult(configured: true, error: '检查更新失败，请稍后重试');
    }
  }

  /// 解析 GitHub Release 响应与下载入口。
  static UpdateResult parseRelease(Map data, {String? fallbackUrl}) {
    String? apkUrl;
    final assets = data['assets'] as List? ?? const [];
    for (final a in assets) {
      final m = a as Map?;
      final name = '${m?['name'] ?? ''}';
      final url = '${m?['browser_download_url'] ?? ''}'.trim();
      // 通用包可用于所有支持的 ABI；其余情况由发布页提供选择。
      if (name.endsWith('-universal.apk') && url.isNotEmpty) {
        apkUrl = url;
        break;
      }
    }
    final tag = '${data['tag_name'] ?? ''}';
    return UpdateResult(
      configured: true,
      latestVersion: tag.isEmpty ? null : tag.replaceFirst(RegExp(r'^v'), ''),
      latestName: '${data['name'] ?? ''}',
      changelog: '${data['body'] ?? ''}'.trim(),
      htmlUrl: '${data['html_url'] ?? fallbackUrl ?? _downloadBase}',
      apkUrl: apkUrl?.isEmpty == true ? null : apkUrl,
    );
  }
}