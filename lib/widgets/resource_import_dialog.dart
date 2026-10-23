import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/network/bili_client.dart';
import '../core/storage/shelf_store.dart';
import '../models/book.dart';
import '../models/content_mode.dart';
import '../pages/book_detail_page.dart';
import '../services/bili_api.dart';
import '../services/bili_resource.dart';

/// 只有成功解析、取得详情并收藏后才关闭对话框并进入详情。
Future<void> showResourceImportDialog(
  BuildContext context, {
  ContentMode initialMode = ContentMode.audiobook,
}) async {
  final resource = await showDialog<({Book book, int? page})>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ResourceImportDialog(initialMode: initialMode),
  );
  if (!context.mounted || resource == null) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BookDetailPage(
        bvid: resource.book.bvid,
        contentMode: resource.book.contentMode,
        initialPage: resource.page,
        initialBook: resource.book,
      ),
    ),
  );
}

class ResourceImportDialog extends StatefulWidget {
  final ContentMode initialMode;
  final BiliApi? api;
  final BiliResourceResolver? resolver;

  const ResourceImportDialog({
    super.key,
    this.initialMode = ContentMode.audiobook,
    this.api,
    this.resolver,
  });

  @override
  State<ResourceImportDialog> createState() => _ResourceImportDialogState();
}

class _ResourceImportDialogState extends State<ResourceImportDialog> {
  final _controller = TextEditingController();
  late ContentMode _mode = widget.initialMode;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resource = await (widget.resolver ?? BiliResourceResolver())
          .resolve(_controller.text);
      if (!mounted) return;
      final book = await (widget.api ?? BiliApi.instance).detail(
        resource.bvid,
        mode: _mode,
      );
      if (!mounted) return;
      final chapters = book.chapters ?? [];
      if (chapters.isEmpty) {
        throw const FormatException('该视频没有可播放的分 P');
      }
      if (resource.hasExplicitPage &&
          !chapters.any((chapter) => chapter.page == resource.page)) {
        throw const FormatException('链接中的分 P 不存在，请检查 p 参数');
      }
      await ShelfStore.instance.add(book, updateContentMode: true);
      if (!mounted) return;
      Navigator.of(context).pop((
        book: book,
        page: resource.hasExplicitPage ? resource.page : null,
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = switch (error) {
          FormatException() => error.message,
          BiliApiException() => error.message,
          DioException() => '网络连接失败，请检查网络后重试',
          _ => '添加失败，请稍后重试',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_loading,
      child: AlertDialog(
        title: const Text('添加 B 站资源'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择资源类型'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ContentMode.values
                    .map(
                      (mode) => ChoiceChip(
                        label: Text(mode.label),
                        selected: _mode == mode,
                        onSelected: _loading
                            ? null
                            : (_) => setState(() => _mode = mode),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                enabled: !_loading,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'B 站链接或 BV 号',
                  hintText: '支持分享文本、b23.tv 短链接和视频链接',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _mode.resumesPosition
                    ? '按此类型记忆倍速，再次收听时接着上次位置播放。'
                    : '歌曲单独记忆倍速，再次选择时从头播放。',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('添加资源'),
          ),
        ],
      ),
    );
  }
}
