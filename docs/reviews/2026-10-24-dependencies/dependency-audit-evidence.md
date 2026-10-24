# 依赖、许可证与 OSV 查询证据

审计日期：2026-10-24。此轮只读取现有依赖和构建材料，查询公开包坐标与官方资料；没有升级依赖、执行 Flutter/Gradle/ADB、修改生产代码或发布。发送到 OSV 的内容仅为公开包名和版本，没有上传项目源码、凭据、日志或本机路径。

## Dart 输入与许可证清单

[dart-license-inventory.json](dart-license-inventory.json) 含 124 项：123 个锁文件条目及根应用。来源分布为 hosted 115、SDK 7、path 1、根应用 1；记录精确版本、依赖分类、来源路径和发现的包根目录 LICENSE/COPYING/NOTICE 文件 SHA256。[CSV](dart-license-inventory.csv) 提供表格视图。本机路径在交付材料中使用占位符。

115 个 hosted 包均找到包根目录许可证材料。BSD/MIT/Apache 等标签由文本规则辅助识别，可能同时命中多个 notice；这些是许可证候选分类，不能视作法律审查通过。六项最初缺少包根目录文件的来源已注明：本地新写的 `blisten_audio_focus` 按当前仓库许可证约定指向根项目 MIT；Flutter 的 driver/test/web/fuchsia/integration 五个 SDK 包采用 Flutter SDK 根许可证。`sky_engine/LICENSE` 是包含 MIT/BSD/Apache/LGPL/GPL/MPL 等内容的引擎第三方通知汇编，不能将整个包描述为单一 MIT 或 GPL。

直接应用依赖为 `audio_service 0.18.19`、`blisten_audio_focus 0.0.1`、`cached_network_image 3.4.1`、`crypto 3.0.7`、`cupertino_icons 1.0.9`、`dio 5.11.1`、`media_kit 1.2.6`、`media_kit_libs_audio 1.0.7`、`path_provider 2.1.6`、`permission_handler 11.3.1`、`provider 6.1.5+1`、`qr_flutter 4.1.0`、`share_plus 12.0.2`、`shared_preferences 2.5.5` 及 Flutter SDK。完整传递依赖保留在 JSON/CSV 中。

SDK 版本从缓存的 `flutter.version.json` 读取，没有执行 SDK 命令：Flutter `3.38.10`，framework 提交 `c6f67dede3d4aa1aa7a69dd56a3494a5cde6cc80`，engine 提交 `cafcda5721a78a7884db92f13c5e89f7643d52dd`，Dart `3.10.9`。

| 输入 | SHA256 |
|---|---|
| pubspec.lock | 5704e6735c4f7fb15c50ed5ba0964d240ccced8379f9666dd2ddf6838dae927f |
| package_config.json | e5c9969f5a454a3ca12a0206ad2c5acf12512c5a970d4f6d716e77e19f206037 |

这些哈希标识本次审计输入，不声明后续修改后的文件仍相同。

## Android 清单的来源与范围

[native-license-inventory.json](native-license-inventory.json) 记录既有 app **debug lint model** 中的 97 个唯一 Maven 坐标、模型路径与 SHA256、缓存 POM 来源及声明或继承的许可证候选。模型时间为 `2026-10-24T04:23:43Z`，它是一次已观察到的 debug 构建快照，**不是 release 依赖锁或完整 release SBOM**。

Guava/Hamcrest 子 POM 缺失的许可证信息由父 POM 追溯补充。Flutter embedding/engine Maven 资产在缓存 POM 中没有有效许可证声明，因此仍需使用 Flutter 汇编通知作为证据。不能从旧构建或缓存目录反推当前依赖：例如旧 `umeng_common_sdk` 构建目录虽然存在，但当前锁文件、package_config 和选定 app debug 模型均未证明它属于本次依赖，故未计入。

原生音频来源已进一步核验：[来源审计](native-source-audit.md)记录了四个 JAR 与发布资产的哈希和大小一致性、固定构建配方、组件标签及本地版本/许可证字符串；[安全审计](native-security-summary.md)记录了已知公告和构建条件。剩余缺口是实际 release 成员、可复现构建、辅助库历史提交、完整分发材料及安全公告适用性处理，不能再笼统说成“原生来源完全未核验”，也不能反向声称已全部放行。

## OSV 查询结果

[osv-evidence.json](osv-evidence.json) 保留 115 个 Pub 与 97 个 debug Maven 坐标的查询、顺序对应的返回及完整匹配公告，共 212 项；此次所有响应已返回，没有未完成的分页。115 个 Pub 坐标返回 **0 项匹配**，不等于没有漏洞，也不覆盖 SDK、Flutter 引擎或原生捆绑组件。

Debug 模型中出现以下已知版本匹配：

| 坐标 | 公告 / CVE | 适用范围说明 |
|---|---|---|
| junit:junit:4.12 | GHSA-269g-pwp5-87pp / CVE-2020-15250 | TemporaryFolder 本地信息泄露；需判断测试框架及相关 API 的实际使用 |
| com.google.guava:guava:28.1-android | GHSA-5mg8-w23w-74h3 / CVE-2020-8908 | 临时目录创建问题；受影响 API 与运行环境是适用条件 |
| com.google.guava:guava:28.1-android | GHSA-7g45-4rm6-3mm3 / CVE-2023-2976 | FileBackedOutputStream 临时文件泄露；需核对调用路径和环境 |

Flutter SDK 的 `integration_test` Gradle 源码声明了 Guava 28.1-android 和 Android 测试库，所观察的 debug 图包含这套测试框架。**这不能证明正式包包含同样的依赖，更不能证明 Blisten 可被利用。** 正式包是否包含它们、是否使用受影响 API，需用实际 release 图和产物核验。本次没有执行依赖升级或修复。

官方依据包括 [OSV querybatch API](https://google.github.io/osv.dev/post-v1-querybatch/) 的批次顺序与分页约定、[JUnit 维护者公告](https://github.com/junit-team/junit4/security/advisories/GHSA-269g-pwp5-87pp)和 [Guava 维护者 issue 6532](https://github.com/google/guava/issues/6532)。完整公告中的别名、范围和引用仍保留在 JSON。审计时 [Flutter 官方安全公告页](https://github.com/flutter/flutter/security/advisories)没有列出已发布公告；这不构成完整的 Flutter 引擎或 Dart 安全审计。

## 交付边界与下一步

本目录提供清单和证据，不附带早期其他构建变体的查询材料或未完成的自动化脚本，也不承诺可以一条命令完整再生本次结果。后续自动化需保留父 POM 追溯、明确输入与构建变体新鲜度、选取实际 release 图、处理分页，并单独说明 SDK/原生组件的覆盖范围。

发布检查还需记录实际 release 依赖图中的 AAR/JAR 及其哈希，核对它们与 APK 原生库成员、DEX 产物的对应关系，并整理合并后的 notices 和对应源码材料，并处理[原生安全公告](native-security-summary.md)。POM 声明、缓存文件和封装层 MIT 许可证都不能独立证明最终产物的许可证材料完整或安全检查通过。
