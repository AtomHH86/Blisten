import 'dart:async';

import 'package:blisten/core/network/api_config.dart';
import 'package:blisten/core/network/bili_client.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/models/up_user.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _CursorClient implements BiliClient {
  final oldInitialization = Completer<Response<dynamic>>();
  final oldInitializationStarted = Completer<void>();
  final archiveRequests = <({int season, int page})>[];
  int initializationCount = 0;

  static Response<dynamic> collections(int season) =>
      _response(BiliEndpoints.upCollections, {
        'items_lists': {
          'seasons_list': [
            {
              'meta': {'season_id': season},
              'archives': <Object>[],
            },
          ],
          'series_list': <Object>[],
        },
      });

  static Response<dynamic> _response(String url, Map<String, dynamic> data) =>
      Response<dynamic>(
        requestOptions: RequestOptions(path: url),
        statusCode: 200,
        data: {'code': 0, 'data': data},
      );

  @override
  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? query,
    bool useWbi = false,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    if (url == BiliEndpoints.upCollections) {
      initializationCount++;
      if (initializationCount == 1) {
        oldInitializationStarted.complete();
        return oldInitialization.future;
      }
      return collections(200);
    }
    if (url == BiliEndpoints.upCollectionArchives) {
      final season = query!['season_id'] as int;
      final page = query['page_num'] as int;
      archiveRequests.add((season: season, page: page));
      return _response(url, {
        'archives': [
          {
            'bvid': 'BVseason${season}page$page',
            'aid': season,
            'title': 'season $season page $page',
            'duration': 600,
            'pic': '',
          },
        ],
      });
    }
    throw StateError('Unexpected request: $url');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'late UP initialization cannot replace the latest pagination cursor',
    () async {
      final client = _CursorClient();
      final api = BiliApi(client: client);
      const up = UpUser(mid: 42, name: '测试 UP');

      // An older mode's first page is still initializing when the mode changes.
      final oldFirst = api.upAudios(up, pageSize: 1);
      await client.oldInitializationStarted.future;
      final currentFirst = await api.upAudios(
        up,
        mode: ContentMode.music,
        pageSize: 1,
      );
      expect(currentFirst.books.single.title, 'season 200 page 1');
      expect(currentFirst.hasMore, isTrue);

      // Distinct seasons make a stale cursor visible without relying on timing.
      client.oldInitialization.complete(_CursorClient.collections(100));
      final staleResult = await oldFirst;
      expect(staleResult.books.single.title, 'season 100 page 1');

      final currentSecond = await api.upAudios(
        up,
        mode: ContentMode.music,
        page: 2,
        pageSize: 1,
      );
      expect(currentSecond.books.single.title, 'season 200 page 2');
      expect(currentSecond.books.single.contentMode, ContentMode.music);
      expect(client.archiveRequests, [
        (season: 200, page: 1),
        (season: 100, page: 1),
        (season: 200, page: 2),
      ]);
    },
  );
}
