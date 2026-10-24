# B听 1.0.0 候选 APK 与发布验收

状态：本机发布验收通过。四种正式签名 APK 已构建，x86_64 全新安装和 universal 同版本覆盖安装、真实联网与断网缓存播放通过。远程 CI 的实际状态见 [Actions](https://github.com/AtomHH86/Blisten/actions/workflows/ci.yml)，公开附件以 [v1.0.0 Release](https://github.com/AtomHH86/Blisten/releases/tag/v1.0.0) 为准。本文分别记录代码回归、成品包验证和未实测范围。

## 输入与签名

- 用户已授权首次创建 B听专用签名证书、本机备份、四包生成和安装包测试；通过发布检查后才发布 GitHub。
- 源码起点：`ca0a169870752056e48b5b54ab3d869948e26e75`；工作分支 `codex/release-v1`。包名 `com.bting.audio`，当前版本 `1.0.0+1`。最终 APK 源码为干净提交 `ee246d76e892218581b8faea1bf09a73315973e1`，`v1.0.0` 标签对应此提交；之后的 main 提交补充验收记录及 CI 环境配置，不修改应用或原生构建输入。
- 已创建 RSA-4096 / PKCS12 长期证书，别名 `blisten`；公开证书 SHA256：`da58f45d2a4309fb420b8508c97b6652f64a8417e4c2d876f5303d3e08bc2ee0`。
- 已核对本机备份字节一致，并将备份复制到临时隔离目录，实际签名一个验证 JAR，使用 `jarsigner -verify -strict` 验证成功；恢复证书摘要一致。
- 私钥、密码与 `key.properties` 不入版本库或发布资产。两份备份均在同一台 Mac，不能防止整机损坏；另存受控外部备份仍需完成。
- GitHub 官方设备授权已成功，API 已核实账号为 `AtomHH86`；用户明确选择公开仓库，目标为 `AtomHH86/Blisten`。已创建该公开仓库并通过 API 回读确认，私密漏洞报告已启用；未上传生产签名材料。

## 发布前代码修复

旧更新逻辑选择 Release 中第一个 `.apk`，四种架构一起发布时可能为设备下载错误架构。现改为选择地址有效的 `-universal.apk`；没有通用包时，现有界面回退到 Release 页面。

验证：新增 11 项回归测试。修复前真实运行 5 项通过、6 项断言失败；修复后连同原应用身份测试共 14 项通过。静态分析已通过，独立静态审查未发现阻塞。证据在忽略目录 `build/release-readiness/app-update-red.txt` 和 `app-update-green.txt`。

## 依赖与原生构建

- 已实际执行 `:app:dependencies --configuration releaseRuntimeClasspath -Ptarget-platform=android-x64`，Gradle 成功。此 release 图没有之前 debug 图中的 `junit:junit:4.12`、`com.google.guava:guava:28.1-android` 或 `integration_test` 项目。`com.google.guava:listenablefuture:1.0` 是另一个坐标。[保存的 release 图](../reviews/2026-10-24-dependencies/release-runtime-classpath.txt)含 88 个解析后的 Maven 坐标；图本身不能替代最终 APK 成员核对。
- 官方音频资产 v1.1.9 仍采用之前审计中的旧组件组合；直接更换该资产不能关闭已知问题。
- 已完成固定源码自建：mpv 0.35.1 保留三份上游音频集成补丁，FFmpeg 更新至 6.1.6，Mbed TLS 更新至 3.6.7 并启用 pthread 支持；裁剪配置禁用 libxml2、DASH/IMF demuxer。helper 固定为 `42054e5d479f39ccbb0ae604862e2bcaf59b74c2`，Mbed TLS framework 也按源码 gitlink 固定。版本、完整提交与源码归档哈希见[原生构建说明](../../tool/native-audio/README.md)和[源码锁文件](../../tool/native-audio/sources.lock.json)。
- 使用 NDK `28.2.13676358`、原生 API24，完成 `arm64-v8a`、`armeabi-v7a`、`x86_64` 三种 ABI 的 `libmpv.so` 和 `libmediakitandroidhelper.so`。六个文件的 ELF `LOAD` 对齐均为 16,384 字节，已记录动态依赖及 JavaVM 符号检查。此结果是原生库静态证据；随后最终 APK ELF/ZIP 对齐也通过，但没有 16KiB 系统运行验收。
- `build/native-audio/source-input-verification.json` 核对了五个源码组件共 11,055 个文件，与锁定归档加补丁一致；三个 ABI 的构建清单记录相同的源码锁、配方、选项和补丁哈希。完整输出证据在 `build/native-audio/*-verification.json` 及各 ABI 的 `manifest.json`。

| ABI | `libmpv.so` 字节数 | `libmediakitandroidhelper.so` 字节数 |
| --- | ---: | ---: |
| arm64-v8a | 5,929,992 | 383,288 |
| armeabi-v7a | 5,251,952 | 234,460 |
| x86_64 | 6,740,360 | 375,368 |

对应源码材料 `build/native-audio/distribution.tar.gz` 已生成并核验：**27,017,370 字节**，SHA256 为 `bf2d36734cf334b0c3310708130be5dff4c879ec7dee700aaca16a55369a9e41`。归档含完整源码归档、framework 子模块、补丁、构建配方、配置证据、许可证和通知；`source-archive-verification.json` 记录 74 个文件哈希验证通过，并能从随包归档离线完成源码准备。这里未宣称已在另一台机器离线重编译，或不同工具链可产生逐字节相同的库。

发布时须把该源码材料与最终 APK 同批提供，并使同版本 Blisten 源码可获得。历史依赖审计保留原结论；本轮升级、裁剪与固定来源的事实不能替代剩余原生公告可达性结论，以及最终 APK 中实际 `.so`、notices 和源代码材料的对应核验。

## 原生 HTTPS 证书校验

本轮负向测试发现：仅更新原生库仍不足以启用证书校验。未显式配置的播放器接受了本机不可信证书，`playBook()` 返回 `true`，真实 RED 记录在 `build/release-readiness/native-tls-red.txt`。这证明测试端点可被接受，不代表已发生线上攻击或真实账号泄露。

修复在两个在线打开入口前启用 `tls-verify=yes`，通过 Android 默认信任管理器导出应用私有、排除备份的 CA 文件，并读回核对原生属性；信任导出或属性设置失败时停止打开。并发播放请求共享初始化结果，初始化失败允许重试。测试 CA 仍仅由集成测试夹具显式设置，没有加入生产资产、系统信任库或应用设置。

测试准备阶段补齐了 `player.setup()`，使原生错误经正式播放器监听回传；一次调试运行曾被通知权限弹窗阻塞，该次不计为通过。随后在专用 API35 x86_64 模拟器上完成运行，退出码为 0，`native-tls-green.txt` 记录以下四个行为用例通过：

- 生产播放路径拒绝不可信 HTTPS 证书，返回失败且不进入播放状态。
- 显式信任测试 CA 后，原生 HTTPS 音频可播放且进度达到至少 2 秒。
- 内嵌播放器的 `terminal` 与 `input-terminal` 均为 `no`。
- 已信任证书的主机名不匹配时拒绝连接，测试服务器未收到 HTTP 请求。

日志中的 `+6` 包含测试钩子，不应写成六项行为测试。此结果属于调试集成入口；新库下的完整原生回归和真实 B 站联网播放随后分别通过；正式候选包的单独验收结果见下表。

## 本轮已核验的检查

以下均有本机原始日志；后续源码变化仍须按影响复验，不能以本表代替最终候选包检查。

| 检查 | 已观察结果 | 本机证据 |
| --- | --- | --- |
| 更新下载回归与应用身份 | 修复前 5 通过 / 6 断言失败；修复后 14 通过 | `build/release-readiness/app-update-red.txt`、`app-update-green.txt` |
| TLS 配置单元测试 | 7 通过，覆盖属性读回、空 CA、导出失败与显式测试信任 | `build/release-readiness/native-tls-unit.txt` |
| Flutter 单元与组件 | 最终代码 302 通过、1 跳过（可选截图导出，需 ABTS_CAPTURE_UI=1）；包含 26 项地址过滤检查 | `build/release-readiness/flutter-unit-final.txt` |
| Python 检查 | 94 通过，含 CA 导出及原生库准备规则 | `build/release-readiness/python-tests.txt` |
| Flutter 静态分析 | 最终代码 `No issues found` | `build/release-readiness/analyze-final.txt` |
| 原生 TLS 定向集成 | 4 个行为用例通过，进程退出码 0 | `build/release-readiness/native-tls-green.txt` |

原生库准备规则的单元测试已验证旧构建指纹、错误架构、额外库等拒绝行为。随后实际执行 Gradle `verifyNativeAudio`：注入额外 `libold.so` 和修改来源摘要的两次负向检查均按预期失败；恢复原文件后正常检查通过。证据为 `gradle-reject-extra-so.txt`、`gradle-reject-stale-source.txt` 和 `gradle-native-final.txt`。

## 实际 APK 验收记录

| 项目 | 状态 |
| --- | --- |
| 新原生库下完整集成回归与真实联网冒烟 | 全量 77 项行为测试通过（19 次 drive，含独立后台寿命检查）；真实联网通过：搜索 15/20/20 条，BV1wB4y1R7Sg 播放进度 3051ms |
| 三 ABI 准备及真实 Gradle 旧库/额外库拒绝 | 通过；测试后恢复，正常输入再次通过 |
| 四包签名、包名、版本、ABI、SHA256、16KiB 静态检查 | 全部通过；所有包 non-debuggable，minSdk24 / targetSdk36 |
| 专用 API35 x86_64 模拟器安装生产 APK | x86_64 全新安装成功；从设备拉回 base.apk，哈希与构建件相同 |
| 搜索、BV 导入、播放、暂停、后台、进度恢复 | 真实歌曲 / UP 搜索和 BV 导入通过；后台 46,781→72,000ms，暂停两次均 74,250ms，快进 01:14→01:29，强停后按进度续播 |
| 缓存与取消/确认清理 | 实际缓存 1 项 / 界面 3.5 MB；取消保留，确认后为空，收藏与记录保留；完全断网播放另见下文 |
| universal 同版本覆盖安装与数据保留 | 成功，设备 base.apk 哈希一致；收藏 1 项、缓存 1 项、深色主题和 02:21 进度保留；不等同跨版本迁移 |
| ARM64 / ARMv7 实际设备、16KiB 系统 | 未实测 |
| 最终 APK 内原生库、notices 与对应源码材料映射 | 独立核验通过；12 项 mpv/helper 与冻结六库逐字节相同，各包 20 项原生通知/清单一致，无旧库或测试证书夹具 |
| GitHub Release 与下载资产 | 使用同批四包、对应源码、manifest、SHA256SUMS 和公开核验 JSON；公开状态以 Release 实际附件为准 |

原始日志、设备截图与构建缓存留在忽略目录；仅将经过核对且不含凭据的结论和清单加入源码仓库。

完整原生回归证据：`build/desktop-tests/20261024-165659-15774`，运行及退出清理均为 0；主日志含 18 个测试进程、76 项行为，独立后台寿命进程另含 1 项。已检查生成的浅色定时与深色倍速大字截图。此后追加了 HTTPS 候选过滤及 GitHub 入口配置，按影响追加定向原生和完整单元检查，不把两轮重复用例相加计数。

最终 HTTPS 地址过滤：旧实现的 content/file/ftp 三项真实断言失败（均发生在原生打开前）；最小修复后，七项 TLS/协议行为通过。证据为 `https-candidates-red.txt`、`https-candidates-green.txt`。GitHub 源码、反馈、手动更新入口已配置到 `AtomHH86/Blisten`；空配置仍不访问网络，独立官网保持未开放，原项目致谢保留。原生公告逐项处置见[原生发布处置记录](../reviews/2026-10-24-native-release-disposition.md)，公开内容检查见[审查记录](../reviews/2026-10-24-publication-content-check.md)。

最终 Android 调试构建和 `lintDebug` 通过：0 错误、12 警告（BatteryLife 1、ExportedService 1、ObsoleteSdkInt 2、IconLauncherShape 5、UseKtx 3），不是零警告。证据 `android-lint-final.txt`。替换本地插件后的 release 依赖图已重新生成并保存。真实联网运行 `online-final.txt` 退出码 0，三个搜索分别返回 15、20、20 条，在线进度 3051ms；测试使用游客，不使用个人 B 站账号。

## 成品与真实离线验证

| APK | 字节数 | SHA256 |
| --- | ---: | --- |
| `Blisten-v1.0.0-arm64-v8a.apk` | 27,986,371 | `d1f094ca4877f164152480c4835e0747d6236d3cf633428642e078a8c9c232df` |
| `Blisten-v1.0.0-armeabi-v7a.apk` | 24,817,975 | `20d73da0e032679b296a4bc2439e1a804d07d25b00edb91708654d68b4bee037` |
| `Blisten-v1.0.0-x86_64.apk` | 30,205,745 | `699715dbe91183865dbe2e07aa2ccac14225c30743aa64e0fb44da3ba0a35d33` |
| `Blisten-v1.0.0-universal.apk` | 76,950,231 | `0c749a8ae515e21f7492e4f19f8b8145dbaa4100afbcc241d789e50d9a55e710` |

正式包测试使用游客及单个公开 BV 资源，没有个人账号；不分发该测试音频。设备退出记录中未观察到应用崩溃或 ANR，已记录的退出为测试强停和包覆盖。

universal 的缓存播放在重建应用进程后、虚拟网卡 eth0 完全断开时测试：测试前后均没有外网路由，B 站请求均返回 Network is unreachable；音频从 209,098ms 播放至 219,047ms，随后恢复网络成功。第一次只等待 4 秒的采样未进入播放态，不算通过；第二次等待实际起播后通过。约 8.61 秒的离线冷启动等待来自在线目录尝试失败后的本地回退，列为后续体验优化，不据此宣称瞬时离线启动。

公开附件 `apk-runtime-verification.json` 与 `apk-native-verification.json` 保存检查结果和证据哈希；原始截图、设备日志、拉回的安装包留在本机忽略目录。公开 `manifest.json` 仅移除了 Flutter SDK 的本机安装路径，其余构建信息和 APK 哈希保持不变。源码归档及原生核验 JSON 一同提供。

尚未验证 ARM64/ARMv7 实机、API24/25/28/33/36、16KiB 页系统、厂商后台限制、真实电话/蓝牙中断、完整 TalkBack、人工听音和耗电/性能基线。静态兼容检查不能替代这些运行证据，也不承诺所有 B 站资源始终可用。

远程 CI 首次运行在 `Install native audio build tools` 失败，原因是 runner 的 `sdkmanager` 不在 PATH（退出码 127），尚未进入原生编译。工作流改为通过 Android SDK 根目录显式调用 `cmdline-tools/latest/bin/sdkmanager`；此环境修复不修改已验收 APK、应用源码或固定原生构建配方。修复后的远程结果以 Actions 和 Release 附件 `ci-verification.json` 为准。
