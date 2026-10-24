# 搜索四分类实施计划

**Goal:** UP 主成为始终可见的第四个搜索分类，并保持资源收听类型明确。

**Architecture:** 搜索分类是页面状态，UP 不是新的 ContentMode。保留原 BiliApi 与请求代次，统一切换走首屏加载；UP 主页使用可变的当前内容模式。

**Tech Stack:** 现有 Flutter / Provider，组件回归与专用 Android 模拟器。

## Global Constraints

仅修改 Blisten；保留三模式播放/存储/权限规则；沿用视觉规范；无正式打包或远程发布。依据[设计](../specs/2026-10-24-search-categories-design.md)。Flutter/ADB/Gradle 由主任务串行运行。

## 任务 1：一级搜索分类与回归（主任务）

Files: lib/pages/search_page.dart、test/search_categories_test.dart、test/audio_modes_ui_test.dart、test/feedback_layout_test.dart。

- [x] 新测试先证明空态UP查询、迟到响应隔离、清空、错误重试及UP分页；运行确认旧实现失败。
- [x] 删除二级标签及独立切换状态，四个ChoiceChip共同调用分类切换。UP查询用searchUser，视频查询仍用search(mode: mode)。
- [x] 分页保存首次提交关键词，以请求代次丢弃旧响应；UP结果按mid去重；短页结束，失败不推进页码。
- [x] 更新旧二级标签的交互测试；验证四项选中语义、小屏大字与键盘。

## 任务 2：UP主页显式模式（子任务）

Files: lib/pages/up_home_page.dart、test/up_home_mode_test.dart；独立复核发现真实服务层游标竞争，补 lib/services/bili_api.dart、test/up_cursor_race_test.dart。

- [x] 先写模式切换、详情传参、错误空态和迟到分页回归，主任务运行RED后再实施。
- [x] 默认沿用构造参数；ChoiceChip选择新模式时从第一页加载并隔离旧请求。
- [x] 详情、分页和空态搜索统一使用当前模式；不改变Book的播放约定。
- [x] 受控 client + 真实 BiliApi 复现旧合集初始化覆盖新游标；将游标登记移动到初始化 await 之前，旧请求只持有自身游标，不能替换新分页状态。

## 任务 3：验收与交付（主任务）

Files: integration_test/support/local_bili_fixture.dart、integration_test/visual_design_test.dart、docs/design/bting-design-system-v1.md、docs/testing/2026-10-24-search-categories.md。

- [x] 本机用户搜索fixture提供bili_user响应；真实Android深浅主题增加搜索/UP结果截图及往返检查。
- [x] 执行定向测试，再执行 tool/test-android.sh unit，原生 audio_modes_test.dart 与 visual_design_test.dart；截图实看。
- [x] 独立代码复核，修复本次引入问题；记录实际通过和未覆盖范围，提交源码/测试/文档。

执行命令：

```bash
source tool/android-env.sh
flutter test test/search_categories_test.dart test/up_home_mode_test.dart test/audio_modes_ui_test.dart test/feedback_layout_test.dart --no-pub --reporter expanded
tool/test-android.sh unit
# 原生使用专用模拟器，flutter drive --keep-app-running，测试后强停并关闭。
```

结果：117 项单元/组件、10 项打包检查、5 个原生功能场景、4 个原生视觉场景通过。具体边界与截图见[验收记录](../../testing/2026-10-24-search-categories.md)。
