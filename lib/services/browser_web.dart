import 'dart:js_interop';

@JS('window.open')
external _BrowserWindow? _openWindow(String url, String target);

extension type _BrowserWindow._(JSObject _) implements JSObject {
  external set opener(JSAny? value);
  external _BrowserLocation get location;
  external void close();
}

extension type _BrowserLocation._(JSObject _) implements JSObject {
  external void replace(String url);
}

Future<bool> openBrowser(String url) async {
  // Open synchronously while the user's click still grants popup permission.
  // Detach the opener before navigating, while keeping popup-block detection.
  final window = _openWindow('about:blank', '_blank');
  if (window == null) return false;
  try {
    window.opener = null;
    window.location.replace(url);
    return true;
  } catch (_) {
    window.close();
    return false;
  }
}
