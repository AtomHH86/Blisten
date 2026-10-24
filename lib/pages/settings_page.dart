import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../services/auth_store.dart';
import '../services/device_service.dart';
import 'login_page.dart';

/// 设置（独立页面）：账号信息 + 播放与后台。未登录也可进入
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  bool _loading = true;
  bool _ignoring = false;
  bool _requesting = false;
  int _refreshId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final requestId = ++_refreshId;
    setState(() => _loading = true);
    final v = await DeviceService.instance.isIgnoringBatteryOptimizations();
    if (!mounted || requestId != _refreshId) return;
    setState(() {
      _ignoring = v;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    if (_requesting) return;
    if (value) {
      final route = ModalRoute.of(context);
      setState(() => _requesting = true);
      try {
        await DeviceService.instance.requestIgnoreBatteryOptimization();
        if (!mounted) return;
        await _refresh();
        if (!mounted || _loading || route?.isCurrent != true) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_ignoring
                ? '已开启后台留存保护'
                : '请在系统弹窗中允许「不受限制」'),
          ),
        );
      } finally {
        if (mounted) setState(() => _requesting = false);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('如需关闭，请在系统电池设置中恢复限制')),
      );
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('退出登录',
            style: TextStyle(color: AppTheme.textMain, fontSize: 20)),
        content: Text(
          '退出后需要重新扫码登录，收藏与收听进度仍保留在本机。',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('退出', style: TextStyle(color: AppTheme.actionText)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LoginStore.instance.markLoggedOut();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出登录')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<LoginStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('系统设置')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          _buildAccountCard(auth),
          const SizedBox(height: 12),
          _sectionTitle('播放与后台'),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
          SwitchListTile(
            value: _ignoring,
            onChanged: _loading || _requesting ? null : _toggle,
            activeThumbColor: AppTheme.onPrimary,
            secondary:
                Icon(Icons.battery_saver_rounded, color: AppTheme.actionText),
            title: Text(
              '后台留存保护',
              style: TextStyle(fontSize: 16, color: AppTheme.textMain),
            ),
            subtitle: Text(
              _loading
                  ? '检测中…'
                  : _ignoring
                      ? '已豁免电池优化，退到后台更不易被系统清理'
                      : '未开启，长时间后台播放可能被系统中断',
              style: TextStyle(fontSize: 14, color: AppTheme.textSub),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Text(
                '播放时应用会以前台服务常驻（通知栏可见），熄屏/锁屏也能继续听。'
                '开启「后台留存保护」可进一步降低被清理的概率。\n\n'
                '若仍被中断，建议在系统设置中为本应用打开「自启动」并设置「无限制」后台策略。',
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textSub, height: 1.6),
              ),
            ),
          ),
          ] else
            ListTile(
              leading: const Icon(Icons.headphones_rounded),
              title: Text(kIsWeb ? '网页版预览' : 'iOS 预览版'),
              subtitle: Text(kIsWeb
                  ? '在线播放仍在验证。切换后台或锁屏后，播放可能受浏览器限制。暂不支持登录和音频离线缓存。'
                  : '在线播放尚未开放。后台与锁屏收听将在 iPhone 真机测试通过后开放。'),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppTheme.textMain,
        ),
      ),
    );
  }

  /// 账号信息：未登录显示登录入口，已登录显示昵称头像与退出登录
  Widget _buildAccountCard(LoginStore auth) {
    if (kIsWeb) {
      return const ListTile(
        leading: Icon(Icons.person_outline_rounded),
        title: Text('匿名收听'),
        subtitle: Text('网页版暂不支持 B 站账号登录。收藏与进度只保存在此浏览器，不会自动同步到其他设备。'),
      );
    }
    final logged = auth.isLogin;
    final action = (logged || auth.status == LoginStatus.unverified)
        ? OutlinedButton(
            onPressed: _logout,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSub,
              side: BorderSide(color: AppTheme.outline),
            ),
            child: const Text('退出登录', style: TextStyle(fontSize: 14)),
          )
        : FilledButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
            child: const Text('登录', style: TextStyle(fontSize: 14)),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final profile = Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surfaceHigh,
                    border: Border.all(color: AppTheme.divider),
                    image: logged && auth.userFace.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(auth.userFace),
                            fit: BoxFit.cover,
                            onError: (_, _) {},
                          )
                        : null,
                  ),
                  child: !logged || auth.userFace.isEmpty
                      ? Icon(Icons.person_rounded, size: 28, color: AppTheme.actionText)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        logged
                            ? (auth.userName.isEmpty ? 'B 站用户' : auth.userName)
                            : switch (auth.status) {
                                LoginStatus.expired => '登录已失效',
                                LoginStatus.unverified => '登录待验证',
                                _ => '未登录',
                              },
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        switch (auth.status) {
                          LoginStatus.verified => '已登录',
                          LoginStatus.expired => '请重新扫码登录',
                          LoginStatus.unverified => '暂时无法验证，请检查网络',
                          LoginStatus.loggedOut => '登录后可同步昵称与头像',
                        },
                        style: TextStyle(fontSize: 14, color: AppTheme.textSub),
                      ),
                    ],
                  ),
                ),
              ],
            );
            if (constraints.maxWidth < 320 ||
                MediaQuery.textScalerOf(context).scale(16) > 20) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  profile,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: profile),
                const SizedBox(width: 12),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}
