import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Native credentials are isolated from settings; the web client stays anonymous.
class CredentialStore {
  CredentialStore._();
  static final instance = CredentialStore._();
  static const _channel = MethodChannel('abts/credentials');
  Future<void> _writes = Future<void>.value();

  Future<String?> load() async {
    if (kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    final saved = await _channel.invokeMethod<String>('read');
    final legacy = prefs.getString('bili_cookie');
    if (saved == null && legacy != null && legacy.isNotEmpty) {
      await write(legacy);
    }
    // Never remove the only durable copy until the isolated write succeeded.
    if (legacy != null) await prefs.remove('bili_cookie');
    return saved ?? legacy;
  }

  Future<void> write(String? cookie) {
    if (kIsWeb) {
      if (cookie == null || cookie.isEmpty) return Future<void>.value();
      return Future<void>.error(UnsupportedError('网页版暂不支持保存登录凭据'));
    }
    final next = _writes.then((_) async {
      final ok = await _channel.invokeMethod<bool>('write', cookie);
      if (ok != true) throw StateError('Credential storage unavailable');
    });
    _writes = next.catchError((Object _) {});
    return next;
  }
}
