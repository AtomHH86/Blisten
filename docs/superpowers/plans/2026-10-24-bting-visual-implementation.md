# B听视觉与交互落地计划

> **For agentic workers:** Use subagent-driven-development for isolated file responsibilities; root owns integration and serialized Flutter/ADB execution. Steps below track implementation and verification.

**Goal:** 落实已认可的 B「闭眼听友」设计规范，完成视觉、交互修正与 Android 模拟器回归。

**Architecture:** 沿用 AppTheme、Material 控件和既有页面。按语义区分填充色与可点击文字，复用现有导入、收藏和播放逻辑；艺术资产由生图模型生成，布局与交互由 Flutter 实现。共享工具链只由主任务顺序执行。

**Tech Stack:** Flutter 3.38.10 / Dart 3.10.9；Android API 35 x86_64 专用模拟器；现有 Python 打包核验；内置 imagegen。

## Global Constraints

- 只在 Blisten 修改；不操作手机、不创建正式签名/发布 APK、不修改包名或数据键。
- 规范：docs/design/bting-design-system-v1.md；原模式规则保持不变。
- 优先最小修改，保留既有注释和换行；互不覆盖其他工作者的文件。
- 交互修复先写可复现测试，由主任务执行红/绿验证；纯视觉和机械资源变化以渲染、对比度和平台验收为主。

## Task 1: 主题与基础组件

Files: lib/core/theme/app_theme.dart；my_page/settings_page/theme_page/cache_page/cache_sheet/sleep_timer_page/about_page；tests covering readability/layout.

- [x] 按规范填入深浅色语义，保留旧接口兼容；增加 actionText/onPrimary/outline/semantic colors，迁移该任务页面的硬编码白字和蓝紫色。
- [x] 统一主题字号、圆角、点击目标和组件状态；修正小屏/大字出现的实际溢出，不顺手重构页面。
- [x] 主任务验证实际组件色对、点击区域、缩放和界面截图。

## Task 2: 发现、搜索、导入、登录和空/错误状态

Files: discover_page.dart, search_page.dart, up_home_page.dart, follow_page.dart, login_page.dart, widgets/resource_import_dialog.dart；test/ux_feedback_test.dart.

- [x] 先加入失败请求仍可重试、不误称断网；分页失败保留列表；登录轮询失败可见；表单大字保持可操作的测试。
- [x] 主任务运行针对性测试确认红色，再实现中性错误、局部重试、空态下一步和正确返回文案。
- [x] 统一这些页面的主题色、边界和点击区域，检查导入保留输入与模式。

Example behavioral expectation:
```dart
expect(find.textContaining('已自动切换离线'), findsNothing);
expect(find.text('重试'), findsWidgets);
```

## Task 3: 播放器、详情和播放条

Files: player_page.dart, book_detail_page.dart, widgets/mini_player.dart；BookPlayer only if retry requires minimal public operation；test/player_ux_test.dart.

- [x] 先测试详情移出收藏取消时保留收藏/进度、确认后执行；失败播放重试可恢复且不擅改分 P/进度策略。
- [x] 红色验证后复用已有移出确认；补真正可用的播放重试，避免把原始异常当唯一用户说明。
- [x] 统一主播放、进度、工具条样式；减少动效，提供语义标签和至少 48 dp 点击区域，修正窄屏与大字布局。
- [x] 保留返回不暂停、已有会话打开不重载；由既有集成测试验证模式规则。

## Task 4: 生图资产、启动和收藏入口

Root files: assets/；Android res；Windows icon；pubspec.yaml；splash_screen.dart；widgets/shelf_common.dart；bookshelf_page.dart；book_cards.dart；home_shell.dart；test/visual_layout_test.dart.

- [x] 从已选 B 图经 imagegen 生成干净透明角色及正式图标，检查身份特征，保留原图和提示词。
- [x] 制作各密度资源、Android 自适应/系统启动和 Flutter 启动资产；不增加固定等待时间。
- [x] 为缺失空收藏导入入口和 320 dp / 200% 大字溢出建立检查，红色后复用现有导入能力，修正所需布局。
- [x] 核对透明通道、图标裁切与启动画面，检查 dark/light 资源一致。

## Task 5: 集成验证、独立审阅与交付

Root files: integration_test/visual_design_test.dart；相关驱动/测试脚本（必要时）；docs/testing/2026-10-24-bting-design.md；截图与脱敏证据。

- [x] 顺序运行新组件测试与 tool/test-android.sh unit，修复实际失败。
- [x] 运行 tool/test-android.sh integration（含跨进程恢复），新增视觉场景覆盖主页面、导入、播放器、深浅色与大字；留存真实截图。
- [x] 检查启动、图标、通知/权限拒绝相关行为和读屏支持；无法完成的项目明确记录，不宣称通过。
- [x] 独立检查差异与业务兼容性，必要问题修复后复验。
- [x] 更新规范实施状态、README/变更记录/测试报告；明确 Windows、真实网络与正式签名包的验证边界；提交本地改动。

## 完成记录

2026-10-24：上述实施与本轮验证已完成，最终 `tool/test-android.sh all` 退出码 0。102 项单元/组件通过、1 项条件截图用例跳过，10 项打包核验通过，26 个原生场景通过。TalkBack 仅完成服务绑定和基础焦点冒烟，完整读屏、Windows 与真实网络边界见 [验收报告](../../testing/2026-10-24-bting-design.md)。
