import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../player/book_player.dart';
import '../utils/format.dart';

/// Both timer entry points use identical choices, eligibility and validation.
class SleepTimerControls extends StatelessWidget {
  const SleepTimerControls({super.key, this.showTitle = false, this.onSelected});

  final bool showTitle;
  final VoidCallback? onSelected;
  static const options = [
    (Duration.zero, '关闭定时'),
    (Duration(minutes: 10), '10 分钟'),
    (Duration(minutes: 15), '15 分钟'),
    (Duration(minutes: 20), '20 分钟'),
    (Duration(minutes: 30), '30 分钟'),
    (Duration(minutes: 45), '45 分钟'),
    (Duration(minutes: 60), '60 分钟'),
    (Duration(hours: 2), '2 小时'),
  ];

  bool _canStart(BuildContext context, BookPlayer player) {
    if (player.loaded && !player.loading) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(player.loading ? '正在加载，请稍后再设置' : '先开始播放再设定吧'),
    ));
    return false;
  }

  void _select(BuildContext context, BookPlayer player, Duration duration, String label) {
    if (duration > Duration.zero && !_canStart(context, player)) {
      return;
    }
    if (duration == Duration.zero) {
      player.cancelSleepTimer();
    } else {
      player.setSleepTimer(duration);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(duration == Duration.zero ? '已关闭睡眠定时' : '$label后自动暂停收听'),
    ));
    onSelected?.call();
  }

  Future<void> _custom(BuildContext context, BookPlayer player) async {
    if (!_canStart(context, player)) return;
    final owner = ModalRoute.of(context);
    final selected = player.sleepTimerDuration;
    final minutes = await showDialog<int>(
      context: context,
      builder: (_) => _CustomSleepTimerDialog(initialMinutes:
        selected > Duration.zero ? selected.inMinutes.clamp(1, 720).toInt() : 20),
    );
    if (minutes == null || !context.mounted || (owner != null && !owner.isCurrent)) {
      return;
    }
    // Loading may have changed while the dialog was open.
    _select(context, player, Duration(minutes: minutes), '$minutes 分钟');
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<BookPlayer>();
    final selected = player.sleepTimerDuration;
    final customSelected = selected > Duration.zero && !options.any((option) => option.$1 == selected);
    final unit = player.book?.contentMode.unitLabel ?? '项';
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        if (showTitle) Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text('睡眠定时', style: TextStyle(fontSize: 20,
            fontWeight: FontWeight.w600, color: AppTheme.textMain)),
        ),
        if (player.sleepRemaining > Duration.zero) Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('距自动暂停还剩 ${Fmt.sleepText(player.sleepRemaining)}',
            style: TextStyle(fontSize: 14, color: AppTheme.textSub)),
        ),
        for (final (duration, label) in options) ListTile(
          selected: duration == selected,
          title: Text(label, style: TextStyle(fontSize: 16, color:
            duration == selected ? AppTheme.actionText : AppTheme.textMain)),
          trailing: duration == selected ? Icon(Icons.check, color: AppTheme.actionText) : null,
          onTap: () => _select(context, player, duration, label),
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: player.stopAtChapterEnd,
          onChanged: player.setStopAtChapterEnd,
          title: Text('播完当前$unit自动暂停', style: TextStyle(fontSize: 16, color: AppTheme.textMain)),
          subtitle: Text('播完即停，不自动播放下一$unit', style: TextStyle(fontSize: 14, color: AppTheme.textSub)),
          activeThumbColor: AppTheme.onPrimary,
        ),
        const Divider(height: 1),
        ListTile(
          selected: customSelected,
          leading: Icon(Icons.edit_calendar_rounded, color: AppTheme.actionText),
          title: Text('自定义时长', style: TextStyle(fontSize: 16, color: AppTheme.textMain)),
          subtitle: Text('按分钟设置，1 ~ 720 分钟', style: TextStyle(fontSize: 14, color: AppTheme.textSub)),
          trailing: Icon(customSelected ? Icons.check : Icons.chevron_right_rounded, color: AppTheme.actionText),
          onTap: () => _custom(context, player),
        ),
      ],
    );
  }
}

class _CustomSleepTimerDialog extends StatefulWidget {
  const _CustomSleepTimerDialog({required this.initialMinutes});
  final int initialMinutes;

  @override
  State<_CustomSleepTimerDialog> createState() => _CustomSleepTimerDialogState();
}

class _CustomSleepTimerDialogState extends State<_CustomSleepTimerDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: '${widget.initialMinutes}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(int.parse(_controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    backgroundColor: AppTheme.surface,
    title: const Text('自定义睡眠定时'),
    content: Form(
      key: _form,
      child: Semantics(
        liveRegion: true,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '分钟数', suffixText: '分钟', helperText: '1 ~ 720 分钟'),
          validator: (value) {
            final minutes = int.tryParse(value?.trim() ?? '');
            return minutes == null || minutes < 1 || minutes > 720
                ? '请输入 1 ~ 720 之间的分钟数' : null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
      TextButton(onPressed: _submit, child: const Text('设置定时')),
    ],
  );
}
