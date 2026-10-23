import 'package:dio/dio.dart';

import '../core/network/api_config.dart';

/// 导入保存作品标识；只有链接显式指定 p 时才覆盖正常续播位置。
class BiliResource {
  final String bvid;
  final int page;
  final bool hasExplicitPage;

  const BiliResource({required this.bvid, int? page})
    : page = page ?? 1,
      hasExplicitPage = page != null;
}

class BiliResourceResolver {
  final Dio _dio;
  BiliResourceResolver({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 12),
            ),
          );

  static final _bv = RegExp(r'^BV[0-9A-Za-z]{10}$');
  static final _url = RegExp(r'''https?://[^\s<>"'【】]+''');
  static const _videoHosts = {
    'bilibili.com',
    'www.bilibili.com',
    'm.bilibili.com',
  };

  Future<BiliResource> resolve(String input) async {
    final text = input.trim();
    if (_bv.hasMatch(text)) return BiliResource(bvid: text);
    var link = _url.firstMatch(text)?.group(0);
    // 地址栏复制的链接有时省略协议。
    if (link == null &&
        (text.startsWith('bilibili.com/') ||
            text.startsWith('www.bilibili.com/') ||
            text.startsWith('m.bilibili.com/') ||
            text.startsWith('b23.tv/'))) {
      link = 'https://$text';
    }
    if (link == null) throw const FormatException('请输入有效的 B 站视频链接或完整 BV 号');
    link = link.replaceFirst(RegExp(r'[),.;!?，。！？；）]+$'), '');
    var uri = Uri.tryParse(link);
    for (var hop = 0; hop < 5; hop++) {
      if (uri == null || !_trusted(uri)) {
        throw const FormatException('仅支持 B 站视频链接和 b23.tv 短链接');
      }
      if (_videoHosts.contains(uri.host)) return _fromVideo(uri);
      // 手动处理重定向，确保短链不会把请求带到其它站点。
      final response = await _dio.get<dynamic>(
        uri.toString(),
        options: Options(
          followRedirects: false,
          responseType: ResponseType.plain,
          headers: {'User-Agent': BiliEndpoints.userAgent},
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
      );
      final location = response.headers.value('location');
      if (location == null || location.isEmpty) {
        throw const FormatException('短链接未指向有效视频，请复制完整视频链接重试');
      }
      uri = uri.resolve(location);
    }
    throw const FormatException('短链接跳转过多，请复制完整视频链接重试');
  }

  static bool _trusted(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == (uri.scheme == 'https' ? 443 : 80)) &&
      (_videoHosts.contains(uri.host) || uri.host == 'b23.tv');

  static BiliResource _fromVideo(Uri uri) {
    final parts = uri.pathSegments;
    if (parts.length < 2 || parts[0] != 'video' || !_bv.hasMatch(parts[1])) {
      throw const FormatException('该链接不是可识别的 BV 视频链接');
    }
    final page = int.tryParse(uri.queryParameters['p'] ?? '');
    return BiliResource(
      bvid: parts[1],
      page: page != null && page > 0 ? page : null,
    );
  }
}
