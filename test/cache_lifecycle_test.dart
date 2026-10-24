import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:flutter_test/flutter_test.dart';
// Test the real store across the path_provider platform boundary.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  final String root;
  Future<String?> Function()? external;
  _Paths(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getExternalStoragePath() async => external == null ? null : await external!();
}

// Actual PCM WAVE samples, with hand-sized RIFF/fmt/data chunks.
Uint8List _wave() {
  final bytes = Uint8List(16044);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  data.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 16, ascii.encode('WAVEfmt '));
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 16000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, ascii.encode('data'));
  data.setUint32(40, 16000, Endian.little);
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = CacheStore.instance;
  late Directory root;
  late HttpServer server;
  late HttpOverrides? previousOverrides;
  late PathProviderPlatform previousPaths;
  late _Paths paths;
  late List<Completer<void>> gates;
  late List<Future<Object?>> running;
  Future<void> Function(HttpRequest)? handler;

  String url(String path) => 'http://127.0.0.1:${server.port}/$path';

  Future<bool> download(int cid, String path) => cache.download(
    bvid: 'cache-bv', cid: cid, url: url(path), bookTitle: '缓存测试',
    chapterTitle: '$cid · 测试', cover: '', durationSec: 1, headers: {},
  );

  setUp(() async {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    gates = [];
    running = [];
    handler = null;
    root = await Directory.systemTemp.createTemp('blisten-cache-test-');
    previousPaths = PathProviderPlatform.instance;
    paths = _Paths(root.path);
    PathProviderPlatform.instance = paths;
    SharedPreferences.setMockInitialValues({});
    await cache.clearAll();
    cache.clearFinishedTasks();
    cache.clearFailures();
    await cache.load();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        request.response.headers.contentType = ContentType.binary;
        if (handler != null) {
          await handler!(request);
        } else {
          request.response.headers.contentType = ContentType('audio', 'wav');
          request.response.add(_wave());
          await request.response.close();
        }
      } on HttpException {
        // A canceled client is expected in the clear-all tests.
      } on SocketException {
        // Cancellation may close the connection before a gated body completes.
      }
    });
  });

  tearDown(() async {
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete();
    }
    for (final work in running) {
      await work.timeout(const Duration(seconds: 10));
    }
    await cache.clearAll();
    cache.clearFinishedTasks();
    cache.clearFailures();
    cache.onQueueFinished = null;
    await server.close(force: true);
    await root.delete(recursive: true);
    HttpOverrides.global = previousOverrides;
    PathProviderPlatform.instance = previousPaths;
  });

  test('load does not report ready before startup reconciliation completes', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    gates.add(release);
    paths.external = () async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
      return null;
    };
    var ready = false;
    final loading = cache.load().then((_) { ready = true; });
    running.add(loading);
    await entered.future;
    await Future<void>.value();
    expect(ready, isFalse,
        reason: 'Resume and new writes must wait for orphan cleanup and migration.');
    release.complete();
    await loading;
    expect(ready, isTrue);
  });

  for (final action in ['recache', 'remove', 'removeBook']) {
    test('$action preserves the index and reports a failed file deletion', () async {
      expect(await download(1, 'complete'), isTrue);
      cache.clearFinishedTasks();
      final entry = cache.entries.single;
      final audio = await cache.fileOf(entry);
      await audio.delete();
      // A non-empty directory at the expected file path cannot be unlinked as
      // a file. This produces a deterministic deletion failure on every host.
      await Directory(audio.path).create();
      await File('${audio.path}/occupied').writeAsString('retain on failure');
      var resolves = 0;
      final Future<void> work = switch (action) {
        'recache' => cache.recache(entry, resolveUrl: (_, _) async {
          resolves++;
          return null;
        }, headers: {}),
        'remove' => cache.remove(entry.bvid, entry.cid),
        _ => cache.removeBook(entry.bvid),
      };
      await expectLater(work, throwsA(isA<FileSystemException>()));
      expect(cache.isCached(entry.bvid, entry.cid), isTrue);
      expect(resolves, 0);
      expect(cache.queueLength, 0);
      expect(cache.tasks, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('abts_cache_index')!), hasLength(1));
      expect(await File('${audio.path}/occupied').exists(), isTrue);
    });
  }

  test('clear all removes queued metadata while URL lookup is still pending', () async {
    expect(await download(1, 'complete'), isTrue);
    cache.clearFinishedTasks();
    final entered = Completer<void>();
    final release = Completer<void>();
    gates.add(release);
    final drained = Completer<void>();
    cache.onQueueFinished = () { if (!drained.isCompleted) drained.complete(); };
    running.add(drained.future);
    await cache.enqueue(
      bvid: 'queued-bv', bookTitle: '待缓存', cover: '', contentMode: ContentMode.concert,
      items: [
        (cid: 10, chapterTitle: '第一段', durationSec: 1, page: 1, part: '第一段', order: 1),
        (cid: 20, chapterTitle: '第二段', durationSec: 1, page: 2, part: '第二段', order: 2),
      ],
      resolveUrl: (_, _) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        return url('wave');
      },
      headers: {},
    );
    await entered.future;
    await cache.clearAll().timeout(const Duration(seconds: 3));
    expect(cache.tasks, isEmpty);
    expect(cache.queueLength, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('abts_cache_pending'), isNull);
    release.complete();
    await drained.future;
    expect(cache.entries, isEmpty);
    expect(cache.tasks, isEmpty);
    expect(cache.queueLength, 0);
    expect(prefs.getString('abts_cache_pending'), isNull);
    expect(jsonDecode(prefs.getString('abts_cache_index')!), isEmpty);
    expect((await cache.diskUsage()).count, 0);
  });

  test('clear all cancels an active file writer before returning', () async {
    expect(await download(1, 'complete'), isTrue);
    final entered = Completer<void>();
    final release = Completer<void>();
    gates.add(release);
    handler = (request) async {
      final body = _wave();
      request.response.contentLength = body.length;
      request.response.add(body.sublist(0, 44));
      await request.response.flush();
      entered.complete();
      await release.future;
      request.response.add(body.sublist(44));
      await request.response.close();
    };
    final active = download(2, 'blocked');
    running.add(active);
    await entered.future;
    await cache.clearAll().timeout(const Duration(seconds: 3));
    expect(cache.tasks, isEmpty);
    expect(cache.entries, isEmpty);
    release.complete();
    expect(await active, isFalse);
    expect(cache.entries, isEmpty);
    expect(cache.tasks, isEmpty);
    expect(cache.queueLength, 0);
    expect((await cache.diskUsage()).count, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('abts_cache_pending'), isNull);
    expect(jsonDecode(prefs.getString('abts_cache_index')!), isEmpty);
  });

  test('a valid chunked WAVE downloads and survives a transient playback check', () async {
    expect(await download(1, 'wave'), isTrue);
    await cache.dropIfBroken('cache-bv', 1);
    expect(cache.isCached('cache-bv', 1), isTrue);
    expect(await cache.cacheFilePath('cache-bv', 1), isNotNull);
  });

  for (final extension in ['m4a', 'flac']) {
    test('a real encoded $extension fixture passes download validation', () async {
      final bytes = await File('test/fixtures/cache-silence.$extension').readAsBytes();
      handler = (request) async {
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      };
      expect(await download(1, extension), isTrue);
      expect(cache.entries.single.sizeBytes, bytes.length);
    });
  }

  for (final invalid in ['html', 'json', 'empty', 'partial-response', 'truncated-wave', 'invalid-mp4', 'truncated-flac']) {
    test('completed download rejects $invalid and leaves no indexed or partial file', () async {
      handler = (request) async {
        switch (invalid) {
          case 'html':
            request.response.headers.contentType = ContentType.html;
            request.response.write('<html>rate limited</html>');
          case 'json':
            request.response.headers.contentType = ContentType.json;
            request.response.write('{"code":-412,"message":"blocked"}');
          case 'empty':
            break;
          case 'partial-response':
            request.response.statusCode = HttpStatus.partialContent;
            request.response.add(_wave());
          case 'truncated-wave':
            request.response.add(_wave().sublist(0, 80));
          case 'invalid-mp4':
            // Declares an ftyp box larger than the downloaded body.
            request.response.add([0, 0, 4, 0, ...ascii.encode('ftypM4A '), 0, 0, 0, 0]);
          case 'truncated-flac':
            request.response.add((await File('test/fixtures/cache-silence.flac').readAsBytes()).sublist(0, 40));
        }
        await request.response.close();
      };
      expect(await download(1, invalid), isFalse);
      expect(cache.isCached('cache-bv', 1), isFalse);
      expect((await cache.diskUsage()).count, 0);
      expect(cache.taskOf('cache-bv', 1)?.error, isNotEmpty);
    });
  }
}
