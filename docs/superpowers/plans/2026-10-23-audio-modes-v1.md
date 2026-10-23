# Audio Modes V1 Implementation Plan

**Goal:** 保留听书行为，加入 B 站歌曲、演唱会搜索与链接/BV 导入，并隔离倍速及续播规则。

**Architecture:** 沿用 Book/Chapter、BiliApi、BookPlayer 和现有缓存，不复制播放器。新增 ContentMode（audiobook/music/concert），随搜索、详情、收藏、缓存持久化。旧 JSON 缺少模式时按 audiobook 读取。

**Tech Stack:** Flutter / Dart、Provider、Dio、SharedPreferences、media_kit。

## Global Constraints

- 来源仅为 B 站视频音轨，不新增跨 BV 歌单、随机循环、演唱会自动分曲或视频显示。
- 听书沿用现有筛选与有声小说补搜；歌曲/演唱会不经过听书筛选和补搜。
- 听书保留原 abts_rate；歌曲/演唱会初始 1.0 倍，用户调整后分别记忆，不互相覆盖。
- 听书和演唱会重新进入时续播；歌曲重新选取时从第一分 P 的开头播放。暂停后恢复、断流重连和用户选分 P/拖动不受此规则影响。
- 保留旧书架、进度、缓存；歌曲/演唱会手动加入收藏并继续记录最近位置，原听书自动入架行为保留。
- 导入支持裸 BV、标准 B 站视频链接、分享文本中的链接和 b23.tv 短链接；只解析可信 B 站主机，不访问任意粘贴 URL。
- 验证覆盖旧数据、三分钟歌曲搜索、听书补搜、分页保留模式、BV/链接解析、错误输入、各模式倍速/续播、缓存模式恢复。

## Task 1: Content model, search and import resolution

Owner: root. Files: lib/models/content_mode.dart, lib/models/book.dart, lib/services/bili_api.dart, lib/services/bili_resource.dart, test/content_mode_test.dart, test/bili_search_test.dart, test/bili_resource_test.dart.

- [x] 补旧数据与新模式序列化、搜索和链接解析行为测试，并观察旧实现的失败。
- [x] 新增 ContentMode；Book 构造/JSON/fromSearch/fromView/withContentMode 保留模式和完整元信息。
- [x] BiliApi.search(..., mode: ContentMode.audiobook) 贯穿原始请求；detail(..., mode:) 返回相应类型。
- [x] 链接解析提取 BV 与可选 p，短链接限制主机与重定向，错误可见。
- [x] 用受控网络边界验证真实搜索逻辑，不访问 B 站即可覆盖过滤/补搜/分页。

## Task 2: Search, discover and resource import UI

Owner: UI worker. Files: lib/pages/search_page.dart, lib/pages/discover_page.dart, lib/pages/book_detail_page.dart, lib/pages/up_home_page.dart, lib/data/seed_books.dart, lib/widgets/resource_import_dialog.dart, corresponding widget tests.

- [x] 搜索增加三模式选择；首搜/分页/UP 切换/并发请求保持正确模式，过时响应不可覆盖新结果。
- [x] 发现页追加歌曲和演唱会分类，模式传到更多、详情、UP 主等入口，保留现有听书类别。
- [x] 增加链接/BV 导入对话框，明确类型、失败保留输入、成功添加收藏并打开详情，选定 p 有效时展示/起播对应分 P。
- [x] 详情页按类型显示合适用语、默认续播规则，收藏/缓存传递类型。

## Task 3: Playback rules and persistent offline mode

Owner: playback worker. Files: lib/player/book_player.dart, lib/player/playback_preferences.dart, lib/core/storage/cache_store.dart, lib/core/storage/shelf_store.dart, lib/pages/player_page.dart, lib/pages/cache_page.dart, lib/pages/cache_sheet.dart, relevant playback/cache tests.

- [x] 先写真实偏好存储/续播决策/缓存模式往返测试。
- [x] 隔离三模式倍速；所有新加载/本地播放/重连使用正确倍速，旧听书设置不丢失。
- [x] 统一恢复入口遵循模式规则，显式选分 P、seek、暂停恢复和重连不被错误归零。
- [x] BookPlayer 与离线 CacheEntry/待下载任务传递模式；已有收藏类型在刷新元数据时不丢失。
- [x] 听书自动入架保留；新类型仅手动收藏，播放文案和通知元数据跟随模式。

## Task 4: Integration, review and delivery

Owner: root with independent reviewer.

- [x] 准备固定兼容 Flutter SDK，运行必要测试和 analyze，区分新增问题与上游既有问题。
- [x] 审查所有详情/缓存/书架入口，检查旧数据和三模式切换。
- [x] 独立审查 diff，修复本次改造引入的问题并复验。
- [x] 更新 README 的功能、规则和验证说明；交付可审查的分支改动，不发布、不合并。


## 验证记录（2026-10-23）

- 固定临时 SDK：Flutter 3.38.10 / Dart 3.10.9；官方 SDK SHA256 校验通过。
- `pubspec.yaml` 和 `pubspec.lock` 未变更，没有新增依赖。
- 全量 `flutter test --no-pub --reporter expanded`（启用可选 UI 截图）：57/57 通过。
- 全量 `flutter analyze --no-pub`：No issues found。原始提交的独立静态分析同样无问题。
- 390×844 的搜索与导入 Widget 截图已实际查看，中文和图标正常，未见溢出；README 中明确标为测试数据。
- 独立终审发现的两项 P2 已修复并复核：首次收藏迁移 recent 时采用新选择类型；最近收听快捷入口同时核对 BV 和类型。未解决发现为 0。
- 未验证 Android 真机/模拟器、原生播放器实际倍速切换、锁屏/通知、真实 B 站取流与后台生命周期；未生成 APK、未发布或合并。
