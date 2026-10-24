import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/checked_hooks.dart';
import 'support/local_bili_fixture.dart';

/// The runner force-stops the seed process. No pause, stop or flush may save
/// progress before it dies; verification reads Android's real persisted data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('ABTS_RESTART_PHASE');
  const marker = 'integration_continuous_seed';
  final fixture = LocalBiliFixture();
  late SharedPreferences prefs;
  late BookPlayer player;
  final shelf = ShelfStore.instance;

  setUpAll(
    () => guardedHook('continuous restart setup', () async {
      expect(phase, isIn(['seed', 'verify']));
      await fixture.start();
      HttpOverrides.global = fixture;
      MediaKit.ensureInitialized();
      prefs = await SharedPreferences.getInstance();
      if (phase == 'seed') await prefs.clear();
      await BiliClient.instance.initLocal();
      await shelf.load();
      await CacheStore.instance.load();
      player = BookPlayer.instance;
      await fixture.configurePlayer(player.player);
      player.setup();
    }),
  );

  tearDownAll(
    () => guardedHook('continuous restart cleanup', () async {
      expect(fixture.unexpectedRequests, isEmpty);
      // Seed intentionally leaves both the player and local media server alive
      // until the external runner terminates this Android process.
      if (phase == 'verify') {
        await player.stop();
        await fixture.close();
        HttpOverrides.global = null;
      }
    }),
  );

  testWidgets(
    'continuous playback survives process termination: $phase',
    (tester) async {
      if (phase == 'seed') {
        final book = await BiliApi.instance.detail(
          LocalBiliFixture.concert,
          mode: ContentMode.concert,
        );
        expect(await player.playBook(book, resumeIndex: 2), isTrue);
        final clock = Stopwatch()..start();
        while (player.currentPosition.inSeconds < 8 &&
            clock.elapsed < const Duration(seconds: 25)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(player.isPlaying, isTrue);
        expect(player.currentPosition.inSeconds, greaterThanOrEqualTo(8));
        await prefs.setString(marker, jsonEncode({'pid': pid}));
        return;
      }
      final seed = jsonDecode(prefs.getString(marker)!) as Map;
      expect(pid, isNot(seed['pid']));
      final saved = shelf.progressByBvid(LocalBiliFixture.concert);
      expect(saved, isNotNull);
      expect(saved!.lastCid, LocalBiliFixture.cid(LocalBiliFixture.concert, 3));
      expect(
        saved.positionMs,
        greaterThanOrEqualTo(4000),
        reason: 'Continuous listening must persist before a manual pause.',
      );
      expect(saved.positionMs, lessThan(90000));
      expect(await player.resumeShelf(saved), isTrue);
      expect(player.currentChapter?.cid, saved.lastCid);
      expect(
        player.currentPosition.inMilliseconds,
        closeTo(saved.positionMs, 3000),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
