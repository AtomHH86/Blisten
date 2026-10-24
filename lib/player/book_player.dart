import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide AudioTrack;
import 'package:permission_handler/permission_handler.dart';

import '../core/network/api_config.dart';
import '../core/network/bili_client.dart';
import '../core/storage/cache_store.dart';
import '../core/storage/shelf_store.dart';
import '../models/audio_stream.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/content_mode.dart';
import '../services/audio_focus.dart';
import '../services/bili_api.dart';
import '../services/umeng_analytics.dart';
import 'playback_preferences.dart';

/// 从缓存页播放一集的结果
///
/// 「文件不存在」和「文件在但打不开」是两回事：前者要提示重新缓存，
/// 后者缓存是好的，只需要告诉用户这次改成了在线播放。
enum CachePlayOutcome { okOffline, okOnline, fileMissing, failed }

/// 从书架播放一本书的结果
///
/// 「没网」和「作品已下架」要分开：前者应该退回离线缓存/提示网络，
/// 后者要问用户是否把这本已经听不了的书移出书架。
enum ShelfPlayOutcome { ok, bookGone, loadFailed }

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

  /// _chapters 是否来自完整目录（在线/书里带的）。
  /// 离线时目录可能是从缓存索引拼的，只有已缓存的那几集。
  bool _chaptersComplete = true;
  int _index = 0;

  bool _ready = false;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  String? _playbackUrl;
  BookAudio? _lastAudio;

  // 只保留最近一次失败的播放目标；重试沿用当次分 P 和偏移，
  // 不能重新套用「重新选择歌曲从首曲开始」的入口规则。
  ({Book book, List<Chapter> chapters, int index, int positionMs,
    int? cid, bool complete})? _failedTarget;
  int _loadGeneration = 0;
  String? _pendingBvid;
  final Set<String> _clearedRecords = {};
  // 用户的最新播放意图独立于资源加载代次；晚到的请求不得逆转暂停。
  bool _wantsPlayback = false;
  bool _preserveCompletedProgress = false;
  int? _nativeLoadGeneration;
  Completer<void>? _nativeLoadError;

  final Map<int, ({String url, int ts})> _urlCache = {};
  Timer? _sleepTimer;
  Duration _sleepRemaining = Duration.zero;

  // ---------- 倍速播放 ----------
  /// 倍速档位：0.5x ~ 3.0x；另外支持自定义任意值（0.5~3.0，步进 0.05）
  static const speedSteps = <double>[
    0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0,
  ];
  static const double minRate = 0.5;
  static const double maxRate = 3.0;
  final PlaybackPreferences _preferences = PlaybackPreferences();
  double _rate = 1.0;

  // ---------- 断流自动重连（长音频） ----------
  // 断流看门狗与系统状态校正器在 setup() 里创建后随单例存活，
  // 故意不随 stop() 取消（stop 可由通知栏触发，取消后功能会永久失效）。
  /// 当前是否已成功打开音源（在线 URL 或本地文件都算）。
  /// 用它判断「音源是否还活着」，不能用 _playbackUrl：离线播放时 URL 本来就是 null。
  bool _mediaReady = false;
  /// 会话代号：stop() 会自增，进行中的重连发现代号变了就放弃，避免停止后又被唤醒播放
  int _session = 0;
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
    // 路径解析与「文件是否真的在」统一交给 CacheStore 判断，
    // 这里不要自己拼路径查 exists()，否则两处结论会不一致
    if (!_cache.isCached(bvid, cid)) return null;
    return _cache.cacheFilePath(bvid, cid);
  }

  /// 倍速显示文本（如 1.5 → "1.5x"）
  String get rateLabel {
    final r = _rate;
    return '${r % 1 == 0 ? r.toStringAsFixed(1) : r.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '')}x';
  }

  /// 启动时载入听书倍速；选定作品后的倍率由加载音源路径负责。
  Future<void> loadRate() async {
    try {
      final rate = await _preferences.rateFor(ContentMode.audiobook);
      // setup 是异步的，晚到的启动设置不能覆盖已选作品的模式。
      if (_book != null || _loading) return;
      _rate = rate;
      await _player.setRate(rate);
    } catch (e) {
      debugPrint('[BookPlayer] load rate failed: ${e.runtimeType}');
    }
  }

  /// 为当前内容模式设置并记忆倍速。
  Future<void> setRate(double v) async {
    _rate = v.clamp(0.5, 3.0);
    try {
      await _preferences.saveRate(
          _book?.contentMode ?? ContentMode.audiobook, _rate);
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
    _player.stream.completed.listen((completed) async {
      if (!completed) return;
      // media_kit 在 open() 换源时可能抛出一次伪 completed，
      // 用「加载中」与「位置未到结尾」两道判断过滤，避免乱跳章节
      if (_loading || !_loaded) return;
      final dur = currentDuration;
      if (dur > Duration.zero &&
          currentPosition < dur - const Duration(seconds: 3)) {
        return;
      }
      final completedGeneration = _loadGeneration;
      final completedSession = _session;
      bool stillCurrent() => completedGeneration == _loadGeneration &&
          completedSession == _session;
      flushProgress();
      _preserveCompletedProgress = true;
      _markCurrentDone();
      if (_stopAtChapterEnd) {
        // 播完本集自动暂停：不再连播下一章
        _error = null;
        await _rewindTail();
        if (!stillCurrent()) return;
        await pause();
        if (!stillCurrent()) return;
        // 回退片尾是为了「再按播放能重听结尾」，但进度要记到下一章，
        // 否则「继续收听」会把已经打完 ✓ 的这一章又翻出来重播
        _advanceSavedProgress();
        debugPrint('[BookPlayer] 本集播放结束，按设置自动暂停');
        notifyListeners();
        return;
      }
      if (hasNext && _wantsPlayback) {
        await next();
      } else {
        _error = null;
        await _rewindTail();
        if (!stillCurrent()) return;
        await pause();
        if (!stillCurrent()) return;
        notifyListeners();
      }
    });
    _player.stream.error.listen((e) async {
      debugPrint('[BookPlayer] player error');
      // 只有本代已经开始打开音源时，原生错误才归属该加载链。
      // 目录仍在等待时的旧音源错误不能接管新请求的 loading。
      if (_loading) {
        final error = _nativeLoadError;
        if (_nativeLoadGeneration == _loadGeneration &&
            error != null && !error.isCompleted) {
          error.complete();
        }
        return;
      }
      if (_reconnecting) return;
      // 长音频断流：先尝试自动重连，重连失败才报错
      if (_loaded) {
        final generation = _loadGeneration;
        final session = _session;
        final retryBook = _book;
        final retryTarget = retryBook == null ? null : (
          book: retryBook, chapters: List<Chapter>.of(_chapters),
          index: _index, positionMs: currentPosition.inMilliseconds,
          cid: currentChapter?.cid,
          complete: _chaptersComplete,
        );
        final ok = await _reconnect();
        if (ok) return;
        // 重连可能清空原生位置，失败后仍从发生错误前的位置重试。
        if (generation != _loadGeneration || session != _session) return;
        _failedTarget = retryTarget;
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
    Timer.periodic(const Duration(seconds: 5), (_) {
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

    // 系统媒体会话状态校正：App 内实际播放状态与已推送给系统的不一致时补推一次。
    // media_kit 的 playing 状态是异步落地的，来电/锁屏/通知栏操作等竞态下
    // 偶尔会出现系统显示与 App 不一致，这里做兜底自愈。
    Timer.periodic(const Duration(seconds: 2), (_) {
      final h = _audioHandler;
      if (h == null) return;
      final actual = _player.state.playing;
      final remote = h.playbackState.value;
      if (remote.playing == actual) return;
      debugPrint('[BookPlayer] 校正系统播放状态 ${remote.playing} -> $actual');
      _pushState(force: true);
    });

    // 音频焦点：被其他 App 抢占时暂停；打断结束后自动续播
    AudioFocus.instance
      ..onFocusInterrupted = () {
        debugPrint('[BookPlayer] 音频焦点被暂时抢占，暂停并等待恢复');
        unawaited(_pauseForInterruption());
      }
      ..onFocusDucked = () {
        if (AudioFocus.instance.pausesOnDuck) {
          unawaited(_pauseForInterruption());
        } else {
          unawaited(_duckVolume());
        }
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
    if (_reconnecting || _loading) return false;
    _reconnecting = true;
    // 新选择和停止都使旧重连失效，旧请求不能触碰新会话的音源与状态。
    final mySession = _session;
    final generation = _loadGeneration;
    bool stillCurrent() => mySession == _session && generation == _loadGeneration;
    final resumeMs = keepMs ?? currentPosition.inMilliseconds;
    final book = _book;
    final chapter = currentChapter;
    final rate = _rate;
    try {
      if (book == null || chapter == null) return false;
      // 先保存旧会话，再关闭保存入口。重开失败产生的原生 0 位置
      // 不属于成功会话，不能覆盖断点；resume 也应重新尝试载入。
      flushProgress();
      _mediaReady = false;
      _playbackUrl = null;
      _loading = true;
      notifyListeners();

      // 已缓存的章节直接重开本地文件，无需重新取流
      final local = await _cachedPathOf(book.bvid, chapter.cid);
      if (!stillCurrent()) return false;
      if (local != null) {
        try {
          final nativeError = _beginNativeLoad(generation);
          await _player.open(Media(local), play: false);
          if (!stillCurrent()) return false;
          await _waitForNativeLoad(nativeError);
          if (!stillCurrent()) return false;
          await _player.setRate(rate);
          if (!stillCurrent()) return false;
          await _seekToResume(resumeMs, mode: book.contentMode,
              stillCurrent: () => stillCurrent() && !nativeError.isCompleted);
          if (!stillCurrent()) return false;
          if (nativeError.isCompleted) throw StateError('原生音源加载失败');
          _isOffline = true;
          _mediaReady = true;
          _error = null;
          _loading = false;
          _lastPos = currentPosition;
          _lastPosAt = DateTime.now();
          _pushState(force: true);
          notifyListeners();
          return true;
        } catch (e) {
          if (!stillCurrent()) return false;
          debugPrint('[BookPlayer] 本地重开失败: ${e.runtimeType}');
          await _cache.dropIfBroken(book.bvid, chapter.cid);
          if (!stillCurrent()) return false;
        }
      }

      // 换一个候选地址重试（清掉旧地址缓存，强制重新取流）
      _urlCache.remove(chapter.cid);
      final source = await _fetchStreamCandidates(chapter.cid,
          bvid: book.bvid, stillCurrent: stillCurrent);
      if (!stillCurrent() || source.urls.isEmpty) return false;
      final candidates = source.urls;

      var opened = false;
      for (final url in candidates) {
        try {
          final nativeError = _beginNativeLoad(generation);
          await _player.open(Media(url, httpHeaders: _streamHeaders()), play: false);
          if (!stillCurrent()) return false;
          await _waitForNativeLoad(nativeError);
          if (!stillCurrent()) return false;
          // open 之后倍速可能被复位，这里显式恢复
          await _player.setRate(rate);
          if (!stillCurrent()) return false;
          await _seekToResume(resumeMs, mode: book.contentMode,
              stillCurrent: () => stillCurrent() && !nativeError.isCompleted);
          if (!stillCurrent()) return false;
          if (nativeError.isCompleted) throw StateError('原生音源加载失败');
          opened = true;
          _playbackUrl = url;
          break;
        } catch (e) {
          if (!stillCurrent()) return false;
          debugPrint('[BookPlayer] 重连候选失败: ${e.runtimeType}');
          await _player.stop();
          if (!stillCurrent()) return false;
        }
      }
      if (!opened) return false;

      _lastAudio = source.audio ?? _lastAudio;
      _error = null;
      _loading = false;
      _mediaReady = true;
      _lastPos = currentPosition;
      _lastPosAt = DateTime.now();
      _pushState(force: true);
      notifyListeners();
      debugPrint('[BookPlayer] 自动重连成功 @${resumeMs}ms');
      return true;
    } catch (e) {
      debugPrint('[BookPlayer] 重连失败: ${e.runtimeType}');
      return false;
    } finally {
      if (stillCurrent()) {
        _nativeLoadGeneration = null;
        _nativeLoadError = null;
        _reconnecting = false;
        _loading = false;
      }
    }
  }

  /// 把已保存的进度指向下一章开头（本章已听完时调用）
  void _advanceSavedProgress() {
    final book = _book;
    if (book == null || !hasNext) return;
    if (_clearedRecords.contains(book.bvid)) return;
    if (_shelf.progressByBvid(book.bvid) == null) return;
    final nextIndex = _index + 1;
    if (nextIndex < 0 || nextIndex >= _chapters.length) return;
    final nextChapter = _chapters[nextIndex];
    unawaited(_shelf.updateProgress(
      book.bvid,
      book: book,
      cid: nextChapter.cid,
      chapterIndex: nextIndex,
      positionMs: 0,
      chapterDurationMs: nextChapter.duration * 1000,
      chapters: _chapters,
      chaptersComplete: _chaptersComplete,
    ));
  }

  /// 播到片尾后回退一小段：否则流已处于 EOF，再按播放会毫无反应
  Future<void> _rewindTail({int seconds = 15}) async {
    try {
      final pos = currentPosition;
      if (pos <= Duration.zero) return;
      final back = pos - Duration(seconds: seconds);
      await _player.seek(back < Duration.zero ? Duration.zero : back);
      // 这里刻意不落库：回退位置只是为了「再按播放能重听结尾」，
      // 不是用户真实的收听进度，落库会把它当成续播点。
      positionTick.value = currentPosition;
    } catch (e) {
      debugPrint('[BookPlayer] 回退片尾失败: ${e.runtimeType}');
    }
  }

  /// 系统打断（来电等）导致的暂停：不放弃焦点，等待 GAIN 后自动续播
  Future<void> _pauseForInterruption() async {
    if (!_wantsPlayback) return;
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
    final generation = _loadGeneration;
    final session = _session;
    bool current() => generation == _loadGeneration && session == _session;
    await _restoreVolumeIfDucked();
    if (!current() || !_wantsPlayback || !_pausedByInterruption) return;
    _pausedByInterruption = false;
    if (_loading || _reconnecting) return;
    await _playIfIntended(current);
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

  int _beginLoad([String? bvid]) {
    flushProgress();
    if (AudioFocus.instance.waiting) unawaited(AudioFocus.instance.abandon());
    _pendingBvid = bvid ?? _book?.bvid;
    _clearedRecords.remove(_pendingBvid);
    _wantsPlayback = true;
    _preserveCompletedProgress = false;
    _nativeLoadGeneration = null;
    _nativeLoadError = null;
    _failedTarget = null;
    _reconnecting = false;
    _loading = true;
    _error = null;
    return ++_loadGeneration;
  }

  /// 播放指定作品；resume:false 从首个分P开头播放，显式分P可直接传入位置。
  /// 返回是否成功进入播放
  Future<bool> playBook(Book book,
      {int resumeIndex = 0, int resumeMs = 0, int? resumeCid, bool resume = true}) async {
    final generation = _beginLoad(book.bvid);
    notifyListeners();
    _ensureNotificationPermission();
    List<Chapter> chapters;
    var complete = true;
    try {
      if (_book?.bvid == book.bvid && _chapters.isNotEmpty && _chaptersComplete) {
        chapters = _chapters; // 同本书复用列表
      } else if (book.chapters?.isNotEmpty == true &&
          _shelf.progressByBvid(book.bvid)?.chaptersComplete != false) {
        chapters = book.chapters!;
      } else {
        final directory = await resolveChapters(book.bvid);
        chapters = directory.chapters;
        complete = directory.complete;
        if (chapters.isEmpty) throw StateError('目录不可用');
      }
    } catch (e) {
      if (generation != _loadGeneration) return false;
      _loading = false;
      _error = '加载目录失败，请重试';
      _failedTarget = (book: book, chapters: <Chapter>[],
        index: resume ? resumeIndex : 0, positionMs: resume ? resumeMs : 0,
        cid: resume ? resumeCid : null,
        complete: true);
      debugPrint('[BookPlayer] 加载目录失败: ${e.runtimeType}');
      notifyListeners();
      return false;
    }
    if (generation != _loadGeneration) return false;

    if (chapters.isEmpty) {
      _error = '这个资源没有可播放的分P';
      _book = book;
      _chapters = [];
      _index = 0;
      _loaded = false;
      _loading = false;
      notifyListeners();
      return false;
    }

    // 换本书时重置「播放 1 分钟自动入书架」的累计
    if (_playTallyBook?.bvid != book.bvid ||
        _playTallyBook?.contentMode != book.contentMode) {
      _playTally = Duration.zero;
      _playTallyBook = book;
      _autoShelved = false;
    }

    var idx = resume && resumeIndex >= 0 && resumeIndex < chapters.length
        ? resumeIndex
        : 0;
    var offset = resume ? resumeMs : 0;
    if (resume && resumeCid != null && resumeCid != 0) {
      final found = chapters.indexWhere((chapter) => chapter.cid == resumeCid);
      if (found >= 0) {
        idx = found;
      } else {
        offset = 0; // 旧 CID 已不存在，不能把它的时间应用到另一分 P。
      }
    }
    return _loadTarget(idx,
        resumeMs: offset, newBook: book, newChapters: chapters,
        chaptersComplete: complete,
        requestGeneration: generation);
  }

  /// 从书架/离线入口播放一本书：在线优先，取不到就退回本地缓存
  ///
  /// 三种结局分得很清楚，UI 才能给出对的提示：
  /// - [ShelfPlayOutcome.ok]：播上了（可能是在线，也可能是本地缓存）
  /// - [ShelfPlayOutcome.bookGone]：目录接口明确报告作品不存在，且无可用缓存
  /// - [ShelfPlayOutcome.loadFailed]：请求本身失败（多半没网）且没有离线数据
  Future<ShelfPlayOutcome> playBookWithFallback(ShelfBook sb) async {
    final generation = _beginLoad(sb.book.bvid);
    notifyListeners();
    _ensureNotificationPermission();
    final book = sb.book;
    final start = PlaybackPreferences.selectionStart(book.contentMode,
        index: sb.lastChapterIndex, positionMs: sb.positionMs);

    // ① 拿章节列表：已加载的 → 书里带的 → 在线接口
    var chapters = const <Chapter>[];
    var complete = true;
    var confirmedGone = false;
    try {
      if (_book?.bvid == book.bvid && _chapters.isNotEmpty && _chaptersComplete) {
        chapters = _chapters;
      } else if (book.chapters != null && book.chapters!.isNotEmpty && sb.chaptersComplete) {
        chapters = book.chapters!;
      } else {
        final directory = await resolveChapters(book.bvid, reportGone: true);
        chapters = directory.chapters;
        complete = directory.complete;
      }
    } on BiliApiException catch (error) {
      confirmedGone = error.code == -404 || error.code == 62002;
    } catch (_) {
      // 目录或网络异常不构成作品下架的证据。
    }
    if (generation != _loadGeneration) return ShelfPlayOutcome.loadFailed;

    // ② 在线拿到了章节：正常播放（命中缓存的集自动播本地文件）
    if (chapters.isNotEmpty) {
      var idx = start.index >= 0 && start.index < chapters.length
          ? start.index
          : 0;
      var offset = start.positionMs;
      if (book.contentMode.resumesPosition && sb.lastCid != 0) {
        final found = chapters.indexWhere((chapter) => chapter.cid == sb.lastCid);
        if (found >= 0) {
          idx = found;
        } else {
          offset = 0;
        }
      }
      final ok = await _loadTarget(idx,
          resumeMs: offset, newBook: book, newChapters: chapters,
          chaptersComplete: complete,
          requestGeneration: generation);
      if (generation != _loadGeneration) return ShelfPlayOutcome.loadFailed;
      if (ok) return ShelfPlayOutcome.ok;
      // 没播起来（多半是没网，且要续听的那一集没缓存）→ 退回本地已缓存的集
    }

    // ③ 看本地有没有离线数据，有就直接离线听
    final cached = _cache.chaptersOf(book.bvid);
    if (cached.isNotEmpty) {
      // 上次听的那一集优先；它文件没了就依次试其它已缓存的集
      final ordered = book.contentMode.resumesPosition
          ? <Chapter>[
              ...cached.where((c) => c.cid == sb.lastCid),
              ...cached.where((c) => c.cid != sb.lastCid),
            ]
          : cached;
      for (final c in ordered) {
        final r = await _playCachedEntry(book.bvid, c.cid, book, generation);
        if (generation != _loadGeneration) return ShelfPlayOutcome.loadFailed;
        if (r == CachePlayOutcome.okOffline || r == CachePlayOutcome.okOnline) {
          return ShelfPlayOutcome.ok;
        }
        if (r == CachePlayOutcome.failed) return ShelfPlayOutcome.loadFailed;
        // fileMissing：这一集文件没了，继续试下一集
      }
      return ShelfPlayOutcome.loadFailed;
    }

    // ④ 在线没有、本地也没有：让播放页显示这本书和可读的原因
    _book = book;
    _chapters = const [];
    _loaded = false;
    _loading = false;
    _error = confirmedGone ? '作品已下架或不存在' : '暂时无法播放，请稍后重试或使用离线缓存';
    notifyListeners();
    return confirmedGone ? ShelfPlayOutcome.bookGone : ShelfPlayOutcome.loadFailed;
  }

  /// 从书架进度继续收听
  Future<bool> resumeShelf(ShelfBook sb) async {
    return playBook(
      sb.book,
      resumeIndex: sb.lastChapterIndex,
      resumeMs: sb.positionMs,
      resumeCid: sb.lastCid,
      resume: sb.book.contentMode.resumesPosition,
    );
  }

  /// 切换到指定章节（index），可选偏移
  Future<void> playChapterIndex(int index, {int offsetMs = 0}) async {
    if (_chapters.isEmpty || index < 0 || index >= _chapters.length) return;
    await _loadTarget(index, resumeMs: offsetMs);
  }

  /// 用户重试失败目标；已停止或正在加载时不再发起播放。
  Future<bool> retryPlayback() async {
    if (_loading || _error == null) return false;
    final target = _failedTarget;
    if (target != null) {
      if (target.index >= 0 && target.index < target.chapters.length) {
        _urlCache.remove(target.chapters[target.index].cid);
      }
      if (target.chapters.isEmpty) {
        return playBook(target.book, resumeIndex: target.index,
            resumeMs: target.positionMs, resumeCid: target.cid);
      }
      return _loadTarget(target.index,
          resumeMs: target.positionMs, newBook: target.book,
          newChapters: target.chapters, chaptersComplete: target.complete);
    }
    final book = _book;
    if (book == null) return false;
    if (_chapters.isNotEmpty) {
      _urlCache.remove(currentChapter?.cid);
      return _loadTarget(_index, resumeMs: currentPosition.inMilliseconds);
    }
    final progress = _shelf.progressByBvid(book.bvid) ?? ShelfBook(book: book);
    return await playBookWithFallback(progress) == ShelfPlayOutcome.ok;
  }

  /// 加载并打开音源：成功才提交新状态，任何一步失败都滚回旧状态
  Future<bool> _loadTarget(
    int index, {
    int resumeMs = 0,
    Book? newBook,
    List<Chapter>? newChapters,
    /// 本次传入的章节列表是否是**完整目录**（在线列表＝完整；
    /// 离线时从缓存索引拼出来的只有已缓存的那几集，不能当整本书的章节数）
    bool chaptersComplete = true,
    int? requestGeneration,
  }) async {
    final generation = requestGeneration ?? _beginLoad(newBook?.bvid);
    if (generation != _loadGeneration) return false;
    final session = _session;
    bool stillCurrent() => generation == _loadGeneration && session == _session;
    _failedTarget = null;
    final prevBook = _book;
    final prevChapters = _chapters;
    final prevComplete = _chaptersComplete;
    final prevIndex = _index;
    final prevLoaded = _loaded;
    final prevUrl = _playbackUrl;
    final prevAudio = _lastAudio;
    final prevOffline = _isOffline;
    final prevRate = _rate;

    // 候选信息在原生播放成功前只留在本次请求中；失败不能回滚到
    // 另一个尚未完成的请求，也不能把旧音源的位置记到候选作品。
    final retryBook = newBook ?? _book;
    final retryChapters = List<Chapter>.of(newChapters ?? _chapters);
    final retryComplete = newChapters != null ? chaptersComplete : _chaptersComplete;
    _loading = true;
    _error = null;
    notifyListeners();

    var ok = false;
    BookAudio? targetAudio;
    try {
      if (retryBook == null || retryChapters.isEmpty || index < 0 || index >= retryChapters.length) {
        throw StateError('分 P 索引越界：$index');
      }
      final rate = await _preferences.rateFor(
          retryBook.contentMode);
      if (!stillCurrent()) return false;
      final chapter = retryChapters[index];
      // 注意：换章时 newBook 为 null，沿用已提交作品判定缓存。
      final curBvid = retryBook.bvid;
      final localPath = await _cachedPathOf(curBvid, chapter.cid);
      if (!stillCurrent()) return false;

      if (localPath != null) {
        // 已缓存：直接播本地文件，不需要网络地址
        var opened = false;
        Completer<void>? nativeError;
        try {
          await _player.setRate(rate);
          if (!stillCurrent()) return false;
          nativeError = _beginNativeLoad(generation);
          await _player.open(Media(localPath), play: false);
          if (!stillCurrent()) return false;
          await _waitForNativeLoad(nativeError);
          if (!stillCurrent()) return false;
          opened = true;
        } catch (e) {
          // open 在播放器忙（比如刚被通知栏/耳机事件打断）时会抛瞬时异常，
          // 重试一次再决定，否则白白回退在线、浪费流量还丢掉离线播放的意义
          debugPrint('[BookPlayer] 本地缓存打开失败，重试一次: ${e.runtimeType}');
          await Future<void>.delayed(const Duration(milliseconds: 350));
          if (!stillCurrent()) return false;
          try {
            await _player.setRate(rate);
            if (!stillCurrent()) return false;
            nativeError = _beginNativeLoad(generation);
            await _player.open(Media(localPath), play: false);
            if (!stillCurrent()) return false;
            await _waitForNativeLoad(nativeError);
            if (!stillCurrent()) return false;
            opened = true;
          } catch (e2) {
            debugPrint('[BookPlayer] 本地缓存打开仍失败，回退在线: ${e2.runtimeType}');
          }
        }
        if (opened) {
          // 先应用当前模式倍速再起播；设置失败也不删除有效的缓存文件。
          await _player.setRate(rate);
          if (!stillCurrent()) return false;
          final error = nativeError!;
          if (resumeMs > 0) {
            await _seekToResume(resumeMs, mode: retryBook.contentMode,
                stillCurrent: () => stillCurrent() && !error.isCompleted);
          } else {
            await _playIfIntended(stillCurrent, mode: retryBook.contentMode);
          }
          if (!stillCurrent()) return false;
          if (error.isCompleted) throw StateError('原生音源加载失败');
          ok = true;
          _playbackUrl = null;
          _mediaReady = true;
          _isOffline = true;
          _pausedByInterruption = false;
        } else {
          // 打开失败先确认文件是否真的坏了，不能因为一次 open 异常就删掉离线文件
          await _cache.dropIfBroken(curBvid, chapter.cid);
        }
      }

      if (!ok) {
        final source = await _fetchStreamCandidates(chapter.cid,
            bvid: curBvid, stillCurrent: stillCurrent);
        if (!stillCurrent()) return false;
        targetAudio = source.audio;
        final candidates = source.urls;
        if (candidates.isEmpty) {
          throw StateError('获取音频链接失败（内容可能无法播放）');
        }

        for (var i = 0; i < candidates.length; i++) {
          final url = candidates[i];
          try {
            // 有续播位置时先打开再精确跳转，保证落点准确到秒
            await _player.setRate(rate);
            if (!stillCurrent()) return false;
            final nativeError = _beginNativeLoad(generation);
            await _player.open(Media(url, httpHeaders: _streamHeaders()),
                play: false);
            if (!stillCurrent()) return false;
            await _waitForNativeLoad(nativeError);
            if (!stillCurrent()) return false;
            // open 后倍速可能被播放器复位，这里显式恢复
            await _player.setRate(rate);
            if (!stillCurrent()) return false;
            if (resumeMs > 0) {
              await _seekToResume(resumeMs, mode: retryBook.contentMode,
                  stillCurrent: () => stillCurrent() && !nativeError.isCompleted);
            } else {
              await _playIfIntended(stillCurrent, mode: retryBook.contentMode);
            }
            if (!stillCurrent()) return false;
            if (nativeError.isCompleted) throw StateError('原生音源加载失败');
            if (_error != null) _error = null;
            ok = true;
            _playbackUrl = url;
            _mediaReady = true;
            _isOffline = false;
            _pausedByInterruption = false;
            break;
          } catch (e) {
            debugPrint('[BookPlayer] 候选音轨 $i 打开失败: ${e.runtimeType}');
            if (!stillCurrent()) return false;
            if (i < candidates.length - 1) {
              await _player.stop();
            }
          }
        }
      }

      if (!ok) {
        throw StateError('无法播放该内容');
      }
      // 在线与离线路径均已在起播前检查焦点与最新播放意图。
      _book = retryBook;
      _chapters = retryChapters;
      _chaptersComplete = retryComplete;
      _rate = rate;
      _lastAudio = targetAudio ?? prevAudio;
      _index = index;
      _loaded = true;
      AppAnalytics.onEvent('play_start');
    } catch (e) {
      if (stillCurrent()) {
        _error = '播放失败，请稍后重试';
        if (retryBook != null) {
          _failedTarget = (book: retryBook, chapters: retryChapters,
            index: index, positionMs: resumeMs,
            cid: index >= 0 && index < retryChapters.length ? retryChapters[index].cid : null,
            complete: retryComplete);
        }
      }
      debugPrint('[BookPlayer] 加载失败: ${e.runtimeType}');
    } finally {
      if (stillCurrent()) {
      if (!ok) {
        _book = prevBook;
        _chapters = prevChapters;
        _chaptersComplete = prevComplete;
        _index = prevIndex;
        _loaded = prevLoaded;
        _playbackUrl = prevUrl;
        _lastAudio = prevAudio;
        _isOffline = prevOffline;
        _rate = prevRate;
        try {
          await _player.setRate(prevRate);
        } catch (_) {}
        if (stillCurrent()) _mediaReady = false;
      }
      if (stillCurrent()) {
        _nativeLoadGeneration = null;
        _nativeLoadError = null;
        _loading = false;
        _pushNowPlaying();
        notifyListeners();
      }
      }
    }
    return ok;
  }

  Completer<void> _beginNativeLoad(int generation) {
    _nativeLoadGeneration = generation;
    final error = Completer<void>();
    _nativeLoadError = error;
    return error;
  }

  Future<void> _waitForNativeLoad(Completer<void> error) async {
    await Future.any<void>([_waitForDuration(), error.future]);
    if (error.isCompleted) throw StateError('原生音源加载失败');
  }

  /// 精确续播：等媒体就绪后跳转，并校验落点（首次 seek 可能被播放器忽略）
  Future<void> _seekToResume(int resumeMs, {bool Function()? stillCurrent, ContentMode? mode}) async {
    final target = Duration(milliseconds: resumeMs);
    await _waitForDuration();
    if (stillCurrent != null && !stillCurrent()) return;
    await _player.seek(target);
    if (stillCurrent != null && !stillCurrent()) return;
    await _playIfIntended(stillCurrent, mode: mode);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (stillCurrent != null && !stillCurrent()) return;
    final off = (_player.state.position - target).inMilliseconds.abs();
    if (off > 5000) {
      debugPrint('[BookPlayer] 续播落点偏差 ${off}ms，重新跳转');
      await _player.seek(target);
    }
  }

  Future<void> _playIfIntended(bool Function()? stillCurrent, {ContentMode? mode}) async {
    bool current() => stillCurrent == null || stillCurrent();
    if (!_wantsPlayback || !current()) return;
    final focus = AudioFocus.instance;
    final speech = (mode ?? _book?.contentMode) == ContentMode.audiobook;
    // 新焦点或新的语音策略不能继承旧音源的闪避音量；仍持有的音乐闪避保留。
    if (!focus.hasFocus || focus.pausesOnDuck != speech) {
      await _restoreVolumeIfDucked();
      if (!_wantsPlayback || !current()) return;
    }
    final granted = await focus.request(speech: speech);
    if (!granted || !_wantsPlayback || !current() || !focus.hasFocus) return;
    await _player.play();
    // 暂停/焦点丢失可在原生命令执行期间到达，不能由旧起播命令逆转。
    if (current() && (!_wantsPlayback || !focus.hasFocus)) await _player.pause();
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
  Future<({List<String> urls, BookAudio? audio})> _fetchStreamCandidates(int cid, {
    required String bvid, bool Function()? stillCurrent,
  }) async {
    if (stillCurrent != null && !stillCurrent()) return (urls: <String>[], audio: null);
    final cached = _urlCache[cid];
    if (cached != null) {
      final ageMs = DateTime.now().millisecondsSinceEpoch - cached.ts;
      if (ageMs < 90 * 60 * 1000) return (urls: [cached.url], audio: null);
    }
    final audio = await _api.playUrl(bvid, cid);
    if (stillCurrent != null && !stillCurrent()) return (urls: <String>[], audio: null);
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
    return (urls: uniq, audio: audio);
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
        title: '第 ${chapter.page} ${_book!.contentMode.unitLabel} · ${chapter.part}',
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

    // 只有「切章/换源」这种真正的加载过程才上报 buffering。
    // 注意：网络抖动引起的短暂缓冲不能上报 buffering —— Android 会把
    // PLAYBACK_STATE_BUFFERING 当作「未在播放」，锁屏/通知栏就会显示暂停图标，
    // 而 App 内实际还在放，造成两边状态不一致。
    // 缓冲状态由 App 内的 loading 提示负责表达，不污染系统媒体会话。
    final processing = _loading
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
    _wantsPlayback = true;
    _preserveCompletedProgress = false;
    final generation = _loadGeneration;
    final session = _session;
    bool stillCurrent() => generation == _loadGeneration && session == _session;
    _pausedByInterruption = false;
    await _restoreVolumeIfDucked();
    if (!stillCurrent() || _loading || _reconnecting) return;
    // 音源确实不在了（重连彻底失败）时重新载入当前章节再播。
    // 注意用 _mediaReady 判断，不能用 _playbackUrl：离线播放时 URL 本来就是 null，
    // 否则每次恢复都会重新开一次本地文件（多一次 loading 与跳转延迟）。
    if (_loaded && !_mediaReady && !_reconnecting) {
      final failed = _failedTarget;
      final saved = _shelf.progressByBvid(_book?.bvid ?? '');
      final keepMs = failed != null && failed.book.bvid == _book?.bvid &&
              failed.index == _index
          ? failed.positionMs
          : saved != null && saved.lastCid == currentChapter?.cid
              ? saved.positionMs
              : currentPosition.inMilliseconds;
      final ok = await _reconnect(keepMs: keepMs);
      if (ok || !stillCurrent()) return;
    }
    if (!stillCurrent()) return;
    await _playIfIntended(stillCurrent);
    if (!stillCurrent()) return;
    _pushState(force: true);
  }

  Future<void> pause() async {
    _wantsPlayback = false;
    _pausedByInterruption = false;
    // 先取消本次焦点，避免旧 pause 的迟到回复释放新选择已取得的焦点。
    unawaited(AudioFocus.instance.abandon());
    await _player.pause();
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
    _preserveCompletedProgress = false;
    await _player.seek(to);
    _pushState(force: true);
  }

  Future<void> seekRelative(int seconds) async {
    final target = currentPosition + Duration(seconds: seconds);
    await seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> stop() async {
    _wantsPlayback = false;
    flushProgress();
    // 在原生 stop 发出位置归零事件前关闭保存，保留最后成功会话的断点。
    _loaded = false;
    _mediaReady = false;
    _pausedByInterruption = false;
    // 会话代号自增：让进行中的重连立即作废，避免「按了停止声音又出来」
    _session++;
    final generation = ++_loadGeneration;
    _nativeLoadGeneration = null;
    _nativeLoadError = null;
    _failedTarget = null;
    _pendingBvid = null;
    _error = null;
    _loading = false;
    await _player.stop();
    if (generation != _loadGeneration) return;
    unawaited(AudioFocus.instance.abandon());
    _loaded = false;
    _playbackUrl = null;
    _mediaReady = false;
    _reconnecting = false;
    positionTick.value = Duration.zero;
    _lastSaveTimer?.cancel();
    _lastSaveTimer = null;
    // 注意：不要取消 _watchdog / _stateReconciler。
    // 它们在 setup() 里只创建一次，而 stop() 可以被通知栏的「停止」触发，
    // 一旦在这里取消，断流重连与系统状态校正就永久失效了。
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

  /// 移出收藏保留当前播放与断点；收听记录同时保留不自动重新收藏的意图。
  Future<void> removeFromShelf(String bvid) async {
    if (_book?.bvid == bvid) flushProgress();
    await _shelf.remove(bvid);
  }

  /// 先终止匹配的播放/加载，再删除断点，避免节流保存或迟到请求写回。
  Future<void> clearListeningRecord(String bvid) async {
    _clearedRecords.add(bvid);
    final pendingMatches = _loading && _pendingBvid == bvid;
    final activeMatches = _book?.bvid == bvid;
    if (pendingMatches && !activeMatches && _loaded && _mediaReady &&
        _nativeLoadGeneration == null) {
      // 目录请求尚未触碰原生音源；取消它即可，保留另一作品的播放。
      ++_loadGeneration;
      _loading = false;
      _pendingBvid = null;
      _failedTarget = null;
      _error = null;
      notifyListeners();
    } else if (pendingMatches ||
        (activeMatches && (!_loading || _pendingBvid == null))) {
      await stop();
    } else if (activeMatches && _nativeLoadGeneration == null) {
      // 另一作品正在查目录/链接，只停止旧音源，不取消新的加载代次。
      _loaded = false;
      _mediaReady = false;
      await _player.stop();
    }
    await _shelf.clearListeningRecord(bvid);
  }

  /// 书籍启用中（真实播放超过 1 分钟）自动加入书架
  static const Duration _autoShelfAfter = Duration(minutes: 1);

  /// 正在计数的是哪个 bvid
  String? _tallyBvid;
  /// 上次出现的位置，用来累计增量
  Duration _lastTallyPos = Duration.zero;

  /// 累计真实播放时长；满 1 分钟且不在书架上时自动加入
  void _tallyPlayTime() {
    if (_loading) return;
    final book = _book;
    if (book == null || !_loaded || !book.contentMode.autoShelf) return;
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
      if (!_shelf.isOnShelf(book.bvid) &&
          !(_shelf.progressByBvid(book.bvid)?.autoAddSuppressed ?? false) &&
          !_clearedRecords.contains(book.bvid)) {
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
    if (_clearedRecords.contains(book.bvid)) return;
    if (!_shelf.isOnShelf(book.bvid)) return;
    _shelf.markChapterDone(book.bvid, chapter.cid);
  }

  /// 播到接近结尾（>=95%）自动打「已听」标记，不等 completed 事件
  void _markDoneIfReached(Duration pos) {
    if (_loading) return;
    final chapter = currentChapter;
    final book = _book;
    final dur = currentDuration;
    if (chapter == null || book == null || dur <= Duration.zero) return;
    if (_clearedRecords.contains(book.bvid)) return;
    if (pos < dur * 0.95) return;
    if (!_shelf.isOnShelf(book.bvid)) return;
    _shelf.markChapterDone(book.bvid, chapter.cid);
  }

  Map<String, String> get downloadHeaders => _streamHeaders();

  /// 取某本书的章节列表：在线取全书，取不到就用本地数据兜底
  ///
  /// 离线不是另一套逻辑，只是数据源换了。所以这里的顺序是
  /// 「已加载的完整列表 → 在线接口 → 书架里存的 → 缓存索引」，
  /// 保证任何情况下目录里都是**真实章节**，而不是一条占位项。
  Future<({List<Chapter> chapters, bool complete})> resolveChapters(
      String bvid, {bool reportGone = false}) async {
    if (_book?.bvid == bvid && _chapters.isNotEmpty && _chaptersComplete) {
      return (chapters: [..._chapters], complete: _chaptersComplete);
    }

    try {
      final list = await _api.pageList(bvid);
      if (list.isNotEmpty) return (chapters: [...list], complete: true);
    } on BiliApiException catch (error) {
      if (reportGone && (error.code == -404 || error.code == 62002)) rethrow;
      // 风控、权限、限流及临时网络失败继续尝试本地数据。
    } catch (_) {
      // 无网络 / 接口失败，继续用本地数据兜底
    }

    final progress = _shelf.progressByBvid(bvid);
    final saved = progress?.book.chapters;
    if (saved != null && saved.isNotEmpty) {
      return (chapters: [...saved], complete: progress!.chaptersComplete);
    }
    if (_book?.bvid == bvid && _chapters.isNotEmpty) {
      return (chapters: [..._chapters], complete: _chaptersComplete);
    }

    // 缓存索引里只有已缓存的那几集，不是完整目录
    return (chapters: _cache.chaptersOf(bvid), complete: false);
  }

  /// 从离线缓存入口播放某一集
  ///
  /// **刻意不自己 open 文件**：直接复用 [_loadTarget]，和在线播放走同一条路。
  /// 这样章节列表、上一篇/下一篇、倍速、断点续播、进度保存全部与在线一致，
  /// 离线仅仅是「这一集的音源恰好在本地」。
  ///
  /// 返回结果要区分「文件真的没了」和「其它原因打不开」——
  /// 两者对用户是完全不同的处境，不能一律提示「缓存文件已失效」。
  Future<CachePlayOutcome> playCachedEntry(
      String bvid, int cid, Book book) {
    final generation = _beginLoad(bvid);
    notifyListeners();
    return _playCachedEntry(bvid, cid, book, generation);
  }

  Future<CachePlayOutcome> _playCachedEntry(
      String bvid, int cid, Book book, int generation) async {
    _ensureNotificationPermission();

    // 文件得真的在，否则没有「离线播放」这回事
    final local = await _cachedPathOf(bvid, cid);
    if (generation != _loadGeneration) return CachePlayOutcome.failed;
    if (local == null) {
      _loading = false;
      notifyListeners();
      _cache.logEvent('播放缓存失败：文件不存在 $bvid/$cid');
      return CachePlayOutcome.fileMissing;
    }

    final resolved = await resolveChapters(bvid);
    if (generation != _loadGeneration) return CachePlayOutcome.failed;
    final chapters = resolved.chapters;
    var complete = resolved.complete;
    var index = chapters.indexWhere((c) => c.cid == cid);
    if (index < 0) {
      // 离线时列表来自缓存索引，理论上必然包含这一集；兜底补一条，
      // 免得出现「目录里找不到自己点的这一集」
      final fromCache = _cache.entriesOf(bvid)
          .firstWhere((e) => e.cid == cid, orElse: () => CacheEntry(
              bvid: bvid, cid: cid, bookTitle: book.cleanTitle, chapterTitle: '',
              contentMode: book.contentMode));
      chapters.add(fromCache.toChapter());
      index = chapters.length - 1;
      complete = false;
    }

    // 优先用书架里存的完整书籍信息（合成的 Book 缺作者/章节等字段）
    var progress = _shelf.progressByBvid(bvid);
    final target = progress?.book ?? book;
    // 保留听书缓存入口自动入架；其他类型只保存独立收听记录。
    if (!_shelf.isOnShelf(bvid) && target.contentMode.autoShelf &&
        !(progress?.autoAddSuppressed ?? false) && !_clearedRecords.contains(bvid)) {
      await _shelf.add(target);
      if (generation != _loadGeneration) return CachePlayOutcome.failed;
      progress = _shelf.progressByBvid(bvid);
    }
    // 离线播放同样要续播：只有当书架记录的就是这一集时才恢复进度
    final start = PlaybackPreferences.selectionStart(target.contentMode,
        index: index,
        positionMs: (progress != null && progress.lastCid == cid) ? progress.positionMs : 0,
        explicitPart: true);

    // 交给统一加载路径：这一集命中缓存就播本地，否则照常走在线
    final ok = await _loadTarget(start.index,
        resumeMs: start.positionMs,
        newBook: target,
        newChapters: chapters,
        chaptersComplete: complete,
        requestGeneration: generation);
    if (generation != _loadGeneration) return CachePlayOutcome.failed;

    if (!ok) {
      // 文件在却没能起播：交给统一路径已经尝试过在线回退，这里只报「没播成」
      _cache.logEvent('缓存入口播放失败 $bvid/$cid');
      return CachePlayOutcome.failed;
    }
    // 能起播时，用实际音源判断是离线还是在线（回退成功也算正常收听）
    return _isOffline ? CachePlayOutcome.okOffline : CachePlayOutcome.okOnline;
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
      debugPrint('[BookPlayer] 取下载地址失败: ${e.runtimeType}');
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
    if (!_loaded || !_mediaReady || _loading || _lastSaveTimer != null) return;
    _lastSaveTimer = Timer(const Duration(seconds: 2), () {
      _lastSaveTimer = null;
      _saveNow();
    });
  }

  void _saveNow() {
    if (!_loaded || !_mediaReady || _loading || _preserveCompletedProgress) return;
    final chapter = currentChapter;
    final book = _book;
    if (chapter == null || book == null) return;
    if (_clearedRecords.contains(book.bvid)) return;
    final pos = currentPosition;
    // 媒体时长可能还没解析出来（刚点开就退出）。这时用章节列表里带的
    // 时长兜底，否则这一章的进度会被整条丢弃——「点开就退，进度不存」。
    var durMs = currentDuration.inMilliseconds;
    if (durMs <= 0) durMs = chapter.duration * 1000;
    if (durMs <= 0) return;
    _shelf.updateProgress(
      book.bvid,
      book: book,
      cid: chapter.cid,
      chapterIndex: _index,
      positionMs: pos.inMilliseconds,
      chapterDurationMs: durMs,
      // 目录不全时不要写总章节数，否则整本进度会被算歪
      totalChapters: _chaptersComplete ? _chapters.length : 0,
      chapters: _chapters,
      chaptersComplete: _chaptersComplete,
    );
  }

  /// 手动留存进度（章节切换/退后台/退出时调用）
  void flushProgress() {
    _lastSaveTimer?.cancel();
    _lastSaveTimer = null;
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
