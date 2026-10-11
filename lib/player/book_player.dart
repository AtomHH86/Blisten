import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide AudioTrack;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_config.dart';
import '../core/storage/cache_store.dart';
import '../core/storage/shelf_store.dart';
import '../models/audio_stream.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../services/audio_focus.dart';
import '../services/bili_api.dart';
import '../services/umeng_analytics.dart';

/// 听书播放器：按"章节"连播 + 断点续播 + 睡眠定时 + 系统媒体会话
class BookPlayer extends ChangeNotifier {
  BookPlayer._();
  static final BookPlayer instance = BookPlayer._();

  final Player _player = Player();
  final BiliApi _api = BiliApi.instance;
  final ShelfStore _shelf = ShelfStore.instance;
  final CacheStore _cache = CacheStore.instance;

  BaseAudioHandler? _audioHandler;
  int _lastStatePush = 0;

  Book? _book;
  List<Chapter> _chapters = [];
  int _index = 0;

  bool _ready = false;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  String? _playbackUrl;
  BookAudio? _lastAudio;

  final Map<int, ({String url, int ts})> _urlCache = {};
  Timer? _positionTimer;
  Timer? _sleepTimer;
  Duration _sleepRemaining = Duration.zero;

  // ---------- 倍速播放 ----------
  /// 听书常用倍速档位（覆盖 1.0 ~ 2.0）
  static const speedSteps = <double>[1.0, 1.25, 1.5, 1.75, 2.0];
  static const _prefRate = 'abts_rate';
  double _rate = 1.0;

  // ---------- 断流自动重连（长音频） ----------
  Timer? _watchdog;
  Duration _lastPos = Duration.zero;
  DateTime _lastPosAt = DateTime.now();
  bool _reconnecting = false;

  /// 播完本集自动暂停（小宇宙同款）：到结尾停下而不是连播下一章
  bool _stopAtChapterEnd = false;
  bool _markingDone = false;

  /// 播放位置（高频，独立于 notifyListeners，避免整页频繁重建）
  final ValueNotifier<Duration> positionTick = ValueNotifier(Duration.zero);

  /// 因系统打断（来电/其他 App 抢占）而暂停：打断结束后自动续播
  bool _pausedByInterruption = false;

  /// 闪避音量（提示音结束后恢复）
  static const double _duckedVolume = 0.05;
  bool _ducking = false;
  double _volumeBeforeDuck = 1.0;

  Player get player => _player;
  Book? get book => _book;
  List<Chapter> get chapters => _chapters;
  int get index => _index;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;
  String? get playbackUrl => _playbackUrl;
  BookAudio? get lastAudio => _lastAudio;
  Duration get sleepRemaining => _sleepRemaining;
  double get rate => _rate;
  bool get stopAtChapterEnd => _stopAtChapterEnd;

  /// 当前是否正在播本地缓存（离线播放）
  bool _isOffline = false;
  bool get isOffline => _isOffline;

  /// 当前章节是否已缓存
  bool get currentCached {
    final b = _book?.bvid;
    final c = currentChapter?.cid;
    if (b == null || c == null || c == 0) return false;
    return _cache.isCached(b, c);
  }

  /// 查本地缓存文件路径；文件不在则视为未缓存
  Future<String?> _cachedPathOf(String? bvid, int cid) async {
    if (bvid == null || bvid.isEmpty || cid == 0) return null;
    final name = _cache.pathOf(bvid, cid);
    if (name == null) return null;
    try {
      final dir = await _audioDir();
      final f = File('$dir/$name');
      if (await f.exists()) return f.path;
      // 文件丢了：清掉索引
      await _cache.remove(bvid, cid);
    } catch (_) {}
    return null;
  }

  Future<Directory> _audioDir() async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    return Directory('${base.path}/audio_cache');
  }

  /// 倍速显示文本（如 1.5 → "1.5x"）
  String get rateLabel {
    final r = _rate;
    return '${r % 1 == 0 ? r.toStringAsFixed(1) : r.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '')}x';
  }

  /// 载入持久化的倍速（启动时调用）
  Future<void> loadRate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_prefRate);
      if (v != null && v >= 0.5 && v <= 3.0) {
        _rate = v;
        await _player.setRate(v);
      }
    } catch (e) {
      debugPrint('[BookPlayer] load rate failed: $e');
    }
  }

  /// 设置倍速并持久化（听书常用 1.25~1.5）
  Future<void> setRate(double v) async {
    _rate = v.clamp(0.5, 3.0);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefRate, _rate);
    } catch (_) {}
    await _player.setRate(_rate);
    _pushState(force: true);
    notifyListeners();
  }

  /// 在档位间循环切换倍速（播放页一键）
  Future<void> cycleSpeed() async {
    final idx = speedSteps.indexWhere((e) => (e - _rate).abs() < 0.001);
    final next = speedSteps[(idx + 1) % speedSteps.length];
    await setRate(next);
  }

  /// 播完本集自动暂停开关
  void setStopAtChapterEnd(bool v) {
    _stopAtChapterEnd = v;
    notifyListeners();
  }

  Chapter? get currentChapter =>
      _chapters.isNotEmpty && _index < _chapters.length
          ? _chapters[_index]
          : null;

  bool get hasNext => _index < _chapters.length - 1;
  bool get hasPrev => _index > 0;

  /// 绑定系统媒体会话（main() 里 AudioService.init 后调用）
  void attachHandler(BaseAudioHandler h) {
    _audioHandler = h;
  }

  /// 初始化（main() 里调用过一次）
  void setup() {
    if (_ready) return;
    _ready = true;
    unawaited(loadRate());
    _player.stream.completed.listen((_) async {
      // media_kit 在 open() 换源时可能抛出一次伪 completed，
      // 用「加载中」与「位置未到结尾」两道判断过滤，避免乱跳章节
      if (_loading || !_loaded) return;
      final dur = currentDuration;
      if (dur > Duration.zero &&
          currentPosition < dur - const Duration(seconds: 3)) {
        return;
      }
      flushProgress();
      _markCurrentDone();
      if (_stopAtChapterEnd) {
        // 播完本集自动暂停：不再连播下一章
        _error = null;
        await _rewindTail();
        await pause();
        debugPrint('[BookPlayer] 本集播放结束，按设置自动暂停');
        notifyListeners();
        return;
      }
      if (hasNext) {
        await next();
      } else {
        _error = null;
        await _rewindTail();
        await pause();
        notifyListeners();
      }
    });
    _player.stream.error.listen((e) async {
      debugPrint('[BookPlayer] player error: $e');
      // 重连进行中再次报错是重连链路的正常噪声，直接忽略，避免覆盖成功状态
      if (_reconnecting) return;
      _loading = false;
      // 长音频断流：先尝试自动重连，重连失败才报错
      if (_loaded) {
        final ok = await _reconnect();
        if (ok) return;
      }
      _error = '播放失败，请稍后重试';
      notifyListeners();
    });
    _player.stream.position.listen((p) {
      positionTick.value = p;
      _tickSave();
      _pushState();
      _tallyPlayTime();
      _markDoneIfReached(p);
    });
    _player.stream.playing.listen((_) {
      _lastPos = currentPosition;
      _lastPosAt = DateTime.now();
      _pushState(force: true);
      notifyListeners();
    });
    _player.stream.buffering.listen((_) {
      _pushState();
      notifyListeners();
    });
    _player.stream.duration.listen((_) {
      _pushState(force: true);
      notifyListeners();
    });

    // 断流看门狗：播放中且长时间（>40s）无进度推进时自动重连
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_reconnecting || !_loaded) return;
      if (!_player.state.playing) {
        _lastPosAt = DateTime.now();
        return;
      }
      final pos = currentPosition;
      if (pos != _lastPos) {
        _lastPos = pos;
        _lastPosAt = DateTime.now();
        return;
      }
      if (DateTime.now().difference(_lastPosAt) > const Duration(seconds: 40)) {
        debugPrint('[BookPlayer] 播放停滞超 40s，触发自动重连');
        unawaited(_reconnect());
      }
    });

    // 音频焦点：被其他 App 抢占时暂停；打断结束后自动续播
    AudioFocus.instance
      ..onFocusInterrupted = () {
        debugPrint('[BookPlayer] 音频焦点被暂时抢占，暂停并等待恢复');
        unawaited(_pauseForInterruption());
      }
      ..onFocusDucked = () {
        unawaited(_duckVolume());
      }
      ..onFocusLost = () {
        debugPrint('[BookPlayer] 音频焦点被永久抢占，暂停');
        _pausedByInterruption = false;
        unawaited(pause());
      }
      ..onFocusGained = () {
        unawaited(_restoreAfterFocusGain());
      }
      ..onNoisy = () {
        // 拔耳机等场景（becomingNoisy）：自动暂停，符合用户预期
        debugPrint('[BookPlayer] 耳机拔出/音频输出变更，自动暂停');
        unawaited(pause());
      }
      ..start();
  }

  /// 断流自动重连：用当前章节的备用音轨地址重开并 seek 回原位置。
  /// 返回是否恢复成功。
  Future<bool> _reconnect({int? keepMs}) async {
    if (_reconnecting) return false;
    _reconnecting = true;
    final resumeMs = keepMs ?? currentPosition.inMilliseconds;
    try {
      final chapter = currentChapter;
      if (chapter == null) return false;
      // 音源视为已失效：重建失败时 resume() 会据此重新载入
      _playbackUrl = null;
      _loading = true;
      notifyListeners();

      // 已缓存的章节直接重开本地文件，无需重新取流
      final local = await _cachedPathOf(_book?.bvid, chapter.cid);
      if (local != null) {
        try {
          await _player.open(Media(local));
          if (_rate != 1.0) await _player.setRate(_rate);
          await _seekToResume(resumeMs);
          _isOffline = true;
          _error = null;
          _loading = false;
          _lastPos = currentPosition;
          _lastPosAt = DateTime.now();
          unawaited(AudioFocus.instance.request());
          _pushState(force: true);
          notifyListeners();
          return true;
        } catch (e) {
          debugPrint('[BookPlayer] 本地重开失败: $e');
          await _cache.remove(_book?.bvid ?? '', chapter.cid);
        }
      }

      // 换一个候选地址重试（清掉旧地址缓存，强制重新取流）
      _urlCache.remove(chapter.cid);
      final candidates = await _fetchStreamCandidates(chapter.cid);
      if (candidates.isEmpty) return false;

      var opened = false;
      for (final url in candidates) {
        try {
          await _player.open(Media(url, httpHeaders: _streamHeaders()),
              play: false);
          // open 之后倍速可能被复位，显式恢复
          if (_rate != 1.0) await _player.setRate(_rate);
          await _seekToResume(resumeMs);
          opened = true;
          _playbackUrl = url;
          break;
        } catch (e) {
          debugPrint('[BookPlayer] 重连候选失败: $e');
          await _player.stop();
        }
      }
      if (!opened) return false;

      _error = null;
      _loading = false;
      _lastPos = currentPosition;
      _lastPosAt = DateTime.now();
      unawaited(AudioFocus.instance.request());
      _pushState(force: true);
      notifyListeners();
      debugPrint('[BookPlayer] 自动重连成功 @${resumeMs}ms');
      return true;
    } catch (e) {
      debugPrint('[BookPlayer] 重连失败: $e');
      return false;
    } finally {
      _reconnecting = false;
      _loading = false;
    }
  }

  /// 播到片尾后回退一小段：否则流已处于 EOF，再按播放会毫无反应
  Future<void> _rewindTail({int seconds = 15}) async {
    try {
      final pos = currentPosition;
      if (pos <= Duration.zero) return;
      final back = pos - Duration(seconds: seconds);
      await _player.seek(back < Duration.zero ? Duration.zero : back);
      positionTick.value = currentPosition;
      _tickSave();
    } catch (e) {
      debugPrint('[BookPlayer] 回退片尾失败: $e');
    }
  }

  /// 系统打断（来电等）导致的暂停：不放弃焦点，等待 GAIN 后自动续播
  Future<void> _pauseForInterruption() async {
    if (!_player.state.playing) return;
    _pausedByInterruption = true;
    await _player.pause();
    _pushState(force: true);
    flushProgress();
  }

  /// 短暂提示音：压低音量（结束后由 onFocusGained 恢复）
  Future<void> _duckVolume() async {
    if (_ducking || !_player.state.playing) return;
    final v = _player.state.volume;
    if (v <= _duckedVolume) return;
    _ducking = true;
    _volumeBeforeDuck = v;
    await _player.setVolume(v * 0.3);
  }

  /// 还原被闪避的音量（幂等）
  Future<void> _restoreVolumeIfDucked() async {
    if (!_ducking) return;
    _ducking = false;
    if (_volumeBeforeDuck > 0) {
      await _player.setVolume(_volumeBeforeDuck);
    }
  }

  /// 焦点恢复：先还原音量，若之前是被打断暂停则续播
  Future<void> _restoreAfterFocusGain() async {
    await _restoreVolumeIfDucked();
    if (!_pausedByInterruption) return;
    debugPrint('[BookPlayer] 音频焦点恢复，继续播放');
    _pausedByInterruption = false;
    await resume();
  }

  /// 累积的真实播放时长：满 1 分钟才自动加入书架（未手动加入时）
  Duration _playTally = Duration.zero;
  Book? _playTallyBook;
  bool _autoShelved = false;
  bool _notificationAsked = false;

  /// 首次播放时按需申请通知权限（Android 13+ 媒体通知需要）。
  /// 放在播放动作里而不是启动时：弹窗有明确上下文，且不阻塞进入应用。
  void _ensureNotificationPermission() {
    if (_notificationAsked || !Platform.isAndroid) return;
    _notificationAsked = true;
    unawaited(() async {
      try {
        await Permission.notification.request();
      } catch (_) {}
    }());
  }

  /// 开始听书：自动从上次进度继续。失败时回滚，保持原播放状态
  /// 返回是否成功进入播放
  Future<bool> playBook(Book book, {int resumeIndex = 0, int resumeMs = 0}) async {
    _ensureNotificationPermission();
    List<Chapter> chapters;
    if (_book?.bvid == book.bvid && _chapters.isNotEmpty) {
      chapters = _chapters; // 同本书复用列表
    } else {
      chapters = book.chapters ?? await _api.pageList(book.bvid);
    }

    if (chapters.isEmpty) {
      _error = '这本书没有可播放的分P';
      _book = book;
      _loaded = false;
      notifyListeners();
      return false;
    }

    // 换本书时重置「播放 1 分钟自动入书架」的累计
    if (_playTallyBook?.bvid != book.bvid) {
      _playTally = Duration.zero;
      _playTallyBook = book;
      _autoShelved = false;
    }

    final idx = resumeIndex >= 0 && resumeIndex < chapters.length
        ? resumeIndex
        : 0;
    return _loadTarget(idx,
        resumeMs: resumeMs, newBook: book, newChapters: chapters);
  }

  /// 从书架进度继续收听
  Future<bool> resumeShelf(ShelfBook sb) async {
    return playBook(
      sb.book,
      resumeIndex: sb.lastChapterIndex,
      resumeMs: sb.positionMs,
    );
  }

  /// 切换到指定章节（index），可选偏移
  Future<void> playChapterIndex(int index, {int offsetMs = 0}) async {
    if (_chapters.isEmpty || index < 0 || index >= _chapters.length) return;
    await _loadTarget(index, resumeMs: offsetMs);
  }

  /// 加载并打开音源：成功才提交新状态，任何一步失败都滚回旧状态
  Future<bool> _loadTarget(
    int index, {
    int resumeMs = 0,
    Book? newBook,
    List<Chapter>? newChapters,
  }) async {
    final prevBook = _book;
    final prevChapters = _chapters;
    final prevIndex = _index;
    final prevLoaded = _loaded;
    final prevUrl = _playbackUrl;
    final prevAudio = _lastAudio;
    final prevOffline = _isOffline;

    if (newBook != null) _book = newBook;
    if (newChapters != null) _chapters = newChapters;
    _loading = true;
    _error = null;
    notifyListeners();

    var ok = false;
    try {
      if (_chapters.isEmpty || index < 0 || index >= _chapters.length) {
        throw StateError('章节索引越界：$index');
      }
      final chapter = _chapters[index];
      // 注意：换章时 newBook 为 null，必须用已提交的 _book 判定缓存
      final curBvid = _book?.bvid;
      final localPath = await _cachedPathOf(curBvid, chapter.cid);

      if (localPath != null) {
        // 已缓存：直接播本地文件，不需要网络地址
        try {
          await _player.open(Media(localPath));
          if (_rate != 1.0) await _player.setRate(_rate);
          if (resumeMs > 0) await _seekToResume(resumeMs);
          ok = true;
          _playbackUrl = null;
          _isOffline = true;
          _pausedByInterruption = false;
        } catch (e) {
          debugPrint('[BookPlayer] 本地缓存打开失败，回退在线: $e');
          // 缓存文件损坏：删除记录后走在线
          await _cache.remove(curBvid ?? '', chapter.cid);
        }
      }

      if (!ok) {
        final candidates = await _fetchStreamCandidates(chapter.cid);
        if (candidates.isEmpty) {
          throw StateError('获取音频链接失败（章节可能无法播放）');
        }

        for (var i = 0; i < candidates.length; i++) {
          final url = candidates[i];
          try {
            // 有续播位置时先打开再精确跳转，保证落点准确到秒
            await _player.open(Media(url, httpHeaders: _streamHeaders()),
                play: resumeMs <= 0);
            // open 后倍速可能被播放器复位，这里显式恢复
            if (_rate != 1.0) await _player.setRate(_rate);
            if (resumeMs > 0) {
              await _seekToResume(resumeMs);
            }
            if (_error != null) _error = null;
            ok = true;
            _playbackUrl = url;
            _isOffline = false;
            _pausedByInterruption = false;
            break;
          } catch (e) {
            debugPrint('[BookPlayer] 候选音轨 $i 打开失败: $e');
            if (i < candidates.length - 1) {
              await _player.stop();
            }
          }
        }
      }

      if (!ok) {
        throw StateError('无法播放该章节');
      }
      // 在线与离线两条路径都要抢占音频焦点
      unawaited(AudioFocus.instance.request());
      _index = index;
      _loaded = true;
      AppAnalytics.onEvent('play_start');
    } catch (e) {
      _error = '播放失败，请稍后重试';
      debugPrint('[BookPlayer] 加载失败: $e');
    } finally {
      if (!ok) {
        _book = prevBook;
        _chapters = prevChapters;
        _index = prevIndex;
        _loaded = prevLoaded;
        _playbackUrl = prevUrl;
        _lastAudio = prevAudio;
        _isOffline = prevOffline;
      }
      _loading = false;
      _pushNowPlaying();
      notifyListeners();
    }
    return ok;
  }

  /// 精确续播：等媒体就绪后跳转，并校验落点（首次 seek 可能被播放器忽略）
  Future<void> _seekToResume(int resumeMs) async {
    final target = Duration(milliseconds: resumeMs);
    await _waitForDuration();
    await _player.seek(target);
    await _player.play();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final off = (_player.state.position - target).inMilliseconds.abs();
    if (off > 5000) {
      debugPrint('[BookPlayer] 续播落点偏差 ${off}ms，重新跳转');
      await _player.seek(target);
    }
  }

  /// 等待播放器拿到时长（最多 4 秒）
  Future<void> _waitForDuration() async {
    if (_player.state.duration > Duration.zero) return;
    try {
      await _player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // 超时继续，交由落点校验兜底
    }
  }

  /// media_kit 请求流媒体时需要的请求头（否则 B 站 CDN 返回 403/412）
  Map<String, String> _streamHeaders() => const {
        'User-Agent': BiliEndpoints.userAgent,
        'Referer': BiliEndpoints.home,
      };

  /// 候选音频地址列表：AAC 优先（稳定），flac/dolby 兜底；百度 http 转 https
  Future<List<String>> _fetchStreamCandidates(int cid) async {
    final cached = _urlCache[cid];
    if (cached != null) {
      final ageMs = DateTime.now().millisecondsSinceEpoch - cached.ts;
      if (ageMs < 90 * 60 * 1000) return [cached.url];
    }
    final audio = await _api.playUrl(_book!.bvid, cid);
    _lastAudio = audio;
    debugPrint('[BookPlayer] 拿到音频: ${audio.tracks.length}条AAC '
        'flac=${audio.flac?.baseUrl.isNotEmpty} dolby=${audio.dolby?.baseUrl.isNotEmpty}');

    final list = <String>[];
    void add(AudioTrack? t) {
      if (t == null) return;
      String toHttps(String u) =>
          u.startsWith('http://') ? 'https://${u.substring(7)}' : u;
      if (t.baseUrl.isNotEmpty) list.add(toHttps(t.baseUrl));
      for (final b in t.backupUrls) {
        if (b.isNotEmpty) list.add(toHttps(b));
      }
    }

    final aac = [...audio.tracks]..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    for (final t in aac) {
      add(t);
    }
    add(audio.flac);
    add(audio.dolby);

    final uniq = list.toSet().toList();
    if (uniq.isNotEmpty) {
      _urlCache[cid] =
          (url: uniq.first, ts: DateTime.now().millisecondsSinceEpoch);
      if (_urlCache.length > 6) {
        final eldest = _urlCache.keys.first;
        _urlCache.remove(eldest);
      }
    }
    return uniq;
  }

  // ---------- 系统媒体会话 ----------
  void _pushNowPlaying() {
    final h = _audioHandler;
    if (h == null) return;
    final chapter = currentChapter;
    if (chapter == null || _book == null) return;
    final dur = currentDuration;
    final pic = Book.normalizePic(_book!.pic);
    h.mediaItem.add(
      MediaItem(
        id: '${_book!.bvid}/${chapter.cid}',
        title: '第 ${chapter.page} 章 · ${chapter.part}',
        artist: _book!.cleanTitle,
        album: _book!.cleanTitle,
        artUri: pic.isEmpty ? null : Uri.tryParse(pic),
        duration:
            dur > Duration.zero ? dur : Duration(seconds: chapter.duration),
      ),
    );
    _pushState(force: true);
  }

  void _pushState({bool force = false}) {
    final h = _audioHandler;
    if (h == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastStatePush < 500) return;
    _lastStatePush = now;

    final playing = _player.state.playing;
    final pos = currentPosition;
    // 真实缓冲位置：之前误传总时长，会让通知栏进度条/状态显示错位
    final buffered = _player.state.buffer;
    final buf = buffered > pos ? buffered : pos;

    final processing = _loading || _player.state.buffering
        ? AudioProcessingState.buffering
        : _error != null
            ? AudioProcessingState.error
            : _loaded
                ? AudioProcessingState.ready
                : AudioProcessingState.idle;

    h.playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.rewind,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
          MediaControl.skipToNext,
        ],
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processing,
        playing: playing,
        updatePosition: pos,
        bufferedPosition: buf,
      ),
    );
  }

  // ---------- 播放控制 ----------
  void togglePlay() {
    final willPlay = !_player.state.playing;
    _pausedByInterruption = false;
    if (willPlay) {
      unawaited(resume());
    } else {
      unawaited(pause());
    }
    _pushState(force: true);
  }

  Future<void> resume() async {
    _pausedByInterruption = false;
    await _restoreVolumeIfDucked();
    // 断流重连彻底失败后播放器会停在 stop 状态，此时直接 play() 是无效的
    // （对应「点了播放没反应」），这里重新载入当前章节再播。
    if (_loaded && _playbackUrl == null && !_reconnecting) {
      final ok = await _reconnect();
      if (ok) return;
    }
    await _player.play();
    unawaited(AudioFocus.instance.request());
    _pushState(force: true);
  }

  Future<void> pause() async {
    _pausedByInterruption = false;
    await _player.pause();
    unawaited(AudioFocus.instance.abandon());
    _pushState(force: true);
    flushProgress();
  }

  Future<void> next() async {
    if (!hasNext) return;
    await playChapterIndex(_index + 1);
  }

  Future<void> previous() async {
    if (!hasPrev) return;
    await playChapterIndex(_index - 1);
  }

  Future<void> seek(Duration to) async {
    await _player.seek(to);
    _pushState(force: true);
  }

  Future<void> seekRelative(int seconds) async {
    final target = currentPosition + Duration(seconds: seconds);
    await seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> stop() async {
    _pausedByInterruption = false;
    await _player.stop();
    unawaited(AudioFocus.instance.abandon());
    _loaded = false;
    _playbackUrl = null;
    _reconnecting = false;
    positionTick.value = Duration.zero;
    _positionTimer?.cancel();
    _watchdog?.cancel();
    final h = _audioHandler;
    if (h != null) {
      h.mediaItem.add(null);
      h.playbackState.add(
        h.playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          playing: false,
          updatePosition: Duration.zero,
        ),
      );
    }
    notifyListeners();
  }

  /// 书籍启用中（真实播放超过 1 分钟）自动加入书架
  static const Duration _autoShelfAfter = Duration(minutes: 1);

  /// 正在计数的是哪个 bvid
  String? _tallyBvid;
  /// 上次出现的位置，用来累计增量
  Duration _lastTallyPos = Duration.zero;

  /// 累计真实播放时长；满 1 分钟且不在书架上时自动加入
  void _tallyPlayTime() {
    final book = _book;
    if (book == null || !_loaded) return;
    if (currentDuration <= Duration.zero) return;

    final pos = currentPosition;
    if (_tallyBvid != book.bvid) {
      _tallyBvid = book.bvid;
      _lastTallyPos = pos;
      return;
    }
    final delta = pos - _lastTallyPos;
    _lastTallyPos = pos;
    // 忽略异常跳变（seek / 换章位置归零 / 暂停期间无输出）
    if (delta <= Duration.zero || delta > const Duration(seconds: 60)) {
      return;
    }
    _playTally += delta;
    if (_playTally >= _autoShelfAfter && !_autoShelved) {
      _autoShelved = true;
      if (!_shelf.isOnShelf(book.bvid)) {
        unawaited(_shelf.add(book));
        AppAnalytics.onEvent('shelf_add_auto');
      }
    }
  }

  /// 把当前章节标记为「已听完」并入库
  void _markCurrentDone() {
    if (_markingDone) return;
    _markingDone = true;
    final chapter = currentChapter;
    final book = _book;
    _markingDone = false;
    if (chapter == null || book == null) return;
    if (!_shelf.isOnShelf(book.bvid)) return;
    _shelf.markChapterDone(book.bvid, chapter.cid);
  }

  /// 播到接近结尾（>=95%）自动打「已听」标记，不等 completed 事件
  void _markDoneIfReached(Duration pos) {
    final chapter = currentChapter;
    final book = _book;
    final dur = currentDuration;
    if (chapter == null || book == null || dur <= Duration.zero) return;
    if (pos < dur * 0.95) return;
    if (!_shelf.isOnShelf(book.bvid)) return;
    _shelf.markChapterDone(book.bvid, chapter.cid);
  }

  Map<String, String> get downloadHeaders => _streamHeaders();

  /// 直接播放缓存里的一集（离线入口，缓存页调用）
  ///
  /// 从缓存页进来时只有 bvid/cid，没有完整章节列表；
  /// 先尝试拉章节列表（失败也不阻塞，缓存页只有一集时用单集占位）。
  Future<bool> playCachedEntry(String bvid, int cid, Book book) async {
    _ensureNotificationPermission();
    List<Chapter> chapters;
    try {
      chapters = await _api.pageList(bvid);
    } catch (_) {
      chapters = const [];
    }

    var index = chapters.indexWhere((c) => c.cid == cid);
    if (index < 0) {
      // 列表里没有这一集（可能是多 P 的某一集），补一个占位章节
      chapters = [
        Chapter(cid: cid, page: 1, part: book.cleanTitle),
      ];
      index = 0;
    }

    final local = await _cachedPathOf(bvid, cid);
    if (local == null) return false;

    final prevBook = _book;
    final prevChapters = _chapters;
    final prevIndex = _index;
    final prevLoaded = _loaded;

    _book = book;
    _chapters = chapters;
    _index = index;
    _loading = true;
    _error = null;
    notifyListeners();

    var ok = false;
    try {
      await _player.open(Media(local));
      if (_rate != 1.0) await _player.setRate(_rate);
      _playbackUrl = null;
      _isOffline = true;
      ok = true;
    } catch (e) {
      debugPrint('[BookPlayer] 缓存播放失败: $e');
      _book = prevBook;
      _chapters = prevChapters;
      _index = prevIndex;
      _loaded = prevLoaded;
    } finally {
      _loading = false;
      if (ok) {
        _loaded = true;
        unawaited(AudioFocus.instance.request());
        _pushNowPlaying();
      }
      notifyListeners();
    }
    return ok;
  }

  /// 取任意 (bvid, cid) 的下载地址（详情页缓存单集时用）
  Future<String?> resolveUrlFor(String bvid, int cid) async {
    try {
      final cached = _urlCache[cid];
      if (cached != null &&
          DateTime.now().millisecondsSinceEpoch - cached.ts <
              90 * 60 * 1000) {
        return cached.url;
      }
      final audio = await _api.playUrl(bvid, cid);
      final urls = <String>[];
      String toHttps(String u) =>
          u.startsWith('http://') ? 'https://${u.substring(7)}' : u;
      void add(AudioTrack? t) {
        if (t == null) return;
        if (t.baseUrl.isNotEmpty) urls.add(toHttps(t.baseUrl));
        for (final b in t.backupUrls) {
          if (b.isNotEmpty) urls.add(toHttps(b));
        }
      }

      final aac = [...audio.tracks]..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      for (final t in aac) {
        add(t);
      }
      add(audio.flac);
      add(audio.dolby);
      final uniq = urls.toSet().toList();
      if (uniq.isEmpty) return null;
      _urlCache[cid] = (url: uniq.first, ts: DateTime.now().millisecondsSinceEpoch);
      if (_urlCache.length > 12) {
        _urlCache.remove(_urlCache.keys.first);
      }
      return uniq.first;
    } catch (e) {
      debugPrint('[BookPlayer] 取下载地址失败: $e');
      return null;
    }
  }

  /// 缓存播放位置（用于离线时恢复进度不依赖网络）
  Duration? get position => _player.state.duration > Duration.zero
      ? _player.state.position
      : null;
  Duration get currentPosition => _player.state.position;
  Duration get currentDuration => _player.state.duration;
  bool get isPlaying => _player.state.playing;
  bool get buffering => _player.state.buffering;

  /// 进度落库（节流，每 ~2 秒持久化一次；取值在落库时刻读取，保证精确）
  Timer? _lastSaveTimer;
  void _tickSave() {
    if (currentChapter == null || _book == null) return;
    if (currentDuration <= Duration.zero) return;
    _lastSaveTimer?.cancel();
    _lastSaveTimer = Timer(const Duration(seconds: 2), _saveNow);
  }

  void _saveNow() {
    if (_loading) return; // 切章过程中不落库，避免记录错章节
    final chapter = currentChapter;
    final book = _book;
    if (chapter == null || book == null) return;
    final pos = currentPosition;
    final dur = currentDuration;
    if (dur <= Duration.zero) return;
    _shelf.updateProgress(
      book.bvid,
      cid: chapter.cid,
      chapterIndex: _index,
      positionMs: pos.inMilliseconds,
      chapterDurationMs: dur.inMilliseconds,
    );
  }

  /// 手动留存进度（章节切换/退后台/退出时调用）
  void flushProgress() {
    _lastSaveTimer?.cancel();
    _saveNow();
  }

  // ---------- 睡眠定时 ----------
  void setSleepTimer(Duration d) {
    _sleepTimer?.cancel();
    _sleepRemaining = d;
    AppAnalytics.onEvent('sleep_timer_use', {'minutes': d.inMinutes});
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _sleepRemaining -= const Duration(seconds: 1);
      if (_sleepRemaining <= Duration.zero) {
        t.cancel();
        _sleepRemaining = Duration.zero;
        pause();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepRemaining = Duration.zero;
    notifyListeners();
  }
}