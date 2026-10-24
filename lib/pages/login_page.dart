import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/theme/app_theme.dart';
import '../core/network/bili_client.dart';
import '../services/auth_store.dart';
import '../services/bili_api.dart';
import '../services/gallery_service.dart';

/// B 站二维码登录页：生成二维码 → 前台轮询 → 成功后写入 Cookie 并持久化
class LoginPage extends StatefulWidget {
  final BiliApi? api;
  const LoginPage({super.key, this.api});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _api = widget.api ?? BiliApi.instance;
  final _qrBoundaryKey = GlobalKey();

  bool _generating = true;
  bool _saving = false;
  bool _polling = false;
  bool _pollFailed = false;
  int _generation = 0;
  String? _qrContent;
  String? _qrKey;
  String _status = '';
  Timer? _timer;
  bool _destroyed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || context.read<LoginStore>().isLogin) return;
      _generate();
    });
  }

  @override
  void dispose() {
    _destroyed = true;
    BiliClient.instance.invalidateSessionRequests();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    _timer?.cancel();
    final generation = ++_generation;
    BiliClient.instance.invalidateSessionRequests();
    setState(() {
      _generating = true;
      _pollFailed = false;
      _qrContent = null;
      _qrKey = null;
      _status = '';
    });
    try {
      final qr = await _api.qrGenerate();
      if (_destroyed || generation != _generation) return;
      setState(() {
        _qrContent = qr.url;
        _qrKey = qr.qrKey;
        _generating = false;
        _status = '使用哔哩哔哩 App 扫码登录';
      });
      _startPolling();
    } catch (e) {
      if (_destroyed || generation != _generation) return;
      setState(() {
        _generating = false;
        _status = '二维码获取失败，请点击刷新';
      });
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _poll() async {
    final key = _qrKey;
    if (key == null || _qrContent == null || _polling) return;
    final generation = _generation;
    final session = BiliClient.instance.sessionGeneration;
    _polling = true;
    String state;
    try {
      state = await _api.qrPoll(key);
    } catch (_) {
      if (_destroyed || generation != _generation) return;
      _timer?.cancel();
      setState(() {
        _pollFailed = true;
        _status = '登录状态检查失败，请重试或刷新二维码';
      });
      return;
    } finally {
      _polling = false;
    }
    // A successful real QR response advances the account generation once.
    final acceptedSession = state == 'success' ? session + 1 : session;
    if (_destroyed || generation != _generation ||
        acceptedSession != BiliClient.instance.sessionGeneration) {
      return;
    }
    setState(() => _pollFailed = false);
    switch (state) {
      case 'success':
        _timer?.cancel();
        await LoginStore.instance.refreshFromNav();
        if (_destroyed || generation != _generation ||
            acceptedSession != BiliClient.instance.sessionGeneration) {
          return;
        }
        if (!LoginStore.instance.isLogin) {
          setState(() => _status = '暂时无法验证登录，请重试');
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登录成功，欢迎回来')),
        );
        Navigator.of(context).pop(true);
      case 'scanned':
        setState(() => _status = '已扫码，请在手机上点击确认');
      case 'expired':
        _timer?.cancel();
        setState(() {
          _status = '二维码已过期，请刷新';
          _qrContent = null;
        });
      case 'waiting':
        setState(() => _status = '使用哔哩哔哩 App 扫码登录');
    }
  }

  /// 保存当前二维码到相册，方便用其他设备扫码
  Future<void> _saveQr() async {
    final data = _qrContent;
    final messenger = ScaffoldMessenger.of(context);
    if (data == null || data.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('二维码还没生成，请先刷新')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      // 直接截取页面上的二维码（白底，避免透明底在相册里扫不出）
      final boundary =
          _qrBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('二维码未就绪');
      final box = boundary.size;
      final ratio = box.width <= 0 ? 3.0 : (900 / box.width).clamp(2.0, 8.0);
      final image = await boundary.toImage(pixelRatio: ratio);
      debugPrint('[LoginPage] qr box=${box.width}x${box.height} '
          'ratio=$ratio out=${image.width}x${image.height}');
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('二维码编码失败');
      final ok = await GalleryService.savePng(
        bytes.buffer.asUint8List(),
        name: 'bili_qr_${DateTime.now().millisecondsSinceEpoch}',
      );
      messenger.showSnackBar(
        SnackBar(content: Text(ok ? '二维码已保存到相册' : '保存失败，请检查存储权限')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('保存失败，请稍后重试')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账号')),
      body: _buildLogin(),
    );
  }

  Widget _buildLogin() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 8),
        Icon(Icons.headset_rounded, size: 44, color: AppTheme.actionText),
        const SizedBox(height: 12),
        Text(
          '登录 B 站账号',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMain,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '登录后可同步你的昵称与头像',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppTheme.textSub, height: 1.5),
        ),
        const SizedBox(height: 28),
        Center(
          child: RepaintBoundary(
            key: _qrBoundaryKey,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: _generating
                  ? const SizedBox(
                      width: 200,
                      height: 200,
                      child: Center(
                        child:
                            CircularProgressIndicator(color: AppTheme.accent),
                      ),
                    )
                  : _qrContent == null
                      ? SizedBox(
                          width: 200,
                          height: 200,
                          child: Center(
                            child: Icon(Icons.qr_code_2_rounded,
                                size: 72, color: AppTheme.textHint),
                          ),
                        )
                      : QrImageView(
                          data: _qrContent!,
                          version: QrVersions.auto,
                          size: 200,
                          backgroundColor: Colors.white,
                        ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _status,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13,
              color: _pollFailed ? AppTheme.error : AppTheme.textSub),
        ),
        if (_pollFailed) Center(
          child: TextButton(
            onPressed: () {
              _startPolling();
              _poll();
            },
            child: const Text('重试'),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _generating ? null : _generate,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('刷新二维码'),
              ),
              OutlinedButton.icon(
                onPressed: (_generating || _saving || _qrContent == null) ? null : _saveQr,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                label: const Text('保存到相册'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '登录即代表同意哔哩哔哩用户协议',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppTheme.textHint),
        ),
      ],
    );
  }
}