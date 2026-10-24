import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android stores this value atomically in noBackupFilesDir, outside settings.
class CredentialStore {
  CredentialStore._();
  static final instance = CredentialStore._();
  static const _channel = MethodChannel('abts/credentials');
  Future<void> _writes = Future<void>.value();

  Future<String?> load() async {
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
    final next = _writes.then((_) async {
      final ok = await _channel.invokeMethod<bool>('write', cookie);
      if (ok != true) throw StateError('Credential storage unavailable');
    });
    _writes = next.catchError((Object _) {});
    return next;
  }
}
