import 'package:flutter/services.dart';

/// Android's native decoder needs an explicit trust bundle and TLS verification.
class NativeAudioTls {
  static const _channel = MethodChannel('blisten/native_tls');

  static Future<void> configure({
    required Future<void> Function(String, String) setProperty,
    required Future<String> Function(String) getProperty,
  }) async {
    // Preserve an explicitly configured verifying player, including the
    // isolated CA installed by integration tests. No certificate bypass exists.
    if (await getProperty('tls-verify') == 'yes' &&
        (await getProperty('tls-ca-file')).trim().isNotEmpty) {
      return;
    }
    await setProperty('tls-verify', 'yes');
    // media_kit's setProperty does not surface libmpv's return code.
    if (await getProperty('tls-verify') != 'yes') {
      throw StateError('无法启用音频连接证书校验');
    }
    final caFile = await _channel.invokeMethod<String>('trustedCaFile');
    if (caFile == null || caFile.trim().isEmpty) {
      throw StateError('无法加载系统信任证书');
    }
    await setProperty('tls-ca-file', caFile);
    if (await getProperty('tls-ca-file') != caFile) {
      throw StateError('无法配置音频连接证书');
    }
  }
}
