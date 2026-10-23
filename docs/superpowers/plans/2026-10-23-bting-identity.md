# B听 Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 将 Blisten 的已确认应用身份改为 B听并验证独立 Android 包，生成三个生图设计方向供用户选择。

**Architecture:** 保留现有 Flutter 页面与播放架构，只修改身份、展示与上游服务归属。视觉生成与非视觉代码并行，图标和主题替换等待用户选定方向。

**Tech Stack:** Flutter 3.38.10、Dart 3.10.9、Kotlin/Android、Bash、Python、内置 imagegen。

## Global Constraints

- 以 ../specs/2026-10-23-bting-identity-design.md 的已确认内容为准。
- 仅修改 Blisten；旧 abts 和旧应用数据保持完整。
- 不生成正式证书/四包，不发布远程。
- 不改播放业务规则、内部持久化键及原生通信通道。
- 原始 CRLF 保持；新文件按项目风格。

### Task 1: 平台与构建身份

负责 android/、windows/、pubspec.yaml/lock、tool/ 和既有 test/integration_test 的 package 导入。

- [x] 改为 blisten、1.0.0+1、com.bting.audio，同步 Kotlin 包、应用标签与 Windows 显示字段。
- [x] 移除 umeng_common_sdk 依赖与原生初始化/混淆规则。
- [x] 同步测试脚本新包名、APK前缀 Blisten 和打包测试，保留签名门禁。
- [x] 校验脚本语法与打包测试，无正式包产出。

### Task 2: 应用文案与服务归属

负责 lib/ 与新增 test/app_identity_test.dart，不触碰平台构建文件。

- [x] 先添加针对上游更新源关闭和关于页归属的行为检查并确认失败。
- [x] AppMeta/启动/通知/分享显示 B听，口号统一；主应用类更名。
- [x] 停用上游更新源，关于页显示独立项目尚未配置链接的状态，明确上游致谢与MIT。
- [x] 移除实际统计逻辑，保留无操作调用接口以减少无关业务改动。
- [x] 全局收藏、三模式入口、混合计数与分模式单位一致；不改布局、图标及主题。

### Task 3: 三种图标与开屏概念

负责 docs/design/bting-v1/，使用内置 imagegen 每方向一次调用。

- [x] 三方向分别生成：极简声标、闭眼听友、现场声浪。
- [x] 检查图形与中文文字，保存原图及完整 prompts；内联展示供选择。
- [x] 将它们标记为未选定概念，不覆盖正式 assets/ 与 Android 图标。

### Task 4: 文档与验收

负责 README、CHANGELOG、当前操作文档与验收记录。

- [x] 更新来源文字、独立身份、版本、未配置远端状态、独立数据和签名要求。
- [x] `tool/test-android.sh unit` 与 `tool/test-android.sh integration` 通过。
- [x] 核对新包名安装、统计移除、旧包保留、签名门禁和差异检查。
- [x] 提交已验证的代码与设计提案；报告视觉资产仍待选择。
