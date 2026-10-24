import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// 与后台媒体引擎同寿命的原生焦点通道；迟到事件按请求号隔离。
class AudioFocus {
  AudioFocus._();
  static final AudioFocus instance = AudioFocus._();

  static const _method = MethodChannel('abts/audio_focus');
  static const _events = EventChannel('abts/audio_focus_events');
  StreamSubscription<dynamic>? _sub;
  int _requestId = 0;
  int _lossRevision = 0;
  bool _granted = false;
  bool _speech = false;
  Completer<bool>? _pending;

  void Function()? onFocusLost;
  void Function()? onFocusInterrupted;
  void Function()? onFocusDucked;
  void Function()? onFocusGained;
  void Function()? onNoisy;

  bool get _nativeFocus => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool get hasFocus => !_nativeFocus || _granted;
  bool get waiting => _pending != null;
  bool get pausesOnDuck => _speech;

  void start() {
    if (_sub != null || !_nativeFocus) return;
    _sub = _events.receiveBroadcastStream().listen((value) {
      if (value is! Map || value['requestId'] != _requestId) return;
      switch (value['event']) {
        case 'gained':
          _granted = true;
          _finish(true);
          onFocusGained?.call();
        case 'lost':
          ++_lossRevision;
          _granted = false;
          _finish(false);
          onFocusLost?.call();
        case 'interrupted':
          ++_lossRevision;
          _granted = false;
          onFocusInterrupted?.call();
        case 'ducked':
          if (_speech) {
            ++_lossRevision;
            _granted = false;
          }
          onFocusDucked?.call();
        case 'noisy':
          onNoisy?.call();
      }
    }, onError: (Object _) {
      _granted = false;
      _finish(false);
      onFocusLost?.call();
    });
  }

  void _finish(bool granted) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(granted);
  }

  /// delayed 保持等待；只有真实 GAIN 才放行。取消和原生通道故障均不放行。
  Future<bool> request({bool speech = false}) async {
    if (!_nativeFocus) return true;
    start();
    if (_speech == speech) {
      if (_granted) return true;
      final pending = _pending;
      if (pending != null) return pending.future;
    }
    _finish(false);
    final id = ++_requestId;
    _speech = speech;
    _granted = false;
    final pending = Completer<bool>();
    _pending = pending;
    final lossRevision = _lossRevision;
    try {
      final result = await _method.invokeMethod<Object>('request',
          {'requestId': id, 'speech': speech});
      if (id != _requestId) return false;
      if (result == 'granted') {
        // 原生事件可能先于 request 的回复到达；旧回复不能抹掉新的打断。
        if (lossRevision == _lossRevision) _granted = true;
        if (_granted) _finish(true);
      } else if (result != 'delayed') {
        _finish(false);
      }
    } catch (_) {
      if (id == _requestId) _finish(false);
    }
    return pending.future;
  }

  Future<void> abandon() async {
    final oldId = _requestId;
    ++_requestId;
    _granted = false;
    _finish(false);
    if (!_nativeFocus) return;
    try {
      await _method.invokeMethod<void>('abandon', {'requestId': oldId});
    } catch (_) {}
  }
}
