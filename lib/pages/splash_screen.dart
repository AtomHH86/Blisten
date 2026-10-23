import 'package:flutter/material.dart';

import '../core/app_meta.dart';
import '../core/theme/app_theme.dart';

/// 纯展示组件：耗时初始化由 BlistenApp 完成，不为品牌展示延长启动。
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: (constraints.maxWidth - 48).clamp(
                    0.0,
                    double.infinity,
                  ),
                  minHeight: (constraints.maxHeight - 48).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/mascot.png',
                      width: 176,
                      height: 176,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppMeta.name,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppMeta.tagline,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: AppTheme.textSub),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.actionText,
                        semanticsLabel: '正在准备收听',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
