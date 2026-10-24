# B听 Android 原生音频构建

此配方替换 media_kit 旧音频 JAR 中来源不完整的预编译库。构建仅写入本仓库的 `build/native-audio/`，不执行 Gradle、不使用 sudo、不修改全局 Pub 缓存。构建操作不等于 APK 播放测试通过。

## 固定来源与变化

| 部分 | 固定版本 | 用途与许可证 |
| --- | --- | --- |
| mpv | 0.35.1 / `140ec21c89d671d392877a7f3b91d67e7d7b9239` | libmpv API；`--enable-lgpl`，LGPL 2.1 或后续版本 |
| FFmpeg | 6.1.6 / `f1e3a2bf7a2f2cde936d1ed97f09a26853d20125` | 音频解封装/解码；禁用 GPL、nonfree，启用 LGPL 3 |
| Mbed TLS | 3.6.7 / `068ff080b369adfac81509f9b57b2afabaf82dc5` | HTTPS；选择 Apache 2.0 授权 |
| Mbed TLS framework | `dde0c4a0e448a0552f18817dcea633bb851fd288` | 由上述提交的 gitlink 确定；生成脚本和完整源码材料 |
| media-kit-android-helper | `42054e5d479f39ccbb0ae604862e2bcaf59b74c2` | JNI / JavaVM / AudioTrack 集成；MIT |
| Waf | 2.0.24 | mpv 构建工具；使用 mpv bootstrap 中公布的 SHA256 |

所有源码归档地址和 SHA256 在 `sources.lock.json`。mpv 保留已经审计的上游 `libmpv-android-audio-build` v1.1.8 配方（提交 `87744be8b337c50ed54961249b7a97c5e8cc37c9`）的三份补丁：AudioTrack 线程安全、JavaVM 入口、移除 libass。每份 mpv 补丁保留原文。2026-10-24 新增 Mbed TLS `include/mbedtls/mbedtls_config.h` 补丁，启用 `MBEDTLS_THREADING_C` 和 `MBEDTLS_THREADING_PTHREAD`，满足 TLS 1.3 在多线程应用中的明确要求；消费者与库使用同一头文件。Mbed TLS 固定 `-O2` 并保留汇编。mpv 禁用独立 JPEG 输出的宿主自动检测，FFmpeg JPEG/PNG 解码保留。FFmpeg 保留原音频及封面图功能子集，明确禁用 libxml2；DASH/IMF demuxer 也必须被配置为禁用。B 站 DASH 音频 URL 由应用解析，播放单独音轨无需 FFmpeg 解析 DASH XML。

不运行上游 bundle.sh（其中含 sudo、重置源码、移动分支 helper 和 Linux 固定路径）。没有新增对会员音质的支持或改变三种模式的倍速/续播规则。

## 构建

需要 Android SDK、NDK **28.2.13676358**、SDK CMake **3.22.1**、Ninja、NASM、pkg-config、make、patch、Python **3.12+**（构建入口及安全解压），以及 Python **3.9–3.11**（旧 Waf 2.0.24）。这些是本轮实际使用的工具组合；其他版本未经本轮验证。

```bash
# 在 Blisten 仓库根目录；macOS 默认读取工作区同级 Android 工具链
python3 tool/native-audio/build.py x86_64
python3 tool/native-audio/build.py arm64-v8a
python3 tool/native-audio/build.py armeabi-v7a
# 或顺序构建三个 ABI（每一步最多 2 个并行编译任务）
python3 tool/native-audio/build.py all
```

可通过 `ANDROID_SDK_ROOT`、`NDK_ROOT`、`CMAKE` 指定工具位置；`BLISTEN_WAF_PYTHON` 指定旧 Waf 的 Python 3.9–3.11。Linux CI 可使用独立 Python 3.11 路径运行 Waf，构建入口使用 Python 3.12+。

第一次运行下载固定源码并核对 SHA256。再次运行使用已校验归档和现有构建目录。修改补丁或源码锁后应使用新的干净 `build/native-audio` 目录，不要在正在编译时改配方。源码归档应保留用于离线重建；本配方不保证不同宿主或工具版本产生逐字节相同的二进制。

输出：`build/native-audio/jniLibs/<ABI>/libmpv.so`、`libmediakitandroidhelper.so`、`manifest.json`。两份 so 使用 16 KiB ELF 页面链接参数。最终 APK 仍需检查 ZIP 对齐、ABI、签名，以及模拟器中的生产入口播放和后台行为。

## 对应源码与替换库

发行时必须把 `package-sources.py` 生成的源码材料归档与 APK 放在同一 Release，不能只链接上游主页。归档包括原始完整源码、子模块、修改补丁、构建配方、实际配置与版本证据、许可证和通知；主应用的同版本源码也应可获得。

使用者可以修改源码、重新生成同名 so，放回项目引用的 `build/native-audio/jniLibs/<ABI>/`，再从同版本 Blisten 源码重新构建并以自己的 Android 证书签名。应用没有签名白名单或限制替换 LGPL 库的检查。自己的证书通常不能覆盖官方证书已安装的包，可先备份需要的数据，再安装自签版本。正式签名私钥不属于重建所需材料，不能分发。若再分发修改版，须将源码改动保存为 `patches/<组件>/` 下的补丁，并重新构建、重新生成对应源码材料；仅改 build 中临时源码而继续分发原归档，不能代表修改后的源码。

FFmpeg 与 Mbed TLS 组合采用 LGPL 3，mpv 的 LGPL 2.1-or-later 允许后续版本；有关权利、源代码、修改与重新链接等条款以随包许可证全文为准。不得禁止用户为调试其对 LGPL 库的修改而进行逆向工程。完整源码中的第三方文件版权和特别通知必须保留。

该版本解决已识别的旧 Mbed TLS、libxml2 与 FFmpeg 分支问题。保留的 mpv 版本仍须单独记录已知公告的可达性分析，不代表整个依赖树没有任何漏洞。
