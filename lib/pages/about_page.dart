import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_meta.dart';
import '../core/theme/app_theme.dart';
import '../services/browser.dart';

/// 关于我们：应用介绍 + 开源/官网快捷入口 + 免责声明
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于我们')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _buildLogo(context),
          const SizedBox(height: 14),
          Text(
            AppMeta.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppMeta.tagline,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.textSub),
          ),
          const SizedBox(height: 4),
          Text(
            '版本 ${AppMeta.version}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textHint),
          ),
          const SizedBox(height: 22),
          _buildIntro(context),
          const SizedBox(height: 14),
          _buildLinks(context),
          const SizedBox(height: 14),
          _buildDisclaimer(context),
          const SizedBox(height: 18),
          Center(
            child: Text(
              '感谢每一位反馈问题的你',
              style: TextStyle(fontSize: 12, color: AppTheme.textHint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    return Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset(
            'assets/logo.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(
              color: AppTheme.surfaceHigh,
              child: Icon(Icons.headset_rounded, size: 40, color: AppTheme.actionText),
            ),
          ),
        ),
      ),
    );
  }

  /// 一句话讲清它是干什么的
  Widget _buildIntro(BuildContext context) {
    const points = [
      '搜索有声书、歌曲与演唱会，也可粘贴 B 站链接或 BV 号添加内容',
      '支持后台与熄屏播放、定时停止、分 P 连播和离线缓存',
      '听书与现场可续播；歌曲再次选择从头播放，三种模式独立记忆倍速',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.actionText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSub,
                        height: 1.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 快捷跳转：开源仓库 / 官网 / 问题反馈 / 协议
  Widget _buildLinks(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          _linkTile(
            context,
            icon: Icons.code_rounded,
            title: '开源仓库',
            subtitle: '源码、构建说明与版本发布',
            url: AppMeta.repoUrl,
          ),
          _divider(),
          _linkTile(
            context,
            icon: Icons.language_rounded,
            title: '官方网站',
            subtitle: '功能介绍与下载入口',
            url: AppMeta.siteUrl,
          ),
          _divider(),
          _linkTile(
            context,
            icon: Icons.bug_report_outlined,
            title: '问题反馈',
            subtitle: '遇到问题或想要新功能，欢迎提 Issue',
            url: AppMeta.issuesUrl,
          ),
          _divider(),
          _linkTile(
            context,
            icon: Icons.history_rounded,
            title: '原项目：阿B听书',
            subtitle: 'B听基于阿B听书修改，感谢原作者与贡献者',
            url: AppMeta.upstreamUrl,
          ),
          _divider(),
          _linkTile(
            context,
            icon: Icons.balance_rounded,
            title: '开源协议',
            subtitle: 'MIT License · 保留原作者版权声明',
            url: AppMeta.licenseUrl,
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 56);

  Widget _linkTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
  }) {
    return InkWell(
      onTap: url.isEmpty ? null : () => _open(context, url, title),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: AppTheme.actionText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    url.isEmpty ? '尚未配置 B听的对应入口' : subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                  ),
                ],
              ),
            ),
            if (url.isNotEmpty)
              Icon(Icons.open_in_new_rounded, size: 16, color: AppTheme.textHint),
          ],
        ),
      ),
    );
  }

  /// 打开链接；打不开时复制到剪贴板兜底
  Future<void> _open(BuildContext context, String url, String title) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await Browser.open(url);
    if (ok) return;
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(
      SnackBar(content: Text('$title 链接已复制\n$url')),
    );
  }

  Widget _buildDisclaimer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel_rounded, size: 16, color: AppTheme.textSub),
              const SizedBox(width: 6),
              Expanded(child: Text(
                '隐私与内容说明',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain,
                ),
              )),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '1. 本应用为第三方个人开发的播放工具，与哔哩哔哩官方无任何关联，'
            '不代表、也不受哔哩哔哩官方授权或认可。\n\n'
            '2. 音频、封面与文字来自 B 站，版权归原作者及相关权利人所有。'
            '播放可用性受平台、账号权限与原视频状态影响，请尊重权利人的授权范围。\n\n'
            '3. 收藏、搜索历史、收听进度及设置保存在本机。离线缓存会将音频'
            '保存到本机应用目录，可在「我的 → 离线缓存」中删除；应用不提供内容二次分发。\n\n'
            '4. 登录后凭据保存在本机，用于向 B 站请求账号及播放服务；'
            '退出登录会清除本机登录凭据，收藏与收听进度保留。'
            '系统备份可恢复收藏与设置，不包含登录凭据及离线音频。\n\n'
            '5. B听未接入第三方行为统计，搜索与播放仍需向 B 站发起请求。'
            '独立项目的更新与反馈入口尚未配置，原项目链接仅用于来源致谢。\n\n'
            '6. 喜欢某部作品时，请前往官方平台支持作者。',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSub,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}
