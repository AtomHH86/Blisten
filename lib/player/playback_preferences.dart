import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_mode.dart';

/// 各类内容分别保存倍速；听书沿用旧键，兼容已有用户设置。
class PlaybackPreferences {
  String _rateKey(ContentMode mode) => switch (mode) {
    ContentMode.audiobook => 'abts_rate',
    ContentMode.music => 'abts_rate_music',
    ContentMode.concert => 'abts_rate_concert',
    ContentMode.children => 'abts_rate_children',
  };

  Future<double> rateFor(ContentMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(_rateKey(mode));
    return value != null && value >= 0.5 && value <= 3.0 ? value : 1.0;
  }

  Future<void> saveRate(ContentMode mode, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_rateKey(mode), value.clamp(0.5, 3.0));
  }

  /// 仅用于重新选择作品/缓存入口；暂停、拖动和重连不经过此规则。
  static ({int index, int positionMs}) selectionStart(
    ContentMode mode, {
    required int index,
    required int positionMs,
    bool explicitPart = false,
  }) => (
    index: mode.resumesPosition || explicitPart ? index : 0,
    positionMs: mode.resumesPosition ? positionMs : 0,
  );
}
