# 原生音频依赖发布处置记录

日期：2026-10-24。对象：本轮自建的 Android `libmpv.so`、`libmediakitandroidhelper.so`，覆盖 `arm64-v8a`、`armeabi-v7a`、`x86_64`。本记录在既有审计范围内复核固定源码、生成配置、库哈希和已有集成测试结果；没有复现漏洞，没有重新执行 Flutter、Gradle、ADB 或原生工具链。

**发布判断：已跟踪的原生公告具有下述版本修复或配置处置依据，可以进入最终 APK 核验；本记录不单独批准发布。** 网络候选 URL 的协议限制及对应测试已完成；仍需将四个最终签名 APK 的原生成员逐一映射至本记录的六份库。源码、通知和测试证据必须随最终发布保留。此结论不是全面漏洞零风险声明，也不是 ARM 真机播放或 16 KiB 页面设备的运行证明。

## 1. 输入和证据边界

旧资产及原问题以[原生来源审计](2026-10-24-dependencies/native-source-audit.md)、[原生安全审计](2026-10-24-dependencies/native-security-summary.md)、[官方公告原文快照](2026-10-24-dependencies/native-security-official-evidence.json)和[Mbed TLS 49 项矩阵](2026-10-24-dependencies/native-security-mbedtls-matrix.json)为基线。旧审计结论针对上游 JAR；不能将本轮自建结论反向用于旧 JAR。

本轮来源由 [sources.lock.json](../../tool/native-audio/sources.lock.json)固定，源码归档 URL 和 SHA256 均在其中。锁文件 SHA256 为 `988e7b69a68f99599aaf53a04539f428b63ec08d72ab3b3e77d130d19ecc65ad`。

| 组件 | 版本 / 固定提交 | 本轮变化 |
| --- | --- | --- |
| mpv | 0.35.1 / `140ec21c89d671d392877a7f3b91d67e7d7b9239` | 保留既有三份 mpv 补丁，启用 LGPL 模式；禁用独立 JPEG 输出的宿主自动检测 |
| FFmpeg | 6.1.6 / `f1e3a2bf7a2f2cde936d1ed97f09a26853d20125` | 替换 6.0；音频及封面图子集；禁用 libxml2、GPL 和 nonfree，启用 version3 |
| Mbed TLS | 3.6.7 / `068ff080b369adfac81509f9b57b2afabaf82dc5` | 替换 3.6.1；保留 ASM，固定 `-O2`，补丁启用 pthread 线程支持 |
| Mbed TLS framework | `dde0c4a0e448a0552f18817dcea633bb851fd288` | 固定 gitlink 对应源码，随源码材料保留 |
| media-kit-android-helper | `42054e5d479f39ccbb0ae604862e2bcaf59b74c2` | 替代旧配方移动 `main` 的来源不确定性；未修补 helper 代码 |
| Waf | 2.0.24 | 固定下载哈希，构建工具随材料记录 |

三份 mpv 补丁来自 [media-kit 官方构建提交](https://github.com/media-kit/libmpv-android-audio-build/tree/87744be8b337c50ed54961249b7a97c5e8cc37c9)，内容为 AudioTrack 线程处理、JavaVM 集成和移除 libass，不是终端公告的回补。[本轮 pthread 补丁](../../tool/native-audio/patches/mbedtls/001.enable-pthread.patch)只修改 Mbed TLS 配置头。详见[构建说明](../../tool/native-audio/README.md)。

源码输入比对（本机忽略目录 `build/native-audio/source-input-verification.json`）记录各组件与固定原始归档加补丁的文件一致性；这是源码输入核验，不是跨宿主逐字节可复现构建证明。工具链证据（本机忽略目录 `build/native-audio/toolchain.json`）记录 macOS 13.7.8 x86_64、NDK r28c `28.2.13676358`、Clang 19.0.1、CMake 3.22.1；原生目标 API 为 24。

## 2. Mbed TLS：49 项逐类处置

旧矩阵共有 49 个唯一公告，其中 42 项版本范围包含 3.6.1，7 项不包含。**42 是版本范围匹配数，不能称为 42 个已证实的应用漏洞。** 升级至 3.6.7 后，49 项中有 47 项可按版本范围排除当前版本，另两项必须保留配置条件。

| 分类 | 数量 | 3.6.7 处置 |
| --- | ---: | --- |
| 旧匹配、官方受影响范围有明确上限 | 38 | 相关 3.x 范围上限不晚于 3.6.6，3.6.7 位于范围外；其中包含一个未分配 CVE 的公告 |
| 旧匹配、表头写 All versions，但正文明确修复版本 | 2 | CVE-2025-27809、CVE-2025-27810 的正文明确截至 3.6.2，3.6.3 修复；3.6.7 包含修复 |
| 旧矩阵已排除 3.6.1 | 7 | 当前 3.6.7 仍在受影响范围外；不能把这七项计为本轮修复的旧漏洞 |
| CVE-2024-45157 | 1 | 按显式 CTR_DRBG 配置和文档一致性处置，不按版本修复处置 |
| CVE-2025-66442 | 1 | 按目标架构、ASM 配置和实际编译选项处置，不存在本轮可声称的通用修复版本 |
| 合计 | 49 | 47 项版本范围判定 + 2 项配置条件 |

38 项为：CVE-2024-49195；CVE-2025-52496、52497、49600、49601、49087、48965、47917、59438、54764；CVE-2026-34876、34873、34871、34875、34872、25833、34874、25835、34877、25834、50584、54435、50581、50640、35336、73064、50587、54441、50585、50580、50588、50586、73096、25832、50579、49300、50583，以及矩阵中 ID 为 `N/A` 的 [PKCS7 弱哈希公告](https://mbed-tls.readthedocs.io/en/latest/security-advisories/mbedtls-security-advisory-2026-07-pkcs7-weak-hash-algorithms-accepted/)。各条完整 ID、官方 URL、原始范围和源快照哈希见原矩阵，不能仅凭本段简称建立另一个计数口径。

七项原已排除记录为 CVE-2024-23170、23775、28960、45158、45159，CVE-2026-54434、50713。其中 CVE-2026-50713 涉及 3.6.3–3.6.6，不能因旧 3.6.1 未命中而忽略升级后的判断；3.6.7 仍在其范围外。

[27809 官方正文](https://mbed-tls.readthedocs.io/en/latest/security-advisories/mbedtls-security-advisory-2025-03-1/)说明 3.6.3 改为在未设置预期 hostname 时拒绝证书认证；[27810 官方正文](https://mbed-tls.readthedocs.io/en/latest/security-advisories/mbedtls-security-advisory-2025-03-2/)也明确 3.6.3 为修复版本。固定源码的 `ChangeLog` 记录相应变更。该版本修复不能代替应用主动启用 TLS 验证，后者见第 4 节。

**CVE-2024-45157。** [官方公告](https://mbed-tls.readthedocs.io/en/latest/security-advisories/mbedtls-security-advisory-2024-08-1/)说明 PSA 的 CTR/HMAC 选择曾被错误描述，3.6.1 起修正文档而没有改变行为。当前 FFmpeg `libavformat/tls_mbedtls.c` 显式使用 `mbedtls_ctr_drbg_seed` / `mbedtls_ctr_drbg_random`；三个 ABI 配置头没有启用 `MBEDTLS_PSA_HMAC_DRBG_MD_TYPE`。未发现“要求 HMAC、实际获得 CTR”的配置承诺。按当前显式 CTR 选择处置；不由此否定公告描述的不同侧信道特性。

**CVE-2025-66442。** [官方公告](https://mbed-tls.readthedocs.io/en/latest/security-advisories/mbedtls-security-advisory-2026-03-compiler-induced-constant-time-violations/)明确 Arm/x86 的 32/64 位目标在启用 `MBEDTLS_HAVE_ASM` 时不受所述优化问题影响，并建议默认 `-O2` / `-Os` 等选项。本次逐 ABI 读取生成证据：各 113 条 Mbed TLS 编译命令均含 `-O2`，未见 `select-optimize` 覆盖；各安装头均启用 ASM。这满足该公告给定的架构与构建条件，不是所有侧信道风险的证明。

三 ABI 的 `MBEDTLS_THREADING_C`、`MBEDTLS_THREADING_PTHREAD` 均已启用，库与消费者使用一致的配置头，满足固定源码对 TLS 1.3 多线程应用的要求。弱验证兼容宏 `MBEDTLS_SSL_CLI_ALLOW_WEAK_CERTIFICATE_VERIFICATION_WITHOUT_HOSTNAME` 均未开启。实际命令和配置保留于源码分发证据目录（本机忽略目录 `build/native-audio/distribution/evidence/`）下的各 ABI 子目录。

## 3. FFmpeg、libxml2 与 mpv

**FFmpeg CVE-2023-47342：版本修复已包含。** [官方安全页](https://ffmpeg.org/security.html)在 6.0.1 回补和 6.1 发布条目中列出该问题；[原始修复提交](https://github.com/FFmpeg/FFmpeg/commit/e4d5ac8d7d2a08658b3db7dd821246fe6b35381f)将 RTSP 回调的索引改为 `rtsp_st->stream_index`。固定 6.1.6 的 `libavformat/rtsp.c` 保留此修复。三 ABI 生成的 `config_components.h` 同时确认 `CONFIG_RTSP_DEMUXER=0`、`CONFIG_H264_DECODER=0`；后者是额外的构建约束，不替代修复证明，也不等于穷尽 FFmpeg 的全部可达代码。

**libxml2：从本次组合移除。** 三 ABI 的 `CONFIG_LIBXML2=0`、`CONFIG_DASH_DEMUXER=0`、`CONFIG_IMF_DEMUXER=0`，构建输入没有 libxml2 源码或静态归档，最终库依赖表也没有 libxml2。应用解析 B 站 JSON 中的独立音频 URL，不要求 FFmpeg 解析 DASH XML。因此旧 libxml2 2.10.3 公告不沿该构建依赖进入新组合；不是宣称旧 libxml2 已修复。最终 APK 仍须确认没有其他旧库混入。

**mpv GHSA-546v-22c3-7927：保留版本匹配，采用当前入口的配置处置。** [官方公告](https://github.com/mpv-player/mpv/security/advisories/GHSA-546v-22c3-7927)给出 `<0.41.0` 的范围，0.35.1 仍在范围内；该公告的 Patched versions 字段为 None，不能将保留旧版本写成已升级修复。

固定 mpv `player/client.c` 中的 `mpv_create()`加载 `etc/builtin.conf` 的 libmpv profile，设置 `config=no`、`terminal=no`、`input-terminal=no`、`osc=no`。media_kit 的初始化调用链使用 `mpv_create()`；Blisten 默认 Player 配置未覆盖终端选项，也未把原生媒体日志直接打印到终端。[native_tls_test.dart](../../integration_test/native_tls_test.dart)进一步读取并断言 `terminal=no`、`input-terminal=no`，在native-tls-green.txt（本机忽略目录 `build/release-readiness/native-tls-green.txt`）中通过。该证据支持公告要求的终端输出路径不在本次嵌入播放配置中；没有复现终端注入，也不据此声称整个 mpv 无漏洞。

## 4. TLS 应用配置、运行验证与数值 IP 局限

旧 mpv 默认将 `tls_verify=0` 传给 FFmpeg，因此仅更新 Mbed TLS 不足以保证 HTTPS 认证。[NativeAudioTls](../../lib/player/native_audio_tls.dart)现在要求 `tls-verify=yes`，加载可信 CA 文件并读取属性核实设置生效，失败时抛错。[本地 Android 插件](../../packages/media_kit_libs_android_audio/README.md)说明信任锚导出方式和边界：这是当前默认 X509TrustManager 的信任锚快照，不等同于原生播放器完整实现 Android Network Security Config。

已有 x86_64 Android 模拟器 debug 应用的定向测试日志 `native-tls-green.txt`以 `All tests passed!` 结束。四个业务测试分别证明：

1. 正式播放器配置拒绝未信任的 HTTPS 夹具证书。
2. 仅在集成测试播放器显式安装 test CA 后，HTTPS 媒体实际播放并推进位置。
3. `terminal`、`input-terminal` 的运行时值均为 `no`。
4. 信任证书但 hostname 不匹配时失败，夹具服务器收到的 HTTP 请求数为 0。

测试媒体 URL 已使用 `https://localhost`；证书包含匹配的 DNS SAN。测试 CA 和错误 hostname 夹具位于 `integration_test/`，不能作为正式流的信任例外。日志 SHA256 为 `be5bdc4aa1ad6bac94676d789376911d33b9eea2f73de80a4cebc2573eb0d6cd`。日志的 `+6` 包含测试钩子，不应表述为六个业务用例。

**数值 IP 是已知功能局限，但当前要求验证时会失败关闭。** FFmpeg 6.1.6 的 `tls_mbedtls.c` 对数值 IP 跳过 `mbedtls_ssl_set_hostname()`；Mbed TLS 3.6.7 的 `ssl_tls.c:get_hostname_for_verification()`在客户端 `VERIFY_REQUIRED` 下对此返回 `MBEDTLS_ERR_SSL_CERTIFICATE_VERIFICATION_WITHOUT_HOSTNAME`（`-0x5D80`）。本次未启用允许弱行为的兼容宏。因此不能声称此路径完成了 IP 身份验证，也不能将它描述为本组合中静默放过身份验证。

Mbed TLS 本身的 `x509_crt_check_san_ip()`支持 IPv4/IPv6 SAN 字节比较，但直接删掉 FFmpeg 的数值 IP 条件，还会使当前 Mbed TLS 把数字地址写入 SNI；[RFC 6066 第 3 节](https://www.rfc-editor.org/rfc/rfc6066.html#section-3)不允许这种 SNI。未实施该原生改动。本轮定向集成测试证明的是域名验证，不是数值 IP 成功路径；数值 IP 失败关闭结论来自固定源码和配置。

**协议入口已补齐：** 播放与下载均调用 `AudioTrack.httpsCandidates`，仅接受带有效主机、无凭据的 HTTP(S) 地址，HTTP 升级 HTTPS；返回时保留原始签名路径与 query。26 项单元检查通过。先运行未修复实现，三个 `resolveUrlFor()` 断言均以返回 content/file/ftp 地址而失败，尚未进入原生打开；修复后 `https-candidates-green.txt` 的七项行为（原四项加三类拒绝）全部通过，退出码 0。测试范围是 API 直接候选，不声称验证全部服务端重定向策略。

## 5. helper 的来源与 `content://` 遗留问题

新 helper 的提交、归档哈希和生成库已固定，解决的是旧配方跟随移动 `main` 的来源不确定性，未修补 helper 的所有缺陷。固定源码 `app/src/main/cpp/native-lib.cpp` 的 `MediaKitAndroidHelperOpenFileDescriptor` 仍把 `env` 而非 `&env` 作为 `GetEnv` 的输出指针使用，应作为遗留代码缺陷保留。

media_kit 1.2.6 的 `Media.normalizeURI()`只在输入 `content://` 时调用 `AndroidContentUriProvider`，后者经 FFI 到达该 helper 函数。当前应用没有接收外部媒体 URI 的 Activity VIEW 入口，已观察的正常播放路径使用 B 站 API 音轨 URL 或应用内部缓存文件；在这些正常入口中未发现该分支被调用的证据。

审查初期只作 `http://` 前缀替换，异常 API 数据中的 `content://` 可能到达 `Media`。第 4 节的过滤现已封住 API 直接候选入口，并通过原生集成测试；这不等于修复 helper 本身。未来增加文件选择、外部分享、ContentProvider 或任意 URI 播放前仍须重新审核 helper。当前不将此静态缺陷报告为已证实可利用漏洞，也不把固定提交或 MIT 许可证当成安全修复。

## 6. 最终库、源码材料和发布条件

本次重新读取六份库计算 SHA256，与全部 ABI 核验记录（本机忽略目录 `build/native-audio/all-abis-verification.json`）一致。该 JSON 的 SHA256 为 `a0abeef3946611c71ddd73b2dbc4011384c0e2e56fd51dc264435540bea87647`；构建输入与库映射（本机忽略目录 `build/native-audio/distribution/evidence/artifacts.json`）同时记录配方及补丁哈希。

| ABI | libmpv.so SHA256 | libmediakitandroidhelper.so SHA256 |
| --- | --- | --- |
| arm64-v8a | `8821c5e2ff9967e8923a73df75aff98d7c11106c6a10b7337b3320cde6b6b35a` | `7be5b566d4204f08a20c8dd81558d05c79ba2c7a7daa2f146c1750b89a788c1f` |
| armeabi-v7a | `5231caf5f2fa0535185b0c23a1c84385a065247d5afdfa49c29b4a083059b028` | `edb8727ea9263ec0d63babc12bcf494dcdd00abf192737b5c639d4efa73d5394` |
| x86_64 | `387361bd3b0437e7102e8a71ec892854fecd6583c227d1e98dc0b420de63e6dc` | `dfb2085f6d9a4d8a40f79ec70339dc14210cbd57efd90d134e48f5bb317f2755` |

核验记录显示各库的 ELF LOAD 对齐为 16384，依赖为 Android 系统库；这是 ELF 静态属性，不替代 APK ZIP 对齐检查或 16 KiB 设备运行验证。三 ABI 都有实际构建证据，但播放验证来自 x86_64 模拟器，不能改写为 ARM 真机通过。

源码归档核验（本机忽略目录 `build/native-audio/source-archive-verification.json`）记录 `distribution.tar.gz` 为 27,017,370 字节、SHA256 `bf2d36734cf334b0c3310708130be5dff4c879ec7dee700aaca16a55369a9e41`，74 个材料文件哈希已核验，并可从随附归档离线准备源码。这里的“离线准备源码”不是独立完成第二次全量编译。

[许可证通知目录](../../tool/native-audio/licenses/)和源码归档涵盖固定完整源码、framework、补丁、生成配置、实际构建命令、LGPL/GPLv3 文本、Mbed TLS 的 Apache 2.0 选择、helper MIT、IJG、Everest 及 NDK 运行时通知。同版本应用源码与重建、替换库及自行签名说明见构建 README。生产签名私钥不属于应分发材料。通知与对应源码必须实际随 Release 提供；本地文件存在不等于已经完成外部分发。

最终放行应记录以下结果后再作判断：

- 网络候选 HTTPS 协议过滤及拒绝异常 scheme 的测试通过，helper 遗留入口的处置范围同步更新。
- 三个单 ABI APK 与 universal APK 的 `lib/<ABI>/` 成员逐项对应上述库；无旧上游 JAR 混入。若打包再次 strip 导致字节变化，应保留可核验的转换/成员映射，不能直接沿用此表宣称相同。
- 四个 APK 的签名、包名、版本、ABI 和 ZIP 对齐通过既定打包检查；签名 APK 与实际测试对象关系被记录。
- Release 同时提供对应源码归档、应用同版本源码、通知和校验值；保留本记录引用的构建/测试证据，不将仅存在于忽略目录 `build/` 的日志当作永久公开证据。

本记录只处置上述已跟踪公告与具体配置问题。没有穷尽所有后续 FFmpeg/mpv 公告、所有编解码器输入、全部侧信道或整个依赖生态；没有运行漏洞利用或原生模糊测试。后续版本、构建选项、URI 入口、信任配置或打包成员改变时，应重新核对受影响结论。
