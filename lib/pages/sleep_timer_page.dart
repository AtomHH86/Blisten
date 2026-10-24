import 'package:flutter/material.dart';

import '../widgets/sleep_timer_controls.dart';

/// 睡眠定时（独立页面）：与播放器面板共用选项和校验。
class SleepTimerPage extends StatelessWidget {
  const SleepTimerPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('睡眠定时')),
    body: const SleepTimerControls(),
  );
}
