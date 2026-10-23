import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blisten/pages/about_page.dart';
import 'package:blisten/services/app_update.dart';

class _NetworkAttemptRecorder extends HttpOverrides {
  int clientsCreated = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clientsCreated++;
    throw StateError('The unconfigured updater must not access the network');
  }
}

void main() {
  test('unconfigured Blisten updater never creates a network client', () async {
    final recorder = _NetworkAttemptRecorder();
    final result = await HttpOverrides.runZoned(
      AppUpdate.check,
      createHttpClient: recorder.createHttpClient,
    );

    expect(recorder.clientsCreated, 0);
    expect(result.configured, isFalse);
    expect(result.hasNewer, isFalse);
    expect(result.error, isNull);
    expect(result.apkUrl, isNull);
  });

  testWidgets('About credits the original project with its real source link', (
    tester,
  ) async {
    String? copiedUrl;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedUrl = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    final source = find.text('原项目：阿B听书');
    await tester.scrollUntilVisible(source, 250);
    await tester.pumpAndSettle();
    expect(source.hitTestable(), findsOneWidget);
    await tester.tap(source);
    await tester.pumpAndSettle();

    expect(copiedUrl, 'https://github.com/fengqiao57/abts');
    expect(find.text('MIT License · 保留原作者版权声明'), findsOneWidget);
  });

  testWidgets('About leaves unpublished project links disabled', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    expect(find.text('B听'), findsOneWidget);
    expect(find.text('闭上眼听 B 站'), findsOneWidget);

    for (final title in ['开源仓库', '官方网站', '问题反馈']) {
      final label = find.text(title);
      await tester.scrollUntilVisible(label, 150);
      final tile = tester.widget<InkWell>(
        find.ancestor(of: label, matching: find.byType(InkWell)).first,
      );
      expect(
        tile.onTap,
        isNull,
        reason: '$title has no Blisten destination yet',
      );
    }
    await tester.scrollUntilVisible(find.textContaining('离线缓存会将音频'), 250);
    expect(find.textContaining('离线缓存会将音频'), findsOneWidget);
    expect(find.textContaining('本应用不存储'), findsNothing);
  });
}
