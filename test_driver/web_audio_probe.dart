import 'dart:async';

import 'package:blisten/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 独立本机验证入口：flutter build web -t test_driver/web_audio_probe.dart
/// 测试音频由 tool/generate-web-probe-audio.py 生成到 Web 输出目录。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(MaterialApp(
    title: 'B听 · Web 音频验证',
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: const _WebAudioProbe(),
  ));
}

class _WebAudioProbe extends StatefulWidget {
  const _WebAudioProbe();

  @override
  State<_WebAudioProbe> createState() => _WebAudioProbeState();
}

class _WebAudioProbeState extends State<_WebAudioProbe> {
  static const _positionKey = 'blisten_web_probe_position_ms';
  final _player = Player();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _opened = false;
  bool _working = false;
  bool _readingSaved = true;
  double _rate = 1;
  int? _lastSaved;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _player.stream.duration.listen((value) {
        if (mounted) setState(() => _duration = value);
      }),
      _player.stream.position.listen((value) {
        if (mounted) setState(() => _position = value);
      }),
      _player.stream.playing.listen((value) {
        if (mounted) setState(() => _playing = value);
      }),
      _player.stream.rate.listen((value) {
        if (mounted) setState(() => _rate = value);
      }),
      _player.stream.error.listen((value) {
        if (mounted) setState(() => _error = '音频播放失败：$value');
      }),
    ]);
    unawaited(_readSavedPosition());
  }

  Future<void> _readSavedPosition() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _lastSaved = preferences.getInt(_positionKey));
    } catch (error) {
      if (mounted) setState(() => _error = '读取测试进度失败：$error');
    } finally {
      if (mounted) setState(() => _readingSaved = false);
    }
  }

  Future<void> _run(String action, Future<void> Function() operation) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      // 在按钮点击时直接调用，保留浏览器的用户播放手势。
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = '$action失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openAndPlay() async {
    await _player.open(Media(Uri.base.resolve('generated-probe.wav').toString()));
    if (mounted) setState(() => _opened = true);
  }

  Future<void> _savePosition() async {
    final positionMs = _position.inMilliseconds;
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setInt(_positionKey, positionMs);
    if (!saved) throw StateError('浏览器未保存测试进度');
    if (mounted) setState(() => _lastSaved = positionMs);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _opened && !_working;
    return Scaffold(
      appBar: AppBar(title: const Text('B听 · Web 音频验证')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(child: Image.asset('assets/logo.png', width: 72, height: 72,
                  semanticLabel: 'B听')),
              const SizedBox(height: 16),
              Text('本机合成测试音频', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('60 秒低音量正弦波，文件名 generated-probe.wav。'
                  '点击按钮开始播放；刷新页面只显示已保存的测试进度。'),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _working ? null : () => _run('打开并播放', _openAndPlay),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('打开并播放测试音频'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: enabled ? () => _run('暂停', _player.pause) : null,
                    child: const Text('暂停'),
                  ),
                  OutlinedButton(
                    onPressed: enabled ? () => _run('跳转',
                        () => _player.seek(const Duration(seconds: 30))) : null,
                    child: const Text('跳到 30 秒'),
                  ),
                  OutlinedButton(
                    onPressed: enabled ? () => _run('调整倍速',
                        () => _player.setRate(1.5)) : null,
                    child: const Text('设为 1.5 倍速'),
                  ),
                  OutlinedButton(
                    onPressed: enabled && !_readingSaved
                        ? () => _run('保存测试进度', _savePosition) : null,
                    child: const Text('保存当前测试进度'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'duration_ms: ${_duration.inMilliseconds}\n'
                    'position_ms: ${_position.inMilliseconds}\n'
                    'playing: $_playing\n'
                    'rate: ${_rate.toStringAsFixed(1)}\n'
                    'opened: $_opened\n'
                    'lastSaved_ms: ${_readingSaved ? "读取中" : _lastSaved ?? "未保存"}',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
