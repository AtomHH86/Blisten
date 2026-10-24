# Task 2：两级发现频道与搜索归属

日期：2026-10-24。实施范围为已确认统一方案第 2、3、8 节；视觉沿用 B听设计系统。

## 实现

- 发现顺序为标题/导入、四频道、频道搜索入口、专属二级分类、资源。频道固定听书/听歌/听现场/听故事；分类数为 8/7/5/6，名称和顺序按 brief。
- `DiscoverSeeds.categoriesFor(ContentMode)` 返回当前频道分类；原有真实主播配置留在听书对应分类，有声小说保留原热门听书主播。其他频道没有虚构主播。
- 热门使用对应题材 query + `order: 'click'`，标题为“热门内容”，不称官方榜单。搜索、更多、导入继续传当前 mode；UP 独立查询及最近内容 mode 继承原实现已正确，无需修改 UP 主页。
- 请求取消及递增 identity 同时保护渲染与缓存；缓存键为 mode.name + category index；只发当前分类请求，已加载分类可复用。刷新保留旧列表和当前位置，失败提供重试。离线备用只显示当前频道的真实缓存。
- 会话内按频道/分类保存列表 offset、每频道保存分类；SharedPreferences 新增 `abts_discover_channel` 与 `abts_discover_category_<mode.name>`，恢复失败/无效分类采用热门。原存储键、签名、模式序列值不变。
- 听故事说明统一为“儿童 · 儿歌、动画、故事”。搜索/UP 原 mode 归属链保留，搜索旧标签测试作相应适配。

## 接口

`HomeTabs.discoverMode` 是 `ValueNotifier<ContentMode?>`；`HomeTabs.openDiscover(mode)` 更新频道再将底栏 index 设为 1。现存 DiscoverPage 监听并立即切换；新建页面初始化也读取目标。页面手动切频道同步 notifier。Task3 可直接调用此接口。

## RED / GREEN 与验证

- 在 production 修改前新增 `discover children category uses its own query and remembers category`；执行失败，原因是旧发现页没有“听故事”入口，日志 `/tmp/task2-red.log`。
- 新增行为回归：听故事→儿歌实际 API keyword/mode；频道切回记忆分类；更多继承；迟到旧频道响应不覆盖新结果且不进入旧缓存；外部 openDiscover 驱动已存在页面；重新挂载从偏好恢复；导入 mode；热门 click 排序；实际滚动位置恢复且不重复请求。
- `flutter test test/audio_modes_ui_test.dart test/feedback_layout_test.dart test/search_categories_test.dart test/playback_preferences_test.dart`：48 passed，1 既有截图条件跳过，日志 `/tmp/task2-final2.log`。
- 保留明/暗、320dp、200% 大字布局检查；布局 fake 改为对热门 click 请求提供原两卡 fixture，保留原网格/无溢出断言。
- `flutter analyze`：No issues found，日志 `/tmp/task2-final-analyze.log`。初次发现 Task1 删除 autoShelf 后旧 playback_preferences_test 仍引用；按 root 授权仅删除过时 flag 断言，保留真实独立倍速/续播检查。
- `git -c core.whitespace=cr-at-eol diff --check` 通过。

## 限制与交接

- 本任务未构建 APK、未操作模拟器、未执行 full integration；原生与全体验收由 root 统一运行。
- 搜索结果仍是 B 站检索，不代表儿童适龄审核。缓存为当前页面会话内存，重启恢复频道/分类但不恢复精确像素位置，符合方案。
- `/tmp` 测试日志为本机临时证据，不入库；以上命令及结果摘要可复跑。
- 本次未修改 root 的计划文档，未触及播放/收藏规则和额外功能。
