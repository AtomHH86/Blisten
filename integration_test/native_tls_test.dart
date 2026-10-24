import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/storage/shelf_store.dart';
import 'package:blisten/player/book_player.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/checked_hooks.dart';
import 'support/local_bili_fixture.dart';
import 'support/localhost_certificate.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final fixture = LocalBiliFixture()..allowTlsRejection = true;
  late BookPlayer player;

  setUpAll(() => guardedHook('native TLS setup', () async {
    expect(Platform.isAndroid, isTrue);
    await fixture.start();
    // The API client trusts this test CA; the native player intentionally does
    // not. Production player setup must reject its HTTPS media certificate.
    HttpOverrides.global = fixture;
    MediaKit.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await BiliClient.instance.initLocal();
    await ShelfStore.instance.load();
    await CacheStore.instance.load();
    await CacheStore.instance.clearAll();
    player = BookPlayer.instance;
    player.setup();
  }));

  tearDown(() => guardedHook('native TLS cleanup', () async {
    await player.stop();
    expect(fixture.unexpectedRequests, isEmpty);
  }));

  tearDownAll(() => guardedHook('native TLS shutdown', () async {
    await fixture.close();
    HttpOverrides.global = null;
  }));

  testWidgets('production player rejects an untrusted HTTPS certificate',
      (tester) async {
    final book = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
    expect(await player.playBook(book, resume: false), isFalse);
    expect(player.loaded, isFalse);
    expect(player.isPlaying, isFalse);
    expect(player.error, isNotNull);
    final native = player.player.platform! as NativePlayer;
    expect(await native.getProperty('tls-verify'), 'yes');
    expect(await native.getProperty('tls-ca-file'), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  for (final (bvid, url) in [
    (LocalBiliFixture.imported, 'content://blisten.invalid/not-a-media-resource'),
    (LocalBiliFixture.cached, 'file:///blisten-invalid/not-a-media-resource'),
    (LocalBiliFixture.retryMusic, 'ftp://blisten.invalid/not-a-media-resource'),
  ]) {
    testWidgets('API ${Uri.parse(url).scheme} media URL is rejected before native open',
        (tester) async {
      // These BVIDs are not used by the other TLS tests, so no valid cached URL
      // can mask the API response being checked here.
      await player.stop();
      try {
        fixture.audioUrlOverride = url;
        final book = await BiliApi.instance.detail(bvid);
        // Keep this assertion before playBook: RED must stop here, without
        // passing a content URI to the native helper.
        expect(await player.resolveUrlFor(bvid, LocalBiliFixture.cid(bvid, 1)),
            isNull);
        expect(await player.playBook(book, resume: false), isFalse);
        expect(player.loaded, isFalse);
        expect(player.isPlaying, isFalse);
        expect(player.error, isNotNull);
      } finally {
        fixture.audioUrlOverride = null;
        await player.stop();
      }
    }, timeout: const Timeout(Duration(minutes: 1)));
  }

  testWidgets('explicitly trusted test CA permits native HTTPS playback',
      (tester) async {
    await fixture.configurePlayer(player.player);
    final book = await BiliApi.instance.detail(LocalBiliFixture.audiobook);
    expect(await player.playBook(book, resume: false), isTrue);
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (player.currentPosition < const Duration(seconds: 2) &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(player.currentPosition, greaterThanOrEqualTo(const Duration(seconds: 2)));
    expect(player.isPlaying, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('embedded player keeps terminal handling disabled', (tester) async {
    final native = player.player.platform! as NativePlayer;
    expect(await native.getProperty('terminal'), 'no');
    expect(await native.getProperty('input-terminal'), 'no');
  });

  testWidgets('trusted certificate with wrong hostname is rejected before HTTP',
      (tester) async {
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(wrongHostCertificate))
      ..usePrivateKeyBytes(utf8.encode(localhostPrivateKey));
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    final errors = <Object>[];
    var requests = 0;
    server.listen((request) {
      requests++;
      request.response.statusCode = HttpStatus.notFound;
      unawaited(request.response.close());
    }, onError: (Object error) {
      if (error is! HandshakeException && error is! SocketException) errors.add(error);
    });
    final directory = await Directory.systemTemp.createTemp('blisten-wrong-host-');
    final ca = await File('${directory.path}/ca.pem').writeAsString(wrongHostCertificate);
    try {
      final native = player.player.platform! as NativePlayer;
      await native.setProperty('tls-ca-file', ca.path);
      expect(await native.getProperty('tls-verify'), 'yes');
      final failure = player.player.stream.error.first.timeout(const Duration(seconds: 15));
      await player.player.open(Media('https://localhost:${server.port}/test.wav'));
      expect(await failure, isNotEmpty);
      expect(requests, 0, reason: 'Hostname mismatch must stop before an HTTP request.');
      expect(errors, isEmpty);
    } finally {
      await player.stop();
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
}
