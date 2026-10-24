import 'browser_native.dart'
    if (dart.library.js_interop) 'browser_web.dart' as platform;

/// 打开外部网页；原生使用系统浏览器，Web 使用独立窗口。
class Browser {
  Browser._();

  /// 仅接受具有主机名的 HTTP(S) 地址，失败时由调用方提示复制链接。
  static Future<bool> open(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority || uri.host.isEmpty) {
      return false;
    }
    return platform.openBrowser(uri.toString());
  }
}
