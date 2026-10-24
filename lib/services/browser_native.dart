import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('abts/browser');

Future<bool> openBrowser(String url) async {
  if (!Platform.isAndroid && !Platform.isIOS) return false;
  try {
    return await _channel.invokeMethod<bool>('open', {'url': url}) ?? false;
  } catch (_) {
    return false;
  }
}
