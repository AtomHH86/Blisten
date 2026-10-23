# Desktop Android Testing Implementation Plan

> Execute the user's approved design with subagent-driven-development and focused test-driven changes.

**Goal:** 后续在电脑上重复验证 Android 听书、歌曲、演唱会功能。
**Architecture:** 保留现有业务；固定外部响应，运行真实 Android 播放器与存储；另列联网验证。
**Tech Stack:** Flutter 3.38.10、integration_test、Android Emulator、ADB、Bash/Python 工具。

## Global Constraints

- 不修改无关业务，不操作实体手机，不发布安装包。
- 工具链持久化，不依赖 /private/tmp 长期存在。
- 不把固定响应测试称为真实 B 站联网测试。
- 本次只测试和交付打包脚本；正式四个 APK 稍后生成。
- 正式打包不得静默回退调试证书，包大小由实际产物计算。

## Tasks

- [x] 1. 配置环境与模拟器：tool/android-env.sh、tool/setup-android-emulator.sh、tool/android-emulator.sh；检查加速、启动和设备身份。
- [x] 2. 新增 integration_test/ 原生回归：真实播放、独立速度、歌曲重选、长音频续播、缓存；pubspec 加 SDK 测试依赖。
- [x] 3. 补充有价值的规则/组件测试；tool/test-android.sh 串联静态检查、单元组件、模拟器测试，保存日志并传播失败状态。
- [x] 4. tool/build-android-apks.sh 与产物核验工具：签名预检、三个独立架构 APK 加 universal，保持相同 versionCode，导出校验和与元数据。
- [x] 5. 在模拟器实跑与复跑，修复发现的问题；审查本次变更，记录 docs/testing/2026-10-23-android-emulator.md 及可复制教程。

## Execution Notes

- 基线提交：31e9ff0，现有规则/组件测试为 57 项。
- 模拟器安装和集成测试文件由不同工作者并行负责，构建串行执行，避免 Gradle 输出互相覆盖。
- 最终验收：完整 all 与后续 integration 连续通过；真实 B 站 online 另行通过。正式四包未生成，符合用户确认范围。
