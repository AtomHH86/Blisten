import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_meta.dart';
import '../core/theme/app_theme.dart';
import '../services/app_update.dart';
import '../services/browser.dart';

/// 首页加载完成后的更新检查宿主，保留在主题重建范围之外。
class AppUpdatePrompt extends StatefulWidget {
  const AppUpdatePrompt({
    super.key,
    required this.child,
    this.checkForUpdate,
    this.now,
    this.openUrl,
  });

  final Widget child;
  final Future<UpdateResult> Function()? checkForUpdate;
  final DateTime Function()? now;
  final Future<bool> Function(String)? openUrl;

  static Future<void> checkManually(BuildContext context) {
    final state = context.findAncestorStateOfType<_AppUpdatePromptState>();
    if (state == null) {
      throw StateError('Update action requires AppUpdatePrompt');
    }
    return state._check(manual: true);
  }

  @override
  State<AppUpdatePrompt> createState() => _AppUpdatePromptState();
}

class _AppUpdatePromptState extends State<AppUpdatePrompt>
    with WidgetsBindingObserver {
  static const _lastSuccessKey = 'blisten_update_last_success_ms';
  bool _checking = false;
  bool _manualRequested = false;
  bool _dialogOpen = false;
  UpdateResult? _pending;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _progress;

  DateTime get _now => (widget.now ?? DateTime.now)();
  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  bool get _canPresent =>
      mounted && _foreground && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Runs once for this app session, after the usable home page is rendered.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAutomatically());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_showPending());
  }

  Future<void> _checkAutomatically() async {
    if (mounted) await _check(manual: false);
  }

  Future<void> _check({required bool manual}) async {
    if (!mounted || _dialogOpen) return;
    if (manual) {
      _manualRequested = true;
      if (_canPresent) {
        _progress ??= ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在检查更新…'),
            duration: Duration(seconds: 20),
          ),
        );
      }
    }
    // Manual taps can join the ongoing automatic request, including its result.
    if (_checking) return;
    _checking = true;
    UpdateResult result;
    try {
      result = await (widget.checkForUpdate ?? AppUpdate.check)();
    } catch (_) {
      result = const UpdateResult(configured: true, error: '检查更新失败，请稍后重试');
    }
    if (result.configured &&
        result.error == null &&
        result.latestVersion != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_lastSuccessKey, _now.millisecondsSinceEpoch);
      } catch (_) {
        // A successful check remains usable when its timestamp cannot be saved.
      }
    }
    _checking = false;
    final report = _manualRequested;
    _manualRequested = false;
    if (!mounted) return;
    _progress?.close();
    _progress = null;
    if (result.hasNewer) {
      setState(() => _pending = result);
      await _showPending();
    } else if (report && _canPresent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !result.configured
                ? '暂未配置更新源'
                : result.error ?? '已是最新版本 ${AppMeta.version}',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _showPending() async {
    if (_pending == null || _dialogOpen || _checking || !_canPresent) return;
    final result = _pending!;
    _pending = null;
    _dialogOpen = true;
    final target = result.apkUrl ?? result.htmlUrl;
    try {
      final download = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.surface,
          scrollable: true,
          title: Text(
            result.latestName?.isNotEmpty == true
                ? result.latestName!
                : '发现新版本 ${result.latestVersion}',
            style: TextStyle(color: AppTheme.textMain, fontSize: 20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前版本 ${AppMeta.version} · 最新 ${result.latestVersion}',
                style: TextStyle(color: AppTheme.textSub, fontSize: 14),
              ),
              if ((result.changelog ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '更新内容：\n${result.changelog}',
                  style: TextStyle(
                    color: AppTheme.textSub,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('稍后', style: TextStyle(color: AppTheme.textSub)),
            ),
            if (target != null && target.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  '下载更新',
                  style: TextStyle(color: AppTheme.actionText),
                ),
              ),
          ],
        ),
      );
      if (download == true && target != null && mounted) {
        final opened = await (widget.openUrl ?? Browser.open)(target);
        if (!opened) {
          await Clipboard.setData(ClipboardData(text: target));
          if (mounted && _foreground) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('下载链接已复制\n$target'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ModalRoute changes when a pushed page is popped; defer until its next frame.
    final current = ModalRoute.of(context)?.isCurrent == true;
    if (current && _pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPending());
    }
    return widget.child;
  }
}
