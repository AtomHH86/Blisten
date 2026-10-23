/// 来源均为 B 站视频；模式只决定发现、展示和收听规则。
enum ContentMode {
  audiobook,
  music,
  concert;

  String get label => switch (this) {
    audiobook => '听书',
    music => '歌曲',
    concert => '演唱会',
  };

  String get unitLabel => switch (this) {
    audiobook => '章',
    music => '曲',
    concert => '段',
  };

  bool get resumesPosition => this != music;
  bool get autoShelf => this == audiobook;

  static ContentMode fromJson(Object? value) => switch (value) {
    'music' => music,
    'concert' => concert,
    _ => audiobook,
  };
}
