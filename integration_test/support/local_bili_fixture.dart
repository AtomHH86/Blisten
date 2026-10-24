import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

import 'localhost_certificate.dart';

/// Only the external Bili HTTP boundary is replaced. JSON still passes through
/// BiliClient/WBI/BiliApi, and media_kit + CacheStore read real HTTP WAV bytes.
class LocalBiliFixture extends HttpOverrides {
  static const audiobook = 'BV1xx411c7mA';
  static const music = 'BV1xx411c7mB';
  static const concert = 'BV1xx411c7mC';
  static const imported = 'BV1xx411c7mD';
  static const cached = 'BV1xx411c7mE';
  static const retryMusic = 'BV1xx411c7mF';
  static const retryBook = 'BV1xx411c7mG';
  static const retryUrl = 'BV1xx411c7mH';
  static const ids = [
    audiobook,
    music,
    concert,
    imported,
    cached,
    retryMusic,
    retryBook,
    retryUrl,
  ];
  static const seconds = 90;

  late final HttpServer _server;
  late final HttpServer _mediaServer;
  late final Directory _tlsDirectory;
  final List<(Object, StackTrace)> _serverErrors = [];
  final _wav = _silenceWav();
  final unexpectedRequests = <String>[];
  bool mediaAvailable = true;
  bool allowTlsRejection = false;
  bool apiAvailable = true;
  String? audioUrlOverride;
  int audioGeneration = 0;
  int minimumAudioGeneration = 0;
  final playUrlRequests = <int>[];
  final _pageListGates = <String, FixtureRequestGate>{};
  final _playUrlGates = <int, FixtureRequestGate>{};
  final _gates = <FixtureRequestGate>[];

  FixtureRequestGate gatePageList(String bvid) {
    final gate = FixtureRequestGate();
    _pageListGates[bvid] = gate;
    _gates.add(gate);
    return gate;
  }

  FixtureRequestGate gatePlayUrl(int cid) {
    final gate = FixtureRequestGate();
    _playUrlGates[cid] = gate;
    _gates.add(gate);
    return gate;
  }

  void releaseGates() {
    for (final gate in _gates) {
      gate.release();
    }
    _gates.clear();
    _pageListGates.clear();
    _playUrlGates.clear();
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _listen(_server);
    final serverContext = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(localhostCertificate))
      ..usePrivateKeyBytes(utf8.encode(localhostPrivateKey));
    _mediaServer = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverContext,
    );
    _listen(_mediaServer);
    _tlsDirectory = await Directory.systemTemp.createTemp('abts-fixture-tls-');
    await File(
      '${_tlsDirectory.path}/ca.pem',
    ).writeAsString(localhostCertificate);
  }

  /// Match production's HTTPS-only stream normalization, without disabling TLS
  /// verification. This CA exists only in the integration-test player instance.
  Future<void> configurePlayer(Player player) async {
    final native = player.platform! as NativePlayer;
    final caPath = '${_tlsDirectory.path}/ca.pem';
    await native.setProperty('tls-ca-file', caPath);
    await native.setProperty('tls-verify', 'yes');
    if (await native.getProperty('tls-ca-file') != caPath ||
        await native.getProperty('tls-verify') != 'yes') {
      throw StateError('Native player did not enable the loopback test CA.');
    }
  }

  Future<void> close() async {
    releaseGates();
    await _server.close(force: true);
    await _mediaServer.close(force: true);
    await _tlsDirectory.delete(recursive: true);
    if (_serverErrors.isNotEmpty) {
      final (error, stack) = _serverErrors.first;
      Error.throwWithStackTrace(error, stack);
    }
  }

  void _listen(HttpServer server) {
    server.listen((request) {
      unawaited(_serve(request).catchError(_serverError));
    }, onError: _serverError);
  }

  void _serverError(Object error, StackTrace stack) {
    // Only negative certificate tests opt into expected peer TLS rejections.
    if (allowTlsRejection && error is HandshakeException) return;
    // Rapid native seek/open can close a TLS connection before it becomes an
    // HttpRequest. Catch those same peer-abort errors at the server boundary.
    if (error is SocketException &&
        [32, 54, 104].contains(error.osError?.errorCode)) {
      return;
    }
    // Unexpected asynchronous errors must fail guarded tearDownAll, rather than
    // appearing after a completed test without reaching the drive result.
    _serverErrors.add((error, stack));
  }

  String audioUrl(int cid) => audioUrlOverride ??
      'https://localhost:${_mediaServer.port}/audio/$cid.wav?generation=$audioGeneration';

  static int cid(String bvid, int page) => (ids.indexOf(bvid) + 1) * 100 + page;

  static List<Map<String, Object>> pages(String bvid) => [
    for (var page = 1; page <= 3; page++)
      {
        'cid': cid(bvid, page),
        'page': page,
        'from': 'vupload',
        'part': '测试分 P $page',
        'duration': seconds,
        'dimension': {'width': 1920, 'height': 1080, 'rotate': 0},
      },
  ];

  static Map<String, Object> view(String bvid) => {
    'bvid': bvid,
    'aid': ids.indexOf(bvid) + 1,
    'videos': 3,
    'tid': 195,
    'tname': '测试内容',
    'copyright': 1,
    'pic': '',
    'title': '原生测试资源 $bvid',
    'pubdate': 1700000000,
    'ctime': 1700000000,
    'desc': '本地确定性音频，无外部版权素材',
    'state': 0,
    'duration': seconds * 3,
    'owner': {'mid': 1, 'name': '本地测试', 'face': ''},
    'stat': {
      'aid': ids.indexOf(bvid) + 1,
      'view': 123,
      'like': 2,
      'coin': 0,
      'favorite': 1,
    },
    'cid': cid(bvid, 1),
    'pages': pages(bvid),
  };

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final trusted = context ?? SecurityContext(withTrustedRoots: true);
    trusted.setTrustedCertificatesBytes(utf8.encode(localhostCertificate));
    return _RedirectClient(super.createHttpClient(trusted), this);
  }

  Uri redirect(Uri uri) {
    if (uri.host == '127.0.0.1' && uri.port == _server.port) return uri;
    if (uri.host == 'localhost' &&
        uri.port == _mediaServer.port &&
        uri.scheme == 'https') {
      return uri;
    }
    if (uri.host == 'api.bilibili.com' || uri.host == 'www.bilibili.com') {
      return uri.replace(scheme: 'http', host: '127.0.0.1', port: _server.port);
    }
    unexpectedRequests.add(uri.toString());
    throw StateError(
      'External network is disabled in deterministic tests: $uri',
    );
  }

  Future<void> _serve(HttpRequest request) async {
    final path = request.uri.path;
    final query = request.uri.queryParameters;
    if (path.startsWith('/audio/')) {
      try {
        final generation = int.tryParse(query['generation'] ?? '') ?? 0;
        if (!mediaAvailable || generation < minimumAudioGeneration) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        final range = request.headers.value(HttpHeaders.rangeHeader);
        final match = range == null
            ? null
            : RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
        final start = match == null ? 0 : int.parse(match[1]!);
        final requestedEnd = match == null || match[2]!.isEmpty
            ? _wav.length - 1
            : int.parse(match[2]!);
        final end = requestedEnd.clamp(0, _wav.length - 1);
        if (start >= _wav.length) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        } else {
          request.response.headers
            ..contentType = ContentType('audio', 'wav')
            ..set(HttpHeaders.acceptRangesHeader, 'bytes')
            ..contentLength = end - start + 1;
          if (match != null) {
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-$end/${_wav.length}',
            );
          }
          if (request.method != 'HEAD') {
            request.response.add(_wav.sublist(start, end + 1));
          }
        }
        await request.response.close();
      } on SocketException catch (error) {
        // Native stop/open cancels the previous local media response. Only
        // peer reset and broken-pipe aborts are expected; other failures escape.
        if (![32, 54, 104].contains(error.osError?.errorCode)) rethrow;
      } on HttpException catch (error) {
        final message = error.message.toLowerCase();
        if (!message.contains('connection closed') &&
            !message.contains('connection reset') &&
            !message.contains('broken pipe')) {
          rethrow;
        }
      }
      return;
    }

    FixtureRequestGate? gate;
    if (path == '/x/player/pagelist') {
      gate = _pageListGates.remove(query['bvid']);
    } else if (path == '/x/player/wbi/playurl') {
      final cid = int.tryParse(query['cid'] ?? '') ?? 0;
      playUrlRequests.add(cid);
      gate = _playUrlGates.remove(cid);
    }
    if (gate != null) await gate.wait();

    if (!apiAvailable || (gate?.fail ?? false)) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'code': 503, 'message': 'offline fixture'}),
      );
      await request.response.close();
      return;
    }

    Object? data;
    var code = 0;
    if (path == '/x/web-interface/nav') {
      data = {
        'isLogin': false,
        'wbi_img': {
          'img_url':
              'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
          'sub_url':
              'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
        },
      };
    } else if (path == '/x/web-interface/view' ||
        path == '/x/player/pagelist') {
      final bvid = query['bvid'];
      if (!ids.contains(bvid)) {
        code = -404;
      } else {
        data = path.endsWith('/view') ? view(bvid!) : pages(bvid!);
      }
    } else if (path == '/x/player/wbi/playurl') {
      final bvid = query['bvid'];
      final requestedCid = int.tryParse(query['cid'] ?? '');
      if (!ids.contains(bvid) ||
          !pages(bvid!).any((p) => p['cid'] == requestedCid)) {
        code = -404;
      } else {
        data = {
          'from': 'local',
          'result': 'suee',
          'message': '',
          'quality': 80,
          'format': 'dash',
          'timelength': seconds * 1000,
          'accept_format': 'dash',
          'accept_quality': [80],
          'video_codecid': 7,
          'last_play_time': 0,
          'last_play_cid': 0,
          'dash': {
            'duration': seconds,
            'minBufferTime': 1.5,
            'video': [],
            'audio': [
              {
                'id': 30280,
                'baseUrl': audioUrl(requestedCid!),
                'backup_url': [],
                'bandwidth': 128000,
                'mimeType': 'audio/wav',
                'codecs': 'pcm_s16le',
                'startWithSap': 0,
              },
            ],
          },
        };
      }
    } else if (path == '/x/web-interface/wbi/search/type') {
      if (query['search_type'] == 'bili_user') {
        data = {
          'page': int.tryParse(query['page'] ?? '') ?? 1,
          'pagesize': 20,
          'numResults': 1,
          'numPages': 1,
          'result': [
            {
              'type': 'bili_user',
              'mid': 1,
              'uname': '本地测试 UP 主',
              'upic': '',
              'usign': '本地测试简介',
              'fans': 123,
              'videos': 3,
            },
          ],
        };
      } else {
        final keyword = query['keyword'] ?? '';
        final short = keyword.contains('歌曲');
        data = {
          'page': int.tryParse(query['page'] ?? '') ?? 1,
          'pagesize': 20,
          'numResults': 1,
          'numPages': 1,
          'result': [
            {
              'type': 'video',
              'aid': short ? 2 : 1,
              'bvid': short ? music : audiobook,
              'title': short ? '本地三分钟歌曲' : '本地有声小说测试',
              'pic': '',
              'author': '本地测试',
              'mid': 1,
              'play': 123,
              'duration': short ? '3:00' : '10:00',
              'videos': 3,
              'description': '',
              'tag': '',
              'typeid': short ? '130' : '195',
              'pubdate': 1700000000,
            },
          ],
        };
      }
    } else if (path == '/' || path == '/x/internal/gaia-gateway/ExClimbWuzhi') {
      data = <String, Object>{};
    } else {
      unexpectedRequests.add(request.uri.toString());
      request.response.statusCode = HttpStatus.notFound;
      code = -404;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'code': code,
        'message': code == 0 ? '0' : 'not found',
        'ttl': 1,
        'data': data,
      }),
    );
    await request.response.close();
  }

  static Uint8List _silenceWav() {
    const bytes = seconds * 8000 * 2;
    final data = ByteData(44 + bytes);
    void ascii(int at, String value) {
      for (var i = 0; i < value.length; i++) {
        data.setUint8(at + i, value.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + bytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, 8000, Endian.little);
    data.setUint32(28, 16000, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, bytes, Endian.little);
    return data.buffer.asUint8List();
  }
}

/// Dio's IO adapter calls openUrl and these lifecycle/timeout properties.
/// All returned requests/responses and loopback downloads are actual dart:io.
class _RedirectClient implements HttpClient {
  final HttpClient _client;
  final LocalBiliFixture _fixture;
  _RedirectClient(this._client, this._fixture);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _client.openUrl(method, _fixture.redirect(url));
  @override
  Duration? get connectionTimeout => _client.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _client.connectionTimeout = value;
  @override
  Duration get idleTimeout => _client.idleTimeout;
  @override
  set idleTimeout(Duration value) => _client.idleTimeout = value;
  @override
  void close({bool force = false}) => _client.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A one-shot HTTP boundary gate. Production code still uses the real API and
/// native player; tests control only when the remote response arrives.
class FixtureRequestGate {
  final entered = Completer<void>();
  final _released = Completer<void>();
  bool fail = false;

  Future<void> wait() async {
    if (!entered.isCompleted) entered.complete();
    await _released.future;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}
