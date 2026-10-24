import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../core/network/api_config.dart';
import '../core/network/bili_client.dart';
import '../models/audio_stream.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/content_mode.dart';
import '../models/up_user.dart';

/// UP 合集摊平游标：把该 UP 的多个合集当一条长列表顺序翻页
class _UpCursor {
  final List<int> seasonIds = [];
  final List<Book> preview = [];
  int seasonIdx = 0;
  int seasonPage = 1;

  bool get exhausted => seasonIdx >= seasonIds.length;

  int get currentSeason => seasonIds[seasonIdx];

  _UpCursor copy() => _UpCursor()
    ..seasonIds.addAll(seasonIds)
    ..preview.addAll(preview)
    ..seasonIdx = seasonIdx
    ..seasonPage = seasonPage;

  /// 移到下一个合集
  void advance() {
    seasonIdx++;
    seasonPage = 1;
  }
}

/// B 站听书数据访问层
class BiliApi {
  BiliApi({BiliClient? client}) : _client = client ?? BiliClient.instance;
  static final BiliApi instance = BiliApi();

  final BiliClient _client;

  /// 听书特征词：命中即视为有声内容
  static const _audioHints = <String>[
    '有声小说', '有声书', '有声剧', '有声读物', '有声', '听书', '评书', '相声',
    '广播剧', '演播', '朗读', '诵读', '长书', '连播', '说书', '单口', '播讲',
    '多人剧', '小说剧',
  ];

  /// 明显不是听书内容的特征词（漫推/解说/鬼畜等）
  static const _noiseHints = <String>[
    '一口气看完', '漫推', '漫画', '解说', '讲解', '解读', '动画', '鬼畜', '混剪',
    '沙雕', '速看', 'reaction', '预告', '游戏实况', '配音秀',
  ];

  static bool _hasAudioHint(String s) => _audioHints.any(s.contains);

  /// 题材词：搜索词本身是这些题材时，长内容按听书放行（如「评书 单田芳」）
  static const _genreHints = <String>[
    '评书', '相声', '广播剧', '听书', '演播', '朗读', '诵读', '长书', '连播',
    '说书', '单口', '播讲',
  ];

  /// B 站「动态漫.广播剧」分区（听书内容主分区）
  static const _audioTypeId = 195;

  /// 只保留有声小说/听书类内容。
  ///
  /// 判定优先级（命中噪音词一律剔除）：
  /// 1. 标题含听书特征词且 >= 5 分钟；
  /// 2. 听书主分区（195 动态漫.广播剧）且 >= 10 分钟；
  /// 3. 简介/标签含听书特征词且 >= 30 分钟（防止蹭标签的短视频）；
  /// 4. 搜索词本身是听书题材（评书/相声…）且 >= 30 分钟。
  static bool _isAudiobookItem(Map<String, dynamic> m, String keyword) {
    final title = '${m['title'] ?? ''}';
    final meta = '${m['description'] ?? ''} ${m['tag'] ?? ''}';
    if (_noiseHints.any('$title $meta'.contains)) return false;

    final seconds = Book.parseDurationSeconds(m['duration']);
    if (_hasAudioHint(title) && seconds >= 300) return true;

    final typeid = int.tryParse('${m['typeid'] ?? 0}') ?? 0;
    if (typeid == _audioTypeId && seconds >= 600) return true;

    if (_hasAudioHint(meta) && seconds >= 1800) return true;

    if (_genreHints.any(keyword.contains) && seconds >= 1800) return true;
    return false;
  }

  /// 原始搜索：不改写关键词，按调用入口决定是否启用听书筛选。
  Future<List<Book>> _searchRaw(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    String? order,
    Function(int total)? onFirstPage,
    /// 结果条数回调（未经听书过滤的原始条数），用于判断是否还有下一页
    Function(int rawCount)? onRawCount,
    /// 关闭听书过滤（UP 主场景：已按 mid 精确过滤，不需要再按题材筛）
    bool applyAudioFilter = true,
    ContentMode mode = ContentMode.audiobook,
    CancelToken? cancelToken,
  }) async {
    final res = await _client.get(
      BiliEndpoints.searchType,
      cancelToken: cancelToken,
      query: {
        'search_type': 'video',
        'keyword': keyword,
        'page': page,
        'page_size': pageSize,
        'platform': 'pc',
        'web_location': 1430654,
        if (order != null && order.isNotEmpty) 'order': order,
      },
      useWbi: true,
      headers: {
        'origin': BiliEndpoints.searchHome,
        'referer': '${BiliEndpoints.searchHome}/video'
            '?keyword=${Uri.encodeComponent(keyword)}',
      },
    );
    final result = _searchResult(res.data);
    if (result['v_voucher'] != null) {
      throw BiliApiException(-412, '网络繁忙，请稍后再试');
    }
    final numResults = int.tryParse('${result['numResults'] ?? 0}') ?? 0;
    final list = result['result'] as List? ?? [];
    final books = <Book>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      if (applyAudioFilter && !_isAudiobookItem(m, keyword)) continue;
      final b = Book.fromSearch(m, mode: mode);
      if (b.bvid.isEmpty || b.aid == 0) continue;
      books.add(b);
    }
    onRawCount?.call(list.length);
    onFirstPage?.call(page == 1 ? numResults : 0);
    return books;
  }

  static Map _searchResult(dynamic body) {
    if (body is! Map || body['data'] is! Map) {
      throw BiliApiException(-1, '搜索响应不完整，请重试');
    }
    final data = body['data'] as Map;
    if (data['result'] is! List && data['v_voucher'] == null &&
        !(data['result'] == null && data['numResults'] == 0)) {
      throw BiliApiException(-1, '搜索响应不完整，请重试');
    }
    return data;
  }

  /// 按收听模式搜索。只有听书需要题材过滤和补搜。
  ///
  /// 先用原关键词搜（标题相关性最好），命中太少时再用
  /// 「关键词 有声小说」补搜一次并合并去重。
  /// 补搜只在第 1 页做，避免翻页时请求翻倍触发风控。
  Future<List<Book>> search(
    String keyword, {
    ContentMode mode = ContentMode.audiobook,
    int page = 1,
    int pageSize = 20,
    String? order,
    Function(int total)? onFirstPage,
    Function(int rawCount)? onRawCount,
    CancelToken? cancelToken,
  }) => BiliClient.withRequestBudget(() async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];
    final primary = await _searchRaw(
      kw,
      cancelToken: cancelToken,
      mode: mode,
      applyAudioFilter: mode == ContentMode.audiobook,
      page: page,
      pageSize: pageSize,
      order: order,
      onFirstPage: onFirstPage,
      onRawCount: onRawCount,
    );
    if (page > 1 || mode != ContentMode.audiobook) return primary;
    if (primary.length >= 6 || _hasAudioHint(kw)) return primary;

    try {
      final extra = await _searchRaw(
        '$kw 有声小说',
        cancelToken: cancelToken,
        page: page,
        pageSize: pageSize,
        order: order,
      );
      final seen = primary.map((b) => b.bvid).toSet();
      for (final b in extra) {
        if (seen.add(b.bvid)) primary.add(b);
      }
    } catch (_) {
      if (cancelToken?.isCancelled ?? false) rethrow;
      // 补搜失败不影响主结果
    }
    return primary;
  }, cancelToken: cancelToken);

  /// 热门推荐（榜单）：有声小说按播放量排序，翻页凑量 + 按标题去重
  Future<List<Book>> rankHotNovel({int limit = 30,
    void Function(Object error)? onPartialFailure,
    CancelToken? cancelToken,
  }) => BiliClient.withRequestBudget(() async {
    final all = <Book>[];
    var received = false;
    for (var page = 1; page <= 2; page++) {
      try {
        final list = await _searchRaw(
          '有声小说',
          cancelToken: cancelToken,
          page: page,
          pageSize: 20,
          order: 'click',
        );
        received = true;
        all.addAll(list);
        if (list.isEmpty) break;
      } catch (error) {
        if (cancelToken?.isCancelled ?? false) rethrow;
        if (!received) rethrow;
        onPartialFailure?.call(error);
        break;
      }
    }
    final seen = <String>{};
    final out = <Book>[];
    for (final b in all) {
      if (!seen.add(b.cleanTitle)) continue;
      out.add(b);
      if (out.length >= limit) break;
    }
    return out;
  }, cancelToken: cancelToken);

  /// 书籍详情（含分P章节）
  Future<Book> detail(String bvid,
      {ContentMode mode = ContentMode.audiobook}) async {
    final res = await _client.get(
      BiliEndpoints.view,
      query: {'bvid': bvid},
    );
    final data = res.data as Map;
    if (data['data'] is! Map) {
      throw BiliApiException(-1, '视频信息暂时无法读取，请重试');
    }
    return Book.fromView((data['data'] as Map).cast<String, dynamic>(), mode: mode);
  }

  /// 纯分P列表
  Future<List<Chapter>> pageList(String bvid) async {
    final res = await _client.get(
      BiliEndpoints.pageList,
      query: {'bvid': bvid},
    );
    final data = res.data as Map;
    final list = data['data'] as List? ?? [];
    return list
        .map((e) => Chapter.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 取音频流
  ///
  /// 重试与超时统一由客户端控制；缺少音轨仍作为可重试的失败返回。
  Future<BookAudio> playUrl(String bvid, int cid) async {
    final res = await _client.get(
      BiliEndpoints.playUrl,
      query: {
        'bvid': bvid,
        'cid': cid,
        'qn': 80,
        'fnval': 4048,
        'fnver': 0,
        'fourk': 1,
        'try_look': 1,
        'gaia_source': 'prefer-ua',
      },
      useWbi: true,
    );
    final data = res.data as Map;
    final audio =
        BookAudio.fromMap((data['data'] as Map).cast<String, dynamic>());
    if (_hasPlayableUrl(audio)) return audio;
    throw BiliApiException(-1, '未返回可用音频地址，请重试');
  }

  /// 响应里是否至少有一条可用的音频地址
  static bool _hasPlayableUrl(BookAudio a) {
    if ((a.flac?.baseUrl.isNotEmpty ?? false)) return true;
    if ((a.dolby?.baseUrl.isNotEmpty ?? false)) return true;
    for (final t in a.tracks) {
      if (t.baseUrl.isNotEmpty || t.backupUrls.isNotEmpty) return true;
    }
    return false;
  }

  // ---------- UP 主 ----------

  /// 搜索 UP 主（search_type=bili_user）
  Future<List<UpUser>> searchUser(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    CancelToken? cancelToken,
  }) => BiliClient.withRequestBudget(() async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];
    final res = await _client.get(
      BiliEndpoints.searchType,
      cancelToken: cancelToken,
      query: {
        'search_type': 'bili_user',
        'keyword': kw,
        'page': page,
        'page_size': pageSize,
      },
      useWbi: true,
      headers: {
        'origin': BiliEndpoints.searchHome,
        'referer': '${BiliEndpoints.searchHome}/upuser?keyword='
            '${Uri.encodeComponent(kw)}',
      },
    );
    final result = _searchResult(res.data);
    final list = result['result'] as List? ?? [];
    final out = <UpUser>[];
    for (final item in list) {
      if (item is! Map) continue;
      final u = UpUser.fromSearch(item.cast<String, dynamic>());
      if (u.mid == 0 || u.name.isEmpty) continue;
      out.add(u);
    }
    return out;
  }, cancelToken: cancelToken);

  /// 拉取某个 UP 主的有声内容（只播放这个 UP 的内容）
  ///
  /// 实测结论（B 站匿名访问）：
  /// - `/x/space/wbi/arc/search` 未登录基本必被风控（-352/412），仅登录后可用；
  /// - `/x/polymer/web-space/seasons_series_list` 匿名可用，能拿到该 UP 的合集，
  ///   `data.items_lists` 是 **Map**（含 seasons_list / series_list），不是 List；
  ///   合集里的 archives 只是每集 6 条预览，完整目录要用
  ///   `/x/polymer/web-space/seasons_archives_list` 按 season_id 翻页；
  /// - 搜索接口作为最后兜底（按 mid 过滤）。
  ///
  /// 为避免触发风控，这里用游标把各合集摊平成一条长列表，
  /// 每次只发「尽量少的请求」凑够一页。
  Future<({List<Book> books, bool hasMore})> upAudios(
    UpUser up, {
    ContentMode mode = ContentMode.audiobook,
    int page = 1,
    int pageSize = 30,
    void Function(Object error)? onPartialFailure,
    CancelToken? cancelToken,
  }) => BiliClient.withRequestBudget(() async {
    if (up.mid == 0) return (books: <Book>[], hasMore: false);
    var received = false;
    Object? lastError;
    StackTrace? lastStack;
    try {
      final r = await _upFromCollections(up, cancelToken: cancelToken, page: page, pageSize: pageSize,
          onPartialFailure: onPartialFailure);
      received = true;
      if (r.books.isNotEmpty) {
        return (books: r.books.map((b) => b.withContentMode(mode)).toList(),
            hasMore: r.hasMore);
      }
    } catch (e, stack) {
      if (cancelToken?.isCancelled ?? false) rethrow;
      lastError = e;
      lastStack = stack;
      debugPrint('[BiliApi] 合集取数失败: ${e.runtimeType}');
    }

    // 空间投稿（登录后才稳）
    try {
      final bySpace =
          await _upWorksFromSpace(up, cancelToken: cancelToken, page: page, pageSize: pageSize, mode: mode);
      received = true;
      if (bySpace.isNotEmpty) {
        return (books: bySpace, hasMore: bySpace.length >= pageSize);
      }
    } catch (e, stack) {
      if (cancelToken?.isCancelled ?? false) rethrow;
      lastError = e;
      lastStack = stack;
      debugPrint('[BiliApi] 空间投稿失败: ${e.runtimeType}');
    }

    // 搜索兜底：按 UP 名搜，按 mid 精确过滤
    try {
      final list = await _searchRaw(
        up.name,
        cancelToken: cancelToken,
        mode: mode,
        page: page,
        pageSize: pageSize * 2,
        applyAudioFilter: false,
      );
      received = true;
      final mine = list.where((b) => b.mid == up.mid).toList();
      if (mine.isNotEmpty) {
        return (
          books: mine
              .map((b) => b.author.isEmpty
                  ? Book.fromJson({...b.toJson(), 'author': up.name})
                  : b)
              .toList(),
          hasMore: mine.length >= pageSize,
        );
      }
    } catch (e, stack) {
      if (cancelToken?.isCancelled ?? false) rethrow;
      lastError = e;
      lastStack = stack;
      debugPrint('[BiliApi] UP 搜索兜底失败: ${e.runtimeType}');
    }
    if (!received && lastError != null) {
      Error.throwWithStackTrace(lastError, lastStack!);
    }
    return (books: <Book>[], hasMore: false);
  }, cancelToken: cancelToken);

  /// 每个 UP 的合集摊平游标（跨分页复用，避免重复请求）
  final Map<int, _UpCursor> _upCursors = {};

  /// 合集取数：第 1 页返回「各合集预览 + 首个合集前几页」，之后顺着合集继续翻。
  /// hasMore 由游标真实状态决定，不由返回条数推断 —— 否则撞到请求预算上限时
  /// 会被误判成「没有更多」，后面的视频再也刷不出来。
  Future<({List<Book> books, bool hasMore})> _upFromCollections(UpUser up,
      {required int page, required int pageSize,
        void Function(Object error)? onPartialFailure,
    CancelToken? cancelToken,
  }) async {
    var cursor = _upCursors[up.mid];
    // 第 1 页重新初始化，保证「刷新」拿到的确实是从头开始
    if (cursor == null || page == 1) {
      cursor = _UpCursor();
      // 先登记本次游标，旧初始化晚返回不能覆盖刷新/切换模式后的分页状态。
      _upCursors[up.mid] = cursor;
      try {
        await _initUpCursor(up, cursor, cancelToken: cancelToken);
      } catch (_) {
        if (identical(_upCursors[up.mid], cursor)) _upCursors.remove(up.mid);
        rethrow;
      }
    }
    if (cursor.preview.isEmpty && cursor.seasonIds.isEmpty) {
      return (books: <Book>[], hasMore: false);
    }

    final original = cursor;
    cursor = cursor.copy();
    final out = <Book>[];
    final seen = <String>{};

    // 第 1 页先给各合集的预览条目（瞬间可见）
    if (page == 1) {
      for (final b in cursor.preview) {
        if (seen.add(b.bvid)) out.add(b);
      }
    }

    // 再按合集顺序补齐到 pageSize（每次最多 4 个请求，克制风控）
    for (var guard = 0;
        out.length < pageSize && guard < 4 && !cursor.exhausted;
        guard++) {
      try {
      final season = cursor.currentSeason;
      final res = await _client.get(
        BiliEndpoints.upCollectionArchives,
      cancelToken: cancelToken,
        query: {
          'mid': up.mid,
          'season_id': season,
          'sort_reverse': false,
          'page_num': cursor.seasonPage,
          'page_size': 30,
        },
        headers: {
          'origin': BiliEndpoints.home,
          'referer': BiliEndpoints.spaceHome(up.mid),
        },
      );
      final data = res.data as Map;
      final body = data['data'];
      if (data['code'] != 0 || body is! Map) {
        throw BiliApiException(-1, '合集响应不完整，请重试');
      }
      if (body['archives'] is! List) {
        throw BiliApiException(-1, '合集响应不完整，请重试');
      }
      final archives = body['archives'] as List;
      if (archives.isEmpty) {
        cursor.advance();
        continue;
      }
      var added = 0;
      for (final a in archives) {
        if (a is! Map) continue;
        final b = _bookFromArchive(a.cast<String, dynamic>(), up);
        if (b != null && seen.add(b.bvid)) {
          out.add(b);
          added++;
        }
      }
      if (added == 0) {
        // 这一页全是重复内容，直接换下一个合集
        cursor.advance();
      } else {
        cursor.seasonPage++;
      }
      } catch (error) {
        if (cancelToken?.isCancelled ?? false) rethrow;
        if (out.isEmpty) rethrow;
        onPartialFailure?.call(error);
        break;
      }
    }
    if (identical(_upCursors[up.mid], original)) {
      _upCursors[up.mid] = cursor;
    }

    // 按发布时间倒序，和 B 站空间页观感一致
    if (page == 1) {
      out.sort((a, b) => b.pubdate.compareTo(a.pubdate));
    }
    return (books: out, hasMore: !cursor.exhausted || out.length >= pageSize);
  }

  /// 读取 UP 的合集/系列，写入游标
  Future<void> _initUpCursor(UpUser up, _UpCursor cursor, {CancelToken? cancelToken}) async {
    final res = await _client.get(
      BiliEndpoints.upCollections,
      cancelToken: cancelToken,
      query: {'mid': up.mid, 'page_num': 1, 'page_size': 20},
      headers: {
        'origin': BiliEndpoints.home,
        'referer': BiliEndpoints.spaceHome(up.mid),
      },
    );
    final body = res.data as Map;
    if (body['code'] != 0) throw StateError('collections ${body['code']}');
    final data = body['data'];
    if (data is! Map) throw BiliApiException(-1, '合集响应不完整，请重试');
    // 注意：items_lists 是 Map，不是 List
    final box = data['items_lists'];
    if (box is! Map || (box['seasons_list'] is! List && box['series_list'] is! List)) {
      throw BiliApiException(-1, '合集响应不完整，请重试');
    }

    void collect(List? list) {
      if (list == null) return;
      for (final s in list) {
        if (s is! Map) continue;
        final meta = s['meta'] as Map? ?? {};
        final sid = int.tryParse('${meta['season_id']}') ?? 0;
        if (sid > 0) cursor.seasonIds.add(sid);
        final archives = s['archives'];
        if (archives is List) {
          for (final a in archives) {
            if (a is! Map) continue;
            final b = _bookFromArchive(a.cast<String, dynamic>(), up);
            if (b != null) cursor.preview.add(b);
          }
        }
      }
    }

    collect(box['seasons_list'] as List?);
    collect(box['series_list'] as List?);

    // 预览去重
    final seen = <String>{};
    cursor.preview.removeWhere((b) => !seen.add(b.bvid));
  }

  /// 合集/空间接口的视频条目 → Book（字段为 bvid/title/pic/duration/stat）
  Book? _bookFromArchive(Map<String, dynamic> m, UpUser up) {
    final bvid = m['bvid'] as String? ?? '';
    if (bvid.isEmpty) return null;
    final secs = int.tryParse('${m['duration'] ?? 0}') ?? 0;
    final title = '${m['title'] ?? ''}';
    final stat = m['stat'] as Map? ?? {};
    return Book(
      bvid: bvid,
      aid: int.tryParse('${m['aid'] ?? 0}') ?? 0,
      title: title,
      pic: Book.normalizePic(m['pic'] as String? ?? ''),
      pages: 1,
      duration: secs,
      author: up.name,
      mid: up.mid,
      authorFace: up.face,
      play: int.tryParse('${stat['view'] ?? 0}') ?? 0,
      pubdate: int.tryParse('${m['pubdate'] ?? 0}') ?? 0,
    );
  }

  /// UP 空间投稿（需要登录，未登录大概率风控）
  Future<List<Book>> _upWorksFromSpace(
    UpUser up, {
    ContentMode mode = ContentMode.audiobook,
    int page = 1,
    int pageSize = 30,
    CancelToken? cancelToken,
  }) async {
    final res = await _client.get(
      BiliEndpoints.spaceArcSearch,
      cancelToken: cancelToken,
      query: {
        'mid': up.mid,
        'pn': page,
        'ps': pageSize,
        'order': 'pubdate',
        'platform': 'web',
        'web_location': 1550101,
      },
      useWbi: true,
      headers: {
        'origin': BiliEndpoints.home,
        'referer': BiliEndpoints.space(up.mid),
      },
    );
    final data = res.data as Map;
    if (data['code'] != 0) throw BiliApiException(-352, 'space blocked');
    final body = data['data'];
    if (body is! Map || body['list'] is! Map || body['list']['vlist'] is! List) {
      throw BiliApiException(-1, '投稿响应不完整，请重试');
    }
    final vlist = body['list']['vlist'] as List;
    final out = <Book>[];
    for (final item in vlist) {
      if (item is! Map) continue;
      final b = _bookFromArchive(item.cast<String, dynamic>(), up);
      if (b == null) continue;
      if (mode == ContentMode.audiobook && b.duration > 0 && b.duration < 180) {
        continue; // 保留原听书入口的短视频过滤，歌曲不受此门槛限制。
      }
      out.add(b.withContentMode(mode));
    }
    return out;
  }

  // ---------- 二维码登录（网页 passport 流程） ----------

  /// 获取二维码内容与 key
  Future<({String url, String qrKey})> qrGenerate() async {
    final res = await _client.get(
      BiliEndpoints.qrGenerate,
      query: {'source': 'main-fe-header'},
    );
    final data = (res.data as Map)['data'] as Map? ?? {};
    return (
      url: data['url'] as String? ?? '',
      qrKey: data['qrcode_key'] as String? ?? '',
    );
  }

  /// 轮询二维码状态：success / waiting / scanned / expired / fail
  ///
  /// 成功时 CookieJar 已自动合并 SESSDATA/bili_jct/DedeUserID 并持久化
  Future<String> qrPoll(String qrKey) async {
    final res = await _client.get(
      BiliEndpoints.qrPoll,
      query: {'qrcode_key': qrKey, 'source': 'main-fe-header'},
    );
    final body = res.data as Map;
    // 外层 code 恒为 0，真正状态在 data.code
    final data = body['data'] as Map? ?? {};
    final code = data['code'] as int? ?? -1;
    return switch (code) {
      0 => 'success',
      86038 => 'expired',
      86090 => 'scanned',
      86101 => 'waiting',
      _ => 'fail',
    };
  }

  /// 当前用户信息（nav，登录与否均可用）
  Future<({bool isLogin, String uname, String face})> currentUser() async {
    final res = await _client.get(BiliEndpoints.nav);
    final body = res.data;
    final data = body is Map ? body['data'] : null;
    if (data is! Map || data['isLogin'] is! bool) {
      throw BiliApiException(-1, '账号状态响应不完整，请重试');
    }
    return (
      isLogin: data['isLogin'] == true,
      uname: data['uname'] as String? ?? '',
      face: data['face'] as String? ?? '',
    );
  }
}
