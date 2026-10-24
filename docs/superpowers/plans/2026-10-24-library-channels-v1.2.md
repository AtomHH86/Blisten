# B听 1.2 频道与个人内容改造 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成已确认的四频道分类、手动收藏、个人内容四视图及静默常驻播放器，经过测试发布 1.2.0+3，再交付跨平台可行性评估。

**Architecture:** 保留 Flutter/Provider、ShelfStore、BookPlayer 和 HomeShell；扩展已有数据字段与导航，不引入第二份收藏/历史数据。各任务在同一 Blisten 文件夹的 codex/channels-library-v1.2 分支执行；用户要求后续修改都在该目录，保留 Git 检查点用于回退。

**Tech Stack:** Flutter/Dart、SharedPreferences、media_kit、Android/Gradle、Python/Bash 测试与打包工具。

## Global Constraints

- 用户已于本轮确认现有方案并授权修改、测试、打包和上传；不再沿用图稿待批准的旧状态。
- 完整需求来源：`docs/superpowers/specs/2026-10-24-channels-favorites-recent-design.md`，第 2–6 节及第 8 节验收清单。v4 图稿是视觉参照，不是运行证据。
- 四频道固定为听书／听歌／听现场／听故事；内部 audiobook/music/concert/children、com.bting.audio、签名和 abts_* 数据键兼容。
- 全局取消自动收藏；显式收藏与实际收听历史、缓存分离。移出收藏继续播放；清除当前收听记录单独确认并停止对应会话。
- 三主页常驻迷你条；冷启动只显示本机历史，不自动播放、不解析音源。歌曲重新选择从头，其他三模式续播；同会话恢复不重置位置。
- 按 `docs/design/bting-design-system-v1.md` 复用主题和现有艺术资产。范围内没有新增艺术资产需求。
- 不改原作者归属、账号权限或音源范围；不向仓库提交凭据、APK、构建缓存。
- 实施先用真实行为的失败测试证明新规则，再改代码并复验；不要写源码文本断言或只验证 mock 的测试。
- 本地完整测试 → 代码审查 → 正式签名 APK → APK 安装/升级/更新识别 → GitHub 发布；每一步只有实际成功才能标记完成。

### Task 1: 手动收藏与实际收听数据

**Files:** `lib/core/storage/shelf_store.dart`, `lib/player/book_player.dart`, `lib/models/content_mode.dart`, `lib/widgets/resource_import_dialog.dart`; corresponding `test/recent_progress_test.dart`, `test/shelf_mode_import_test.dart`, `test/player_lifecycle_test.dart` and focused new tests.

**Interfaces:** Preserve existing public storage/player methods. Add `int lastListenedAt` and `bool get hasListened` to ShelfBook; add `Future<void> moveToMode(String bvid, ContentMode mode)` to ShelfStore. `recentBooks` returns only actually heard BV-unique items sorted by lastListenedAt; progressByBvid continues to include unplayed favorite metadata. Add optional `bool listened = true` to updateProgress; player must pass actual playback evidence, not mere position/seek/loading. Existing callers/tests using direct updateProgress retain sensible default. Document actual production evidence handling in report.

- [ ] Write/run failing real-store tests for new favorite absent from recent history, heard item retained after zero-position rewind, metadata refresh not reordering recent, nonfavorite completion, clear resetting history while preserving favorite, mode move preserving directory/progress/done/cache identity and old-session writes retaining new mode. Use literal books/positions as in existing tests:
  ```dart
  await shelf.add(resource('unplayed', ContentMode.audiobook));
  expect(shelf.recentBooks, isEmpty);
  await savePosition(resource('heard', ContentMode.music));
  await shelf.moveToMode('heard', ContentMode.concert);
  expect(shelf.progressByBvid('heard')!.positionMs, 47000);
  ```
- [ ] Remove time/cached-play automatic additions and stale hints/analytics; import button explicitly 添加到收藏. Preserve persisted legacy fields if necessary without behavior.
- [ ] Track actual playback advancement separately from seek/restoration; migration infers legacy heard only from stored positive progress/chapter/done evidence. New failed playback or merely selecting later P must not count heard. Keep lastListenedAt independent of metadata updatedAt; nonfavorite limit remains global100.
- [ ] Preserve completion/full directory for nonfavorites; clear current record prevents stale async writes resurrecting it. Move changes storage mode, not current playback tempo/session. Cache display can resolve mode using shelf metadata in Task3.
- [ ] Run focused tests via `source tool/android-env.sh && flutter test <changed tests>`, analyze changed files, commit scoped source/tests and write report with red/green evidence.

### Task 2: 两级发现频道与搜索归属

**Files:** `lib/data/seed_books.dart`, `lib/pages/discover_page.dart`, `lib/core/nav/home_tabs.dart`, `lib/pages/search_page.dart`, `lib/pages/up_home_page.dart`, related discover/search tests.

**Interfaces:** Add `DiscoverSeeds.categoriesFor(ContentMode mode)` returning List<DiscoverCategory>; retain legacy categories only if consumer compatibility needs it. Add `HomeTabs.openDiscover(ContentMode mode)` for Task3 empty-group navigation; store selected channel via notifier so an existing DiscoverPage reacts. Search/import receive current mode through existing arguments.

- [ ] Failing widget/API-boundary tests: channel change alters query/mode; delayed old response doesn't overwrite new channel; each channel remembers category; more/search/import inherit; favorites empty link changes active discover channel.
- [ ] Implement exact categories: book 热门/有声小说/广播剧/评书/相声/悬疑/玄幻仙侠/名著悦读; music 热门/华语/经典老歌/翻唱/纯音乐/欧美/日韩; concert 热门/演唱会/音乐节/Livehouse/舞台现场; children 热门/儿歌/动画/睡前故事/童话寓言/启蒙. Keep real book anchor configs in corresponding categories only.
- [ ] Use channel/category cache/request identity, category/scroll memory and local preference restoration; only current request loads. Hot uses matching query and play ordering. Loading/errors/refresh/empty follow spec; stale responses cannot pollute cache. Example independent expectation:
  ```dart
  // Capture actual API request after selecting 听故事 -> 儿歌.
  expect(requestMode, ContentMode.children);
  expect(requestKeyword, contains('儿歌'));
  ```
- [ ] All displayed modes use 听故事 and explanation 儿童 · 儿歌、动画、故事; preserve UP independent search and current content context.
- [ ] Run focused tests and analyze, commit and report.

### Task 3: 收藏页单行四视图与频道分组

**Files:** `lib/pages/bookshelf_page.dart`, `favorites_page.dart`, `recent_page.dart`, `cache_page.dart`, `follow_page.dart`, `my_page.dart`, `lib/core/nav/home_tabs.dart`, relevant widgets/tests.

**Interfaces:** Add enum `LibraryView { favorites, recent, cache, following }` and `HomeTabs.openLibrary(LibraryView view)`; default favorites. Existing main HomeShell indexed pages remain. Embed page content using optional `embedded` flag or scoped reusable body; standalone callers retain correct route behavior. Use Task1 hasListened/recentBooks/moveToMode and Task2 openDiscover.

- [ ] Write/run failing widget tests for single title/tab row, My shortcut switches matching view, channel count ordering/tie order, ordering stable during edit and refreshed on re-entry, move retaining data, large font/small viewport no exceptions.
- [ ] Implement one 56dp normal header, four fixed equal-width min48dp slots; selected24sp semibold/action color/short underline, others16sp secondary, same baseline,180ms transitions respecting reduced motion. No separate 收藏 title, nav counts, stat cards or resume avatar. Large type horizontally scrolls with selected visible and appropriate fixed-for-scale height.
- [ ] Four views preserve scroll, lazily instantiate needed content, remove embedded duplicate AppBars. My removes big stat cards and uses ordinary menu redirects. 在听 is actual history filterable four modes; cache completed-and-file-usable count only, following count UPs.
- [ ] Favorites groups sorted BV counts desc/fixed tie order, previews6 and 查看全部; within group 最近更新. Empty group goes matching discover; all empty one empty state. Long press move/remove with rules explained; current playback unaffected and cache labels reflect moved mode.
- [ ] Run focused widget/storage tests; check320dp/200% typography, themes, semantics; commit/report.

### Task 4: 常驻播放器与静默恢复

**Files:** `lib/widgets/mini_player.dart`, `lib/pages/player_page.dart`, `lib/pages/home_shell.dart`, `lib/player/book_player.dart` if required, focused player/widget and integration tests.

**Interfaces:** Current valid BookPlayer session wins; otherwise ShelfStore.recentBooks.firstOrNull provides local metadata preview. PlayerPage accepts `ShelfBook? preview` (or equivalent scoped typed argument), rendering pending preview without invoking playback. Explicit Play uses existing resumeShelf selection behavior; paused current uses existing resume.

- [ ] Failing tests: cold preview visible while player remains unloaded/no source requests; tapping cover opens preview silently; explicit Play music starts0 vs others checkpoint; empty state去发现; active session priority; clear matching updates preview without autoplay; actual playing-only rotation.
- [ ] Implement always reserved mini row only HomeShell's three pages; cover/title and right control independent, no cover play overlay. Missing image uses existing placeholder. Loading/buffer/error/end/retry show coherent state; no animation under reduced motion. Keep cached current playback continuity.
- [ ] Add deterministic Android integration scenarios covering uncollected >1min playback in four modes, cached path, P advance/completion, cold-process restoration, no auto source calls, UI navigation and persistent metadata. Use existing LocalBiliFixture/checked hooks, not real network for deterministic suite.
- [ ] Run focused tests and full unit before commit; report exact limitations and runtime validation pending Task5.

### Task 5: 完整验收、发布与跨平台评估

**Files:** versions `pubspec.yaml` and `lib/core/app_meta.dart`, README/CHANGELOG/design spec/current docs, integration fixtures if needed, `docs/testing/2026-10-24-v1.2-release.md`, `docs/planning/2026-10-24-cross-platform-feasibility.md`.

- [ ] Update version to1.2.0+3 and current behavior docs; old release evidence unchanged. Run `tool/test-android.sh`, `tool/test-android.sh online`, necessary script/native tests, diffcheck. Actual emulator screenshots for light/dark, narrow/large font and new flows. Fix failures with reproducer; no attaching phones.
- [ ] Independent review all source changes against unified spec, including async playback/history races and navigation; fix then targeted re-review.
- [ ] `tool/build-android-apks.sh`; verify4ABIs/package/version/certificate. Install release APK on dedicated x86_64 emulator, test clean start and signed1.1→1.2 upgrade preserving seeded favorite/history/mode/speed/cache; test release playback and update endpoints with existing harness. Save hashes/evidence and sign-off before upload.
- [ ] Commit/mergemain without rewriting history; push authorized repo, create tagv1.2.0 and release attachments with accurate notes. Verify anonymous release asset download hashes and public manual/automatic update recognition; fixes precede any success claim.
- [ ] After delivery, assess current-source portability and official current policies for PWA, WeChat mini program, iOS TestFlight/AppStore. Browser CORS/referer/Bili restrictions, native media/storage/login differences, background audio, offline, deployment/HTTPS/domains, account/filing/content rights/review risk, costs and recommended order. Existing server/domain is an input, not proof of compatibility or compliance; do not deploy a proxy or platform app in this task.
- [ ] Deliver release links, test scope/known limits, rollback checkpoint and actionable platform recommendation. No platform release or signing account creation is authorized by feasibility request.
