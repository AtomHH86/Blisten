import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/credential_store.dart';
import 'api_config.dart';
import 'cookie_jar.dart';
import 'wbi_signer.dart';
import 'request_scheduler.dart';

class BiliApiException implements Exception {
  final int? code;
  final String message;
  BiliApiException(this.code, this.message);

  @override
  String toString() => message;
}

/// B 站客户端：Cookie 预热 + buvid 激活 + WBI 签名 + 统一请求头 + 风控兜底
class _OperationBudget {
  _OperationBudget(this.cancelToken);
  final CancelToken? cancelToken;
  RequestBudget? value;
}

class BiliClient {
  static final _budgetKey = Object();

  /// A search may use several endpoints. Share its deadline and total attempts,
  /// including preparation and fallback, rather than resetting at each endpoint.
  static Future<T> withRequestBudget<T>(Future<T> Function() action,
      {CancelToken? cancelToken}) async {
    if (Zone.current[_budgetKey] != null) return action();
    final holder = _OperationBudget(cancelToken);
    try {
      return await runZoned(action, zoneValues: {_budgetKey: holder});
    } finally {
      holder.value?.close();
    }
  }

  RequestBudget _budget(CancelToken? token) {
    final holder = Zone.current[_budgetKey] as _OperationBudget?;
    if (holder == null) return RequestBudget(_scheduler, cancelToken: token);
    return holder.value ??= RequestBudget(_scheduler,
        cancelToken: holder.cancelToken ?? token, maxAttempts: 12);
  }

  void _closeBudget(RequestBudget budget) {
    if (Zone.current[_budgetKey] == null) budget.close();
  }

  BiliClient._();

  @visibleForTesting
  BiliClient.forTesting(Dio dio, RequestScheduler scheduler) {
    _dio = dio;
    _scheduler = scheduler;
    _dio.httpClientAdapter = ScheduledAdapter(_dio.httpClientAdapter, _scheduler);
  }

  RequestScheduler _scheduler = RequestScheduler();
  static final BiliClient instance = BiliClient._();

  static const _prefWbi = 'bili_wbi_keys';

  late Dio _dio;
  final CookieJar _jar = CookieJar.instance;

  String? _imgUrl;
  String? _subUrl;
  int _wbiFetchedAt = 0;

  bool _buvidActivated = false;
  int _sessionGeneration = 0;
  int get sessionGeneration => _sessionGeneration;

  /// Invalidate pending responses on login attempt replacement or cancellation.
  void invalidateSessionRequests() { _sessionGeneration++; }


  void _setupIo() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.json,
      ),
    );
    _dio.httpClientAdapter = ScheduledAdapter(_dio.httpClientAdapter, _scheduler);
    _dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) {
          final cookie = _jar.buildHeader();
          if (cookie.isNotEmpty) {
            options.headers['Cookie'] = cookie;
          }
          options.headers['User-Agent'] ??= BiliEndpoints.userAgent;
          handler.next(options);
        },
      ),
    );
  }

  /// 本地初始化（启动关键路径，无任何网络请求）：
  /// 创建 Dio 并从本地恢复 Cookie / WBI 缓存，保证进入主界面即可发请求。
  Future<void> initLocal() async {
    _setupIo();
    final prefs = await SharedPreferences.getInstance();
    _sessionGeneration++;
    _jar.clear();
    final cookie = await CredentialStore.instance.load();
    if (cookie != null && cookie.isNotEmpty) {
      final map = <String, String>{};
      for (final seg in cookie.split(';')) {
        final eq = seg.indexOf('=');
        if (eq > 0) map[seg.substring(0, eq).trim()] = seg.substring(eq + 1).trim();
      }
      _jar.mergeFromMap(map);
    }
    final wbi = prefs.getString(_prefWbi);
    if (wbi != null) {
      final parts = wbi.split('|');
      if (parts.length == 3) {
        _imgUrl = parts[0];
        _subUrl = parts[1];
        _wbiFetchedAt = int.tryParse(parts[2]) ?? 0;
      }
    }
  }

  /// 网络预热（进主界面后后台执行，绝不阻塞启动）：
  /// 种入 buvid、激活设备、拉取 WBI 密钥；失败静默，不影响使用。
  Future<void> warmupIfNeeded() async {
    if (!_jar.ready || _needFreshWbiKeys() || !_buvidActivated) await warmup();
  }

  bool _needFreshWbiKeys() {
    if (_imgUrl == null || _subUrl == null) return true;
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return _wbiFetchedAt < day.millisecondsSinceEpoch;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final cookie = _jar.buildHeader();
    await CredentialStore.instance.write(cookie.isEmpty ? null : cookie);
    if (_imgUrl != null && _subUrl != null) {
      await prefs.setString(_prefWbi, '$_imgUrl|$_subUrl|$_wbiFetchedAt');
    }
  }

  /// 预热共享一个预算；不在风险重试内部递归启动新的预热请求。
  Future<void> warmup() async {
    final budget = RequestBudget(_scheduler);
    final generation = _sessionGeneration;
    try {
      await _request('GET', BiliEndpoints.warmup, budget, generation,
          responseType: ResponseType.plain);
      if (generation != _sessionGeneration) return;
      _jar.markSuccess();
      debugPrint('[BiliClient] warmup completed');
      await _ensureBuvidActivated(budget, generation);
      await _refreshWbiKeys(budget, generation);
      await _persist();
    } catch (e) {
      debugPrint('[BiliClient] warmup failed: ${e.runtimeType}');
    } finally {
      budget.close();
    }
  }

  Future<void> _ensureBuvidActivated(RequestBudget budget, int generation) async {
    if (_buvidActivated) return;
    if ((_jar.get('buvid3') ?? '').isEmpty) _jar.put('buvid3', genBuvid3());
    if ((_jar.get('buvid4') ?? '').isEmpty) _jar.put('buvid4', genBuvid3());
    await _persist();
    final rnd = Random();
    final png = base64.encode([
      for (var i = 0; i < 32; i++) rnd.nextInt(256),
      0, 0, 0, 0, 73, 69, 78, 68,
      for (var i = 0; i < 4; i++) rnd.nextInt(256),
    ]);
    final payload = jsonEncode({
      '3064': 1, '39c8': '333.1387.fp.risk',
      '3c43': {'adca': 'Linux', 'bfe9': png.substring(png.length - 50)},
    });
    await _request('POST', BiliEndpoints.activateBuvid, budget, generation,
        data: {'payload': payload});
    if (generation == _sessionGeneration) _buvidActivated = true;
  }

  /// 部分接口（如 passport 扫码）content-type 非 JSON，dio 会保留原始字符串，
  /// 这里统一尝试解码，保证上层拿到 Map。
  static Response<dynamic> _normalize(Response<dynamic> res) {
    final d = res.data;
    if (d is String && d.isNotEmpty) {
      final t = d.trimLeft();
      if (t.startsWith('{') || t.startsWith('[')) {
        try {
          return Response<dynamic>(
            data: jsonDecode(d),
            statusCode: res.statusCode,
            statusMessage: res.statusMessage,
            headers: res.headers,
            isRedirect: res.isRedirect,
            redirects: res.redirects,
            requestOptions: res.requestOptions,
            extra: res.extra,
          );
        } catch (_) {
          // 非 JSON，保持原样
        }
      }
    }
    return res;
  }

  Future<Response<dynamic>> _acceptResponse(
      String url, Response<dynamic> res, int generation) async {
    final isQrPoll = url == BiliEndpoints.qrPoll ||
        url.startsWith('${BiliEndpoints.qrPoll}?');
    if (isQrPoll && generation != _sessionGeneration) {
      throw BiliApiException(-2, '登录请求已取消');
    }
    if (generation == _sessionGeneration) {
      final body = res.data;
      if (isQrPoll && body is Map && body['code'] == 0 &&
          body['data'] is Map && body['data']['code'] == 0) {
        // Commit the new account before any competing old response can merge.
        _sessionGeneration++;
      }
      if (res.headers['set-cookie'] != null) {
        _jar.mergeFromHeaders(res.headers['set-cookie']);
        await _persist();
      }
    }
    return res;
  }

  static bool _riskCode(int c) => c == -412 || c == -352 || c == -509;
  static const _backoff = [800, 1600, 3200];

  static bool _isRiskResponse(Response<dynamic> res) {
    if (res.statusCode == 412 || res.statusCode == 403) return true;
    final body = res.data;
    return body is Map && (_riskCode(int.tryParse('${body['code']}') ?? 0) ||
        (body['data'] is Map && body['data']['v_voucher'] != null));
  }

  static void _validateResponse(Response<dynamic> res) {
    if (_isRiskResponse(res)) throw BiliApiException(-412, '网络繁忙，请稍后再试');
    final status = res.statusCode ?? 0;
    if (status >= 400) throw BiliApiException(status, 'HTTP $status');
    final body = res.data;
    if (body is Map) {
      final code = int.tryParse('${body['code'] ?? 0}') ?? 0;
      if (code != 0) {
        throw BiliApiException(code, '$code：${body['message'] ?? body['msg'] ?? ''}');
      }
    }
  }

  /// Every actual attempt (including POST and WBI) reserves a unique slot.
  Future<Response<dynamic>> _request(
    String method, String url, RequestBudget budget, int generation, {
    Map<String, String>? headers,
    Map<String, dynamic>? data,
    bool jsonBody = true,
    ResponseType responseType = ResponseType.json,
    bool allowGuestWbi = false,
  }) async {
    var retry = 0;
    while (true) {
      budget.check();
      try {
        final res = _normalize(await _dio.request<dynamic>(url,
          data: method == 'POST' ? (jsonBody ? jsonEncode(data ?? {}) : data) : null,
          cancelToken: budget.token,
          options: Options(
            method: method,
            extra: {ScheduledAdapter.budgetKey: budget},
            headers: {'Referer': BiliEndpoints.home, ...?headers},
            contentType: method == 'POST' && jsonBody ? Headers.jsonContentType : null,
            responseType: responseType,
            receiveTimeout: budget.remaining,
            sendTimeout: budget.remaining,
            validateStatus: (_) => true,
          ),
        ));
        budget.check();
        await _acceptResponse(url, res, generation);
        if (_isRiskResponse(res) && budget.canRetry && retry < 3) {
          await budget.wait(Duration(milliseconds: _backoff[retry.clamp(0, 2)]));
          retry++;
          continue;
        }
        final body = res.data;
        final guestKeys = allowGuestWbi && body is Map && body['code'] == -101 &&
            body['data'] is Map && body['data']['wbi_img'] is Map &&
            body['data']['wbi_img']['img_url'] is String &&
            body['data']['wbi_img']['sub_url'] is String;
        if (!guestKeys) _validateResponse(res);
        return res;
      } on DioException catch (error) {
        if (budget.timedOut) throw TimeoutException('Request deadline');
        if (CancelToken.isCancel(error)) rethrow;
        if (!budget.canRetry || retry >= 3) {
          throw BiliApiException(-1, '网络请求失败：${error.type.name}');
        }
        await budget.wait(Duration(milliseconds: _backoff[retry.clamp(0, 2)]));
        retry++;
      }
    }
  }

  Future<void> _refreshWbiKeys(RequestBudget budget, int generation) async {
    final res = await _request('GET', BiliEndpoints.nav, budget, generation,
        allowGuestWbi: true);
    if (generation != _sessionGeneration) return;
    final body = res.data;
    if (body is Map && body['data'] is Map && body['data']['wbi_img'] is Map) {
      final wbi = body['data']['wbi_img'] as Map;
      final img = wbi['img_url'] as String?;
      final sub = wbi['sub_url'] as String?;
      if (img != null && sub != null) {
        _imgUrl = img;
        _subUrl = sub;
        _wbiFetchedAt = DateTime.now().millisecondsSinceEpoch;
        _jar.markSuccess();
        await _persist();
      }
    }
  }

  /// Four HTTP attempts / 45 seconds total, including signature preparation.
  Future<Response<dynamic>> get(String url, {
    Map<String, dynamic>? query,
    bool useWbi = false,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    final budget = _budget(cancelToken);
    final generation = _sessionGeneration;
    try {
      var q = {...?query};
      if (useWbi) {
        if (_needFreshWbiKeys()) await _refreshWbiKeys(budget, generation);
        budget.check();
        if (_imgUrl == null || _subUrl == null) {
          throw BiliApiException(-401, '初始化失败，请检查网络后重试');
        }
        q = WbiSigner.sign(q, imgUrl: _imgUrl!, subUrl: _subUrl!);
      }
      final fullUrl = q.isEmpty ? url : Uri.parse(url).replace(queryParameters: {
        for (final e in q.entries) e.key: '${e.value}',
      }).toString();
      return await _request('GET', fullUrl, budget, generation, headers: headers);
    } on TimeoutException {
      throw BiliApiException(-1, '请求超时，请重试');
    } finally {
      _closeBudget(budget);
    }
  }

  Future<Response<dynamic>> post(String url, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
    bool jsonBody = true,
    CancelToken? cancelToken,
  }) async {
    final budget = _budget(cancelToken);
    try {
      return await _request('POST', url, budget, _sessionGeneration,
          data: data, headers: headers, jsonBody: jsonBody);
    } on TimeoutException {
      throw BiliApiException(-1, '请求超时，请重试');
    } finally {
      _closeBudget(budget);
    }
  }

  /// 是否存在会话凭据；有效性由 nav 验证，不能用于展示已登录。
  bool get isLoggedIn {
    final s = _jar.get('SESSDATA');
    return s != null && s.isNotEmpty;
  }

  /// 退出登录：清空并持久化
  Future<void> logout() async {
    _sessionGeneration++;
    _jar.clear();
    await _persist();
  }

  /// 生成本地 buvid3（UUID 大写 + 5 位随机 + infoc）
  static String genBuvid3() {
    final rnd = Random();
    String hex(int n) {
      final sb = StringBuffer();
      for (var i = 0; i < n; i++) {
        sb.write(rnd.nextInt(16).toRadixString(16));
      }
      return sb.toString();
    }

    final uuid = '${hex(8)}-${hex(4)}-4${hex(3)}-'
        '${(8 + rnd.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
    final suffix = rnd.nextInt(100000).toString().padLeft(5, '0');
    return '${uuid.toUpperCase()}$suffix' 'infoc';
  }

  CookieJar get jar => _jar;
}