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

  bool get hasNewer => isNewerThan(AppMeta.version);

  bool isNewerThan(String currentVersion) {
    if (!configured || error != null) return false;
    final current = _stableVersion(currentVersion);
    final latest = _stableVersion(latestVersion ?? '');
    if (current == null || latest == null) return false;
    for (var i = 0; i < current.length; i++) {
      if (latest[i] != current[i]) return latest[i] > current[i];
    }
    return false;
  }
}

/// Only three-part stable release versions are offered by the updater.
List<int>? _stableVersion(String value) {
  if (!RegExp(
    r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
  ).hasMatch(value)) {
    return null;
  }
  final parts = value.replaceFirst(RegExp(r'^v'), '').split('.');
  final numbers = parts.map(int.tryParse).toList();
  return numbers.contains(null) ? null : numbers.cast<int>();
}

class AppUpdate {
  AppUpdate._();

  /// GitHub 仓库（检查更新数据源）
  static const String githubOwner = 'AtomHH86';
  static const String githubRepo = 'Blisten';

  static bool get configured => githubOwner.isNotEmpty && githubRepo.isNotEmpty;

  /// 未配置仓库时不创建客户端；检查有整体时限并释放连接。
  static Future<UpdateResult> check({
    String owner = githubOwner,
    String repo = githubRepo,
    Dio Function()? createClient,
  }) async {
    if (owner.isEmpty || repo.isEmpty) {
      return const UpdateResult(configured: false);
    }
    Dio? client;
    try {
      client = (createClient ?? Dio.new)();
      client.options
        ..connectTimeout = const Duration(seconds: 10)
        ..sendTimeout = const Duration(seconds: 10)
        ..receiveTimeout = const Duration(seconds: 10);
      final resp = await client
          .get(
            'https://api.github.com/repos/$owner/$repo/releases/latest',
            options: Options(
              headers: {'Accept': 'application/vnd.github+json'},
              responseType: ResponseType.json,
            ),
          )
          .timeout(const Duration(seconds: 15));
      return parseRelease(
        resp.data is Map ? resp.data as Map : const {},
        owner: owner,
        repo: repo,
      );
    } catch (_) {
      return const UpdateResult(configured: true, error: '检查更新失败，请稍后重试');
    } finally {
      client?.close(force: true);
    }
  }

  /// 解析正式版本，仅接受同仓库的 HTTPS 发布页和通用 APK。
  static UpdateResult parseRelease(
    Map data, {
    String? fallbackUrl,
    String owner = githubOwner,
    String repo = githubRepo,
  }) {
    final tag = '${data['tag_name'] ?? ''}';
    if (data['draft'] == true ||
        data['prerelease'] == true ||
        _stableVersion(tag) == null) {
      return const UpdateResult(configured: true, error: '更新信息无效，请稍后重试');
    }
    Uri? trustedUri(Object? raw) {
      final uri = Uri.tryParse('$raw'.trim());
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          uri.userInfo.isNotEmpty ||
          uri.port != 443 ||
          uri.hasFragment) {
        return null;
      }
      final parts = uri.pathSegments;
      if (parts.length < 4 ||
          parts[0] != owner ||
          parts[1] != repo ||
          parts[2] != 'releases' ||
          parts.contains('..')) {
        return null;
      }
      return uri;
    }

    String? releasePage(Object? raw) {
      final uri = trustedUri(raw);
      if (uri == null) return null;
      final parts = uri.pathSegments;
      return (parts.length == 4 && parts[3] == 'latest') ||
              (parts.length == 5 && parts[3] == 'tag' && parts[4].isNotEmpty)
          ? uri.toString()
          : null;
    }

    String? apkUrl;
    final assets = data['assets'];
    for (final asset in assets is List ? assets : const []) {
      if (asset is! Map) continue;
      final name = '${asset['name'] ?? ''}';
      final uri = trustedUri(asset['browser_download_url']);
      if (!name.endsWith('-universal.apk') || uri == null) continue;
      final parts = uri.pathSegments;
      if (parts.length == 6 &&
          parts[3] == 'download' &&
          parts[4] == tag &&
          parts[5] == name) {
        apkUrl = uri.toString();
        break;
      }
    }
    return UpdateResult(
      configured: true,
      latestVersion: tag.replaceFirst(RegExp(r'^v'), ''),
      latestName: '${data['name'] ?? ''}',
      changelog: '${data['body'] ?? ''}'.trim(),
      htmlUrl:
          releasePage(data['html_url']) ??
          releasePage(fallbackUrl) ??
          'https://github.com/$owner/$repo/releases/latest',
      apkUrl: apkUrl,
    );
  }
}
