# B听 1.0.0 候选 APK 与发布验收

状态：进行中。三种 ABI 的原生音频库及对应源码材料已构建、核对并冻结；API35 x86_64 全量原生回归已通过。尚未生成本轮四个候选 APK，尚未发布 GitHub。本文记录本轮实际证据，不把调试版集成测试结果算作正式安装包验收。

## 输入与签名

- 用户已授权首次创建 B听专用签名证书、本机备份、四包生成和安装包测试；通过发布检查后才发布 GitHub。
- 源码起点：`ca0a169870752056e48b5b54ab3d869948e26e75`；工作分支 `codex/release-v1`。包名 `com.bting.audio`，当前版本 `1.0.0+1`。
- 已创建 RSA-4096 / PKCS12 长期证书，别名 `blisten`；公开证书 SHA256：`da58f45d2a4309fb420b8508c97b6652f64a8417e4c2d876f5303d3e08bc2ee0`。
- 已核对本机备份字节一致，并将备份复制到临时隔离目录，实际签名一个验证 JAR，使用 `jarsigner -verify -strict` 验证成功；恢复证书摘要一致。
- 私钥、密码与 `key.properties` 不入版本库或发布资产。两份备份均在同一台 Mac，不能防止整机损坏；另存受控外部备份仍需完成。
- GitHub 官方设备授权已成功，API 已核实账号为 `AtomHH86`；用户明确选择公开仓库，目标为 `AtomHH86/Blisten`。创建前已查该账号同名仓库不存在，尚未进行远程写入。

## 发布前代码修复

旧更新逻辑选择 Release 中第一个 `.apk`，四种架构一起发布时可能为设备下载错误架构。现改为选择地址有效的 `-universal.apk`；没有通用包时，现有界面回退到 Release 页面。

验证：新增 11 项回归测试。修复前真实运行 5 项通过、6 项断言失败；修复后连同原应用身份测试共 14 项通过。静态分析已通过，独立静态审查未发现阻塞。证据在忽略目录 `build/release-readiness/app-update-red.txt` 和 `app-update-green.txt`。

## 依赖与原生构建

- 已实际执行 `:app:dependencies --configuration releaseRuntimeClasspath -Ptarget-platform=android-x64`，Gradle 成功。此 release 图没有之前 debug 图中的 `junit:junit:4.12`、`com.google.guava:guava:28.1-android` 或 `integration_test` 项目。`com.google.guava:listenablefuture:1.0` 是另一个坐标。[保存的 release 图](../reviews/2026-10-24-dependencies/release-runtime-classpath.txt)含 88 个解析后的 Maven 坐标；图本身不能替代最终 APK 成员核对。
- 官方音频资产 v1.1.9 仍采用之前审计中的旧组件组合；直接更换该资产不能关闭已知问题。
- 已完成固定源码自建：mpv 0.35.1 保留三份上游音频集成补丁，FFmpeg 更新至 6.1.6，Mbed TLS 更新至 3.6.7 并启用 pthread 支持；裁剪配置禁用 libxml2、DASH/IMF demuxer。helper 固定为 `42054e5d479f39ccbb0ae604862e2bcaf59b74c2`，Mbed TLS framework 也按源码 gitlink 固定。版本、完整提交与源码归档哈希见[原生构建说明](../../tool/native-audio/README.md)和[源码锁文件](../../tool/native-audio/sources.lock.json)。
- 使用 NDK `28.2.13676358`、原生 API24，完成 `arm64-v8a`、`armeabi-v7a`、`x86_64` 三种 ABI 的 `libmpv.so` 和 `libmediakitandroidhelper.so`。六个文件的 ELF `LOAD` 对齐均为 16,384 字节，已记录动态依赖及 JavaVM 符号检查。此结果是原生库静态证据，尚不包含最终 APK ZIP 对齐或 16KiB 系统运行验收。
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

日志中的 `+6` 包含测试钩子，不应写成六项行为测试。此结果属于调试集成入口；新库下的完整原生回归和真实 B 站联网播放随后分别通过；正式候选包仍需单独验收。

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
| 四包签名、包名、版本、ABI、SHA256、16KiB 静态检查 | 待构建 |
| 专用 API35 x86_64 模拟器安装生产 APK | 待验 |
| 搜索、BV 导入、播放、暂停、后台、进度恢复 | 待验 |
| 缓存与取消/确认清理 | 待验 |
| universal 同版本覆盖安装与数据保留 | 待验；不等同跨版本迁移 |
| ARM64 / ARMv7 实际设备、16KiB 系统 | 未实测 |
| 最终 APK 内原生库、notices 与对应源码材料映射 | 待候选包生成后核验 |
| GitHub Release 与下载资产回读核验 | 待发布条件满足 |

原始日志、设备截图与构建缓存留在忽略目录；仅将经过核对且不含凭据的结论和清单加入源码仓库。

完整原生回归证据：`build/desktop-tests/20261024-165659-15774`，运行及退出清理均为 0；主日志含 18 个测试进程、76 项行为，独立后台寿命进程另含 1 项。已检查生成的浅色定时与深色倍速大字截图。此后追加了 HTTPS 候选过滤及 GitHub 入口配置，按影响追加定向原生和完整单元检查，不把两轮重复用例相加计数。

最终 HTTPS 地址过滤：旧实现的 content/file/ftp 三项真实断言失败（均发生在原生打开前）；最小修复后，七项 TLS/协议行为通过。证据为 `https-candidates-red.txt`、`https-candidates-green.txt`。GitHub 源码、反馈、手动更新入口已配置到 `AtomHH86/Blisten`；空配置仍不访问网络，独立官网保持未开放，原项目致谢保留。原生公告逐项处置见[原生发布处置记录](../reviews/2026-10-24-native-release-disposition.md)，公开内容检查见[审查记录](../reviews/2026-10-24-publication-content-check.md)。

最终 Android 调试构建和 `lintDebug` 通过，证据 `android-lint-final.txt`。替换本地插件后的 release 依赖图已重新生成并保存。真实联网运行 `online-final.txt` 退出码 0，三个搜索分别返回 15、20、20 条，在线进度 3051ms；测试使用游客，不使用个人 B 站账号。
