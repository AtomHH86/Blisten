// Optional network smoke. This intentionally uses live Bilibili and can fail
// independently of app changes when the network/resource/API is unavailable.
import 'dart:convert';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/network/cookie_jar.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/player/bili_audio_handler.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:blisten/services/bili_resource.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'live Bili mode searches and native audio playback',
    (tester) async {
      MediaKit.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      // Clear only network credentials in this dedicated emulator debug app.
      // Deterministic tests store fixture WBI keys which must not reach live APIs.
      await prefs.remove('bili_cookie');
      await prefs.remove('bili_wbi_keys');
      CookieJar.instance.clear();
      await BiliClient.instance.initLocal();
      await BiliClient.instance.warmupIfNeeded();
      await ShelfStore.instance.load();
      await CacheStore.instance.load();
      final player = BookPlayer.instance;
      player.setup();
      final handler = await AudioService.init(
        builder: BiliAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.bting.audio.channel.audio',
          androidNotificationChannelName: 'B听',
          androidStopForegroundOnPause: false,
        ),
      );
      player.attachHandler(handler);
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('B 站联网验证中'))),
          ),
        );

        final results = <String, int>{};
        String? childrenBvid;
        for (final query in [
          (ContentMode.audiobook, '三体 有声小说'),
          (ContentMode.music, '种子'),
          (ContentMode.concert, '演唱会 全场'),
          (ContentMode.children, '儿歌 小星星'),
          (ContentMode.children, '儿童动画片'),
          (ContentMode.children, '儿童故事'),
        ]) {
          final books = await BiliApi.instance.search(query.$2, mode: query.$1);
          expect(
            books,
            isNotEmpty,
            reason: '${query.$1.name} live search is empty',
          );
          expect(books.every((book) => book.contentMode == query.$1), isTrue);
          results['${query.$1.name}:${query.$2}'] = books.length;
          if (query.$1 == ContentMode.children) childrenBvid ??= books.first.bvid;
        }

        const bvid = String.fromEnvironment(
          'ABTS_LIVE_BV',
          defaultValue: 'BV1wB4y1R7Sg',
        );
        final resource = await BiliResourceResolver().resolve(bvid);
        final book = await BiliApi.instance.detail(
          resource.bvid,
          mode: ContentMode.music,
        );
        expect(book.chapters, isNotEmpty);
        expect(await player.playBook(book, resume: false), isTrue);
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (player.currentPosition < const Duration(seconds: 3) &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(player.isPlaying, isTrue);
        expect(player.isOffline, isFalse);
        expect(
          player.currentPosition,
          greaterThanOrEqualTo(const Duration(seconds: 3)),
        );
        // No cookies or signed/expiring media URLs in this summary.
        debugPrint(
          'ABTS_LIVE_RESULT ${jsonEncode({'searchCounts': results, 'bvid': book.bvid, 'positionMs': player.currentPosition.inMilliseconds, 'online': !player.isOffline})}',
        );
        await player.stop();
        const childrenOverride = String.fromEnvironment('ABTS_CHILDREN_LIVE_BV');
        final children = await BiliApi.instance.detail(
          childrenOverride.isEmpty ? childrenBvid! : childrenOverride,
          mode: ContentMode.children,
        );
        expect(children.chapters, isNotEmpty);
        expect(await player.playBook(children, resume: false), isTrue);
        final childrenDeadline = DateTime.now().add(const Duration(seconds: 30));
        while (player.currentPosition < const Duration(seconds: 3) &&
            DateTime.now().isBefore(childrenDeadline)) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(player.isPlaying, isTrue);
        expect(player.isOffline, isFalse);
        expect(player.currentPosition, greaterThanOrEqualTo(const Duration(seconds: 3)));
        debugPrint('ABTS_CHILDREN_LIVE_RESULT ${jsonEncode({
          'bvid': children.bvid, 'positionMs': player.currentPosition.inMilliseconds,
          'mode': player.book!.contentMode.name, 'online': !player.isOffline,
        })}');
      } finally {
        // Keep cleanup inside runTest so the drive adapter observes failures.
        await player.stop();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
