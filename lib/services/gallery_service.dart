import 'dart:io';

import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// 保存图片到系统相册（走 MainActivity 原生通道，无需额外插件）
class GalleryService {
  GalleryService._();

  static const _channel = MethodChannel('abts/gallery');

  static int? _sdkInt;

  /// Android API 等级（仅 Android 有意义）
  static Future<int> sdkInt() async {
    if (!(!kIsWeb && Platform.isAndroid)) return 0;
    _sdkInt ??= await _channel.invokeMethod<int>('sdkInt') ?? 0;
    return _sdkInt!;
  }

  /// 保存 PNG 字节到相册；成功返回 true
  static Future<bool> savePng(Uint8List bytes, {required String name}) async {
    if (!(!kIsWeb && Platform.isAndroid)) return false;
    try {
      final sdk = await sdkInt();
      if (sdk <= 0) return false;
      // Android 9 及以下需要写存储权限（10+ 走 MediaStore 无需权限）。
      if (sdk < 29) {
        final status = await Permission.storage.request();
        if (!status.isGranted) return false;
      }
      final path = await _channel.invokeMethod<String>('saveImage', {
        'base64': base64Encode(bytes),
        'name': name,
      });
      return path != null && path.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
