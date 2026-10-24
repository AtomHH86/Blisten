/// 单条 DASH 音频轨
class AudioTrack {
  final int id;
  final String baseUrl;
  final List<String> backupUrls;
  final int bandwidth;
  final String codecs;
  final int quality; // 简单给个位数排序

  AudioTrack({
    required this.id,
    required this.baseUrl,
    this.backupUrls = const [],
    this.bandwidth = 0,
    this.codecs = '',
    this.quality = 0,
  });

  factory AudioTrack.fromMap(Map<String, dynamic> m) => AudioTrack(
        id: int.tryParse('${m['id'] ?? 0}') ?? 0,
        baseUrl: m['baseUrl'] as String? ?? '',
        backupUrls: (m['backup_url'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        bandwidth: int.tryParse('${m['bandwidth'] ?? 0}') ?? 0,
        codecs: m['codecs'] as String? ?? '',
        quality: int.tryParse('${m['id'] ?? 0}') ?? 0,
      );

  /// 仅接收有主机且不含凭据的 HTTP(S) 地址；保留 CDN 签名的原始字符。
  List<String> get httpsCandidates {
    final candidates = <String>[];
    final invalidCharacters = RegExp(r'[\x00-\x20\x7f\\<>"{}|^`]');
    final invalidEscape = RegExp(r'%(?![0-9a-fA-F]{2})');
    final httpAuthority = RegExp(r'^https?://([^/?#]*)', caseSensitive: false);
    for (final url in [baseUrl, ...backupUrls]) {
      if (url.isEmpty || invalidCharacters.hasMatch(url) ||
          invalidEscape.hasMatch(url)) {
        continue;
      }
      final uri = Uri.tryParse(url);
      final authority = httpAuthority.firstMatch(url)?.group(1);
      if (uri == null || !uri.hasAuthority || uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.userInfo.isNotEmpty || authority == null || authority.contains('@')) {
        continue;
      }
      // Do not rebuild the URI: doing so may normalize a signed path or query.
      candidates.add('https${url.substring(url.indexOf(':'))}');
    }
    return candidates;
  }

  String get qualityLabel {
    final q = id;
    if (q >= 30280) return '192K';
    if (q >= 30232) return '132K';
    if (q >= 30216) return '64K';
    if (q == 30251) return 'Hi-Res';
    if (q == 30250) return 'Dolby';
    return '$q';
  }
}

/// playurl 音频结果
class BookAudio {
  final List<AudioTrack> tracks;
  final AudioTrack? flac;
  final AudioTrack? dolby;
  final int timelength; // 毫秒
  final int? lastPlayTime; // 毫秒
  final int? lastPlayCid;

  BookAudio({
    this.tracks = const [],
    this.flac,
    this.dolby,
    this.timelength = 0,
    this.lastPlayTime,
    this.lastPlayCid,
  });

  factory BookAudio.fromMap(Map<String, dynamic> m) {
    final dash = m['dash'] as Map? ?? {};
    final audio = dash['audio'] as List? ?? [];
    return BookAudio(
      tracks: audio
          .map((e) => AudioTrack.fromMap(e as Map<String, dynamic>))
          .toList(),
      flac: dash['flac'] is Map
          ? AudioTrack.fromMap((dash['flac'] as Map)['audio'] as Map<String, dynamic>)
          : null,
      dolby: dash['dolby'] is Map &&
              (dash['dolby'] as Map)['audio'] is List &&
              ((dash['dolby'] as Map)['audio'] as List).isNotEmpty
          ? AudioTrack.fromMap(
              ((dash['dolby'] as Map)['audio'] as List).first
                  as Map<String, dynamic>)
          : null,
      timelength: int.tryParse('${m['timelength'] ?? 0}') ?? 0,
      lastPlayTime: m['last_play_time'] is num ? m['last_play_time'] as int? : null,
      lastPlayCid: m['last_play_cid'] is num ? m['last_play_cid'] as int? : null,
    );
  }

  /// 挑选音频轨：优先无损/杜比，其次按带宽降序
  AudioTrack pickPreferred() {
    if (tracks.isEmpty) return flac ?? dolby ?? AudioTrack(id: 0, baseUrl: '');
    if (flac != null && flac!.baseUrl.isNotEmpty) return flac!;
    if (dolby != null && dolby!.baseUrl.isNotEmpty) return dolby!;
    final sorted = [...tracks]..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    return sorted.first;
  }
}