import 'package:abts/core/network/bili_client.dart';
import 'package:abts/models/content_mode.dart';
import 'package:abts/models/up_user.dart';
import 'package:abts/services/bili_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class SearchClient implements BiliClient {
  final calls = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> Function(Map<String, dynamic>) results;

  SearchClient(this.results);

  @override
  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? query,
    bool useWbi = false,
    Map<String, String>? headers,
  }) async {
    final request = Map<String, dynamic>.from(query!);
    calls.add(request);
    return Response<dynamic>(
      requestOptions: RequestOptions(path: url),
      data: {
        'code': 0,
        'message': '0',
        'data': {'result': results(request), 'numResults': 40},
      },
      statusCode: 200,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> video(String bvid, String title, String duration) => {
  'bvid': bvid,
  'aid': 1,
  'title': title,
  'pic': '//example.invalid/cover.jpg',
  'duration': duration,
  'videos': 1,
  'author': '上传者',
  'mid': 42,
  'play': 200,
  'pubdate': 1,
  'description': '',
  'tag': '',
  'typeid': 0,
};

class UpClient implements BiliClient {
  @override
  Future<Response<dynamic>> get(String url, {
    Map<String, dynamic>? query,
    bool useWbi = false,
    Map<String, String>? headers,
  }) async => Response<dynamic>(
    requestOptions: RequestOptions(path: url),
    data: {
      'code': 0,
      'data': url.contains('arc/search')
          ? {'list': {'vlist': [{
              'bvid': 'BV1xx411c7mD', 'aid': 1, 'title': '两分钟歌曲',
              'duration': 120, 'pic': '', 'stat': {'view': 10}, 'pubdate': 1,
            }]}}
          : url.contains('search/type')
              ? {'result': [], 'numResults': 0}
              : {'items_lists': {'seasons_list': [], 'series_list': []}},
    },
    statusCode: 200,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('music UP page retains songs shorter than the audiobook duration floor', () async {
    final result = await BiliApi(client: UpClient()).upAudios(
      UpUser(mid: 42, name: '上传者', face: ''), mode: ContentMode.music);
    expect(result.books.map((b) => b.bvid), ['BV1xx411c7mD']);
    expect(result.books.single.contentMode, ContentMode.music);
  });

  test('default UP page retains its existing short-video exclusion', () async {
    final result = await BiliApi(client: UpClient()).upAudios(
      UpUser(mid: 42, name: '上传者', face: ''));
    expect(result.books, isEmpty);
  });

  test(
    'music returns a three-minute song without audiobook supplementation',
    () async {
      final client = SearchClient(
        (_) => [video('BV1xx411c7mD', '晴天 MV', '3:00')],
      );
      final result = await BiliApi(
        client: client,
      ).search('晴天', mode: ContentMode.music);
      expect(result.map((b) => b.title), ['晴天 MV']);
      expect(result.single.contentMode, ContentMode.music);
      expect(client.calls.map((q) => q['keyword']), ['晴天']);
    },
  );

  test(
    'concert accepts a long live video without audiobook keywords',
    () async {
      final client = SearchClient(
        (_) => [video('BV1xx411c7mD', '巡回演唱会全场', '2:00:00')],
      );
      final result = await BiliApi(
        client: client,
      ).search('巡回演唱会', mode: ContentMode.concert);
      expect(result.single.contentMode, ContentMode.concert);
      expect(client.calls, hasLength(1));
    },
  );

  test(
    'default audiobook still rejects short music and supplements the keyword',
    () async {
      final client = SearchClient(
        (q) => q['keyword'] == '三体'
            ? [video('BV1xx411c7mD', '歌曲', '3:00')]
            : [video('BV1yy411c7mD', '三体 有声小说', '60:00')],
      );
      final result = await BiliApi(client: client).search('三体');
      expect(client.calls.map((q) => q['keyword']), ['三体', '三体 有声小说']);
      expect(result.map((b) => b.bvid), ['BV1yy411c7mD']);
      expect(result.single.contentMode, ContentMode.audiobook);
    },
  );

  test(
    'music pagination keeps mode and reports the unfiltered page size',
    () async {
      final client = SearchClient(
        (_) => [video('BV1xx411c7mD', '现场歌曲', '2:50')],
      );
      var rawCount = -1;
      final result = await BiliApi(client: client).search(
        '现场',
        page: 2,
        mode: ContentMode.music,
        onRawCount: (n) => rawCount = n,
      );
      expect(client.calls.single['page'], 2);
      expect(client.calls.single['keyword'], '现场');
      expect(result.single.contentMode, ContentMode.music);
      expect(rawCount, 1);
    },
  );
}
