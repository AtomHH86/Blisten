import 'package:blisten/core/network/api_config.dart';
import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/models/up_user.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client implements BiliClient {
  _Client(this.respond);
  final Object Function(String url, Map<String, dynamic> query) respond;
  final calls = <String>[];

  @override
  Future<Response<dynamic>> get(String url, {
    Map<String, dynamic>? query,
    bool useWbi = false,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    calls.add(url);
    final value = respond(url, query ?? {});
    if (value is Exception) throw value;
    return Response(data: value, statusCode: 200,
        requestOptions: RequestOptions(path: url));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _up = UpUser(mid: 42, name: 'Synthetic UP');
Object _offline(String url, Map<String, dynamic> query) =>
    BiliApiException(-1, 'synthetic offline');
Map<String, dynamic> _search(List<Map<String, dynamic>> rows) => {
  'code': 0, 'data': {'result': rows, 'numResults': rows.length},
};
Map<String, dynamic> _book(String bvid) => {
  'bvid': bvid, 'aid': 42, 'title': '有声小说 $bvid',
  'duration': 900, 'mid': 42, 'author': 'Synthetic UP',
};

void main() {
  test('all UP sources failing remains a retryable failure', () async {
    final client = _Client(_offline);
    await expectLater(BiliApi(client: client).upAudios(_up),
        throwsA(isA<BiliApiException>()));
    expect(client.calls, hasLength(3));
  });

  test('discovery first request failing remains a failure', () async {
    await expectLater(BiliApi(client: _Client(_offline)).rankHotNovel(),
        throwsA(isA<BiliApiException>()));
  });

  test('valid empty discovery stays a successful empty result', () async {
    final api = BiliApi(client: _Client((_, _) => _search([])));
    expect(await api.rankHotNovel(), isEmpty);
  });

  test('partial discovery keeps the previously received books', () async {
    final client = _Client((url, query) => query['page'] == 1
        ? _search([_book('BV1TEST000001')]) : _offline(url, query));
    expect((await BiliApi(client: client).rankHotNovel()).single.bvid,
        'BV1TEST000001');
  });

  test('one valid empty UP source does not become all-sources failure', () async {
    final client = _Client((url, query) => url == BiliEndpoints.upCollections
        ? {'code': 0, 'data': {'items_lists': {'seasons_list': [], 'series_list': []}}}
        : _offline(url, query));
    expect((await BiliApi(client: client).upAudios(_up)).books, isEmpty);
  });

  test('malformed search response is not a successful empty list', () async {
    final api = BiliApi(client: _Client((_, _) => {'code': 0}));
    await expectLater(api.search('song', mode: ContentMode.music), throwsA(anything));
    await expectLater(api.searchUser('up'), throwsA(anything));
  });

  test('malformed detail is not evidence that the video was deleted', () async {
    final api = BiliApi(client: _Client((_, _) => {'code': 0}));
    try {
      await api.detail('BV1TEST000001');
      fail('Malformed detail must be rejected');
    } on BiliApiException catch (error) {
      expect(error.code, isNot(-404));
    }
  });
}
