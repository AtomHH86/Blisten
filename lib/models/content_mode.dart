/// 来源均为 B 站视频；模式只决定发现、展示和收听规则。
enum ContentMode {
  audiobook,
  music,
  concert,
  children;

  String get label => switch (this) {
    audiobook => '听书',
    music => '听歌',
    concert => '听现场',
    children => '儿童',
  };

  String get unitLabel => switch (this) {
    audiobook => '章',
    music => '曲',
    concert => '段',
    children => '集',
  };

  bool get resumesPosition => this != music;
  bool get autoShelf => this == audiobook;

  static ContentMode fromJson(Object? value) => switch (value) {
    'music' => music,
    'concert' => concert,
    'children' => children,
    _ => audiobook,
  };
}
