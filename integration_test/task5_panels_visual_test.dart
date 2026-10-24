// Stage C scratch: copy to integration_test/ after the original UX RED.
// Real Android rendering/media with a bounded 320/360dp Flutter app viewport;
// PNG capture is manual-review evidence, not a golden or TalkBack claim.
import 'dart:io';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/pages/player_page.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/checked_hooks.dart';
import 'support/local_bili_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final fixture = LocalBiliFixture();
  late BookPlayer player;

  setUpAll(() => guardedHook('task5 panel visual setup', () async {
    expect(Platform.isAndroid, isTrue);
    await fixture.start();
    HttpOverrides.global = fixture;
    MediaKit.ensureInitialized();
    await (await SharedPreferences.getInstance()).clear();
    await BiliClient.instance.initLocal();
    await ShelfStore.instance.load();
    await CacheStore.instance.load();
    await CacheStore.instance.clearAll();
    player = BookPlayer.instance;
    await fixture.configurePlayer(player.player);
    player.setup();
    await binding.convertFlutterSurfaceToImage();
  }, timeout: const Duration(seconds: 90)));

  tearDown(() => guardedHook('task5 panel visual case cleanup', () async {
    player.cancelSleepTimer();
    await player.stop();
    expect(fixture.unexpectedRequests, isEmpty);
    AppTheme.mode = ThemeMode.system;
  }));

  tearDownAll(() => guardedHook('task5 panel visual cleanup', () async {
    await fixture.close();
    HttpOverrides.global = null;
  }));

  Future<void> capture(WidgetTester tester, String name, double width) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull, reason: name);
    if (name.endsWith('custom-dialog-keyboard-closed')) {
      expect(MediaQuery.viewInsetsOf(tester.element(find.byType(AlertDialog))).bottom, 0,
        reason: 'Full-form screenshot must have a settled, closed native keyboard.');
    }
    // One APK/process exercises both widths; representative 320dp screenshots
    // cover both themes without rebuilding every theme/panel combination.
    if (width == 320) await binding.takeScreenshot(name);
  }

  Future<void> openPanel(WidgetTester tester, IconData icon) async {
    final chip = find.widgetWithIcon(ActionChip, icon);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  Future<void> closePanel(WidgetTester tester) async {
    final sheet = find.byType(BottomSheet);
    final owner = ModalRoute.of(tester.element(sheet));
    final bounds = tester.getRect(sheet);
    expect(bounds.top, greaterThan(8), reason: 'The dismissible scrim must be reachable.');
    // Tap the actual exposed scrim, using the same pointer path as a user.
    await tester.tapAt(Offset(bounds.center.dx, bounds.top / 2));
    // Live binding pump(duration) waits then draws one frame; it does not run
    // all intervening animation frames. Start reversal, then supply frames.
    await tester.pump();
    expect(owner!.isCurrent, isFalse,
      reason: 'The scrim tap must pop the owning route before animation waiting.');
    final wait = Stopwatch()..start();
    while (sheet.evaluate().isNotEmpty && wait.elapsed < const Duration(seconds: 5)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(sheet, findsNothing);
    expect(find.byType(PlayerPage), findsOneWidget);
  }

  for (final dark in [false, true]) {
    for (final width in [320.0, 360.0]) {
      final tone = dark ? 'dark' : 'light';
      testWidgets('native panels $tone ${width.toInt()}dp at 200%', (tester) async {
        AppTheme.mode = dark ? ThemeMode.dark : ThemeMode.light;
        final book = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
        expect(await player.playBook(book), isTrue);
        await until(tester, () => player.isPlaying, 'native local audio ready');
        await player.pause();
        player.setSleepTimer(const Duration(minutes: 30));
        await tester.pumpWidget(host(player, dark: dark, width: width));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.getSize(find.byType(PlayerPage)).width, width);
        final prefix = 'task5-$tone-${width.toInt()}dp-200';

        await openPanel(tester, Icons.speed_rounded);
        expect(find.text('1.0x'), findsOneWidget);
        await capture(tester, '$prefix-speed-open', width);
        await closePanel(tester);

        await openPanel(tester, Icons.format_list_bulleted);
        expect(find.text('1 · 测试分 P 1'), findsOneWidget);
        await capture(tester, '$prefix-chapters-open', width);
        await closePanel(tester);

        await openPanel(tester, Icons.bedtime_outlined);
        expect(find.text('30 分钟'), findsOneWidget);
        await capture(tester, '$prefix-timer-open', width);
        final custom = find.text('自定义时长');
        await tester.scrollUntilVisible(custom, 160,
          scrollable: find.descendant(of: find.byType(BottomSheet),
            matching: find.byType(Scrollable)).first);
        await tester.tap(custom);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('自定义睡眠定时'), findsOneWidget);
        // Flutter surface screenshots omit the native IME. Do not capture a
        // keyboard-constrained layout while labelling it a full-form screenshot.
        FocusManager.instance.primaryFocus?.unfocus();
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await until(tester, () => MediaQuery.viewInsetsOf(
          tester.element(find.byType(AlertDialog))).bottom == 0, 'custom dialog keyboard closed');
        // Supply frames for Dialog's inset animation after native metrics settle.
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final helper = find.text('1 ~ 720 分钟');
        await tester.ensureVisible(helper);
        await tester.pump();
        final formBounds = tester.getRect(find.byType(TextFormField));
        final cancelBounds = tester.getRect(find.text('取消'));
        expect(formBounds.top, greaterThanOrEqualTo(tester.getRect(find.byType(AlertDialog)).top),
          reason: 'The complete input must remain inside the dialog bounds.');
        expect(formBounds.bottom, lessThanOrEqualTo(cancelBounds.top),
          reason: 'The complete field and helper must be above dialog actions.');
        expect(helper.hitTestable(), findsOneWidget);
        await capture(tester, '$prefix-custom-dialog-keyboard-closed', width);
        await tester.tap(find.text('取消'));
        await tester.pump(const Duration(milliseconds: 400));
        await closePanel(tester);
        await tester.pumpWidget(const SizedBox());
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  }
}

Widget host(BookPlayer player, {required bool dark, required double width}) =>
  ColoredBox(
    color: AppTheme.bg,
    child: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: width,
        height: 640,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: ShelfStore.instance),
            ChangeNotifierProvider.value(value: CacheStore.instance),
            ChangeNotifierProvider<BookPlayer>.value(value: player),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(width, 640),
                textScaler: const TextScaler.linear(2), disableAnimations: true),
              child: child!,
            ),
            home: KeyedSubtree(key: ValueKey('$dark-$width'), child: const PlayerPage()),
          ),
        ),
      ),
    ),
  );

Future<void> until(WidgetTester tester, bool Function() ready, String label) async {
  final clock = Stopwatch()..start();
  while (!ready() && clock.elapsed < const Duration(seconds: 20)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  expect(ready(), isTrue, reason: label);
}
