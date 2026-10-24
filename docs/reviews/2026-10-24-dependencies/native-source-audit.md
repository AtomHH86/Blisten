# 原生音频库来源、资产与许可证证据

审计日期：2026-10-24。只读取既有 JAR 和公开的 GitHub 元数据、许可证与构建文本；没有执行工具链或原生构建，没有升级依赖、替换二进制或重新下载 JAR。未上传私有源码、凭据、日志或本机路径。

## 发布资产的字节一致性

锁定的 Pub 包 `media_kit_libs_android_audio 1.3.8` 指向 [v1.1.8 发布](https://github.com/media-kit/libmpv-android-audio-build/releases/tag/v1.1.8)。查询时发布/标签对应构建仓库提交 **`87744be8b337c50ed54961249b7a97c5e8cc37c9`**，发布时间为 `2025-08-02T14:17:29Z`。

四个既有本地 JAR 均匹配该 Pub 包固定的 MD5，以及 GitHub 发布资产的 SHA256 和大小。这证明本地文件与所查询的上游资产字节一致，**不证明它们已从源码可复现构建，也不证明最终 APK 的成员组成**。

| 本地 / 发布资产 | SHA256 |
|---|---|
| default-arm64-v8a.jar | 0481a64b5e246774da22573d7a4e67f9fb3d89a68630864d8819d3ff3a08bb09 |
| default-armeabi-v7a.jar | 1bba852f5b7f0098c54ab8c3a945866d2b730b9e146b472a6ffaa80fc0dceae9 |
| default-x86.jar | 824deeee316dfa3085832c6308e2953425bd428ba7eeeefd59bb51101b7ce8b7 |
| default-x86_64.jar | ddffa0465e2dbb42d52937dae08516dbe07c534d489e9ea995f36a02d31a7106 |

证据见[发布、标签和树元数据](native-upstream-metadata.json)与[本地哈希及逐项比较](native-asset-identity.json)。

## 固定的构建配方与组件版本

[native-upstream-recipes.json](native-upstream-recipes.json) 保留从精确构建提交取得的相关配方、补丁、许可证文本及 SHA256。[depinfo.sh](https://github.com/media-kit/libmpv-android-audio-build/blob/87744be8b337c50ed54961249b7a97c5e8cc37c9/buildscripts/include/depinfo.sh) 选择组件标签，`download-deps.sh` 按标签克隆；[标签提交证据](native-component-tag-commits.json)通过官方仓库 API 解析了附注标签。

| 组件 | 配方选定的版本 / 标签 | 查询时官方标签对应提交 |
|---|---|---|
| mpv | 0.35.1 / v0.35.1 | 140ec21c89d671d392877a7f3b91d67e7d7b9239 |
| FFmpeg | 6.0 / n6.0 | ea3d24bbe3c58b171e55fe2151fc7ffaca3ab3d2 |
| Mbed TLS | 3.6.1 / v3.6.1 | 71c569d44bf3a8bd53d874c81ee8ac644dd6e9e3 |
| libxml2 | 2.10.3 / v2.10.3 | f507d167f1755b7eaea09fb1a44d29aab828b6d1 |
| media-kit-android-helper | main，未固定提交 | 未确定发布时使用的提交 |

配方还指定 NDK `27.1.12297006`、build-tools `35.0.0`、原生 Android API `21` 和链接器 `max-page-size=16384`。保存的三个 mpv 补丁分别涉及 AudioTrack 线程、Java VM 集成和移除 libass；一个 FFmpeg 补丁涉及 DASH URL 转义。这些修改说明仅列基础标签不足以描述源码，也不能将它们当成已回补安全公告的证据。

`bundle.sh` 执行下载、打补丁、构建，收集调试符号并 strip libmpv；随后构建克隆自 `main` 的 helper，把各 ABI 的 libmpv 复制到其输出，再把 `.so` 打成 JAR。配方来源可追溯；helper 的历史提交、构建环境/工具解析结果及可复现性仍待补充。

## 从本地二进制直接观察到的内容

四个 JAR 均包含 `libmpv.so` 与 `libmediakitandroidhelper.so`。四个 libmpv 均含 `mpv 0.35.1-dirty`、`FFmpeg n6.0` 和 `Lavc/Lavf 60.3.100` 版本文本。内嵌 FFmpeg 配置字符串含 `disable-gpl`、`disable-nonfree`、`enable-version3` 和静态链接选项；libavcodec/libavformat/libavutil 的内嵌许可证字符串为 LGPL v3 或更新版本。

这些内容与固定配方相符，但不能证明每个目标文件的修订，也不能排除其他链接代码。本次定向提取没有发现明确的 Mbed TLS/libxml2 版本字符串，它们的精确二进制修订仍只有配方证据。成员哈希与选定字符串保存在 [native-binary-strings.json](native-binary-strings.json)，这是字节观察，不是重新构建或运行验证。

## 许可证来源与适用边界

构建仓库的 LICENSE 将 default/full 构建封装层标为 MIT；这不能取代组件通知。[native-component-licenses.json](native-component-licenses.json) 保留以下源码层面的依据：

| 组件 | 官方声明与本次配置 |
|---|---|
| mpv 0.35.1 | [Copyright](https://github.com/mpv-player/mpv/blob/v0.35.1/Copyright) 提供 LGPL v2.1 或更新版本构建选项；配方启用 `enable-lgpl` 和共享 libmpv |
| FFmpeg n6.0 | [LICENSE.md](https://github.com/FFmpeg/FFmpeg/blob/n6.0/LICENSE.md) 说明版本 3 配置的影响；本次 `disable-gpl` / `enable-version3` 及内嵌字符串支持 FFmpeg 为 LGPL v3 或更新版本的配置 |
| Mbed TLS 3.6.1 | [LICENSE](https://github.com/Mbed-TLS/mbedtls/blob/v3.6.1/LICENSE) 声明 Apache-2.0 或 GPL-2.0-or-later 选择；不据此直接判定应用全部分发义务 |
| libxml2 2.10.3 | [Copyright](https://github.com/GNOME/libxml2/blob/v2.10.3/Copyright) 为 MIT 风格条款，并注明特定文件各自的通知 |
| helper 当前 main | 当前 LICENSE 为 MIT；因配方克隆移动的 main，不能证明发布资产当时的精确源码与许可证快照 |

这里没有认定 Blisten 整体必须采用某一种许可证。最终分发的通知、源码提供材料和组件例外，需要对照实际打包组合核验。

## 尚未完成的来源和分发检查

查询到的上游发布资产为四个 default JAR 和 `debug-symbols-default.zip`；发布界面另提供 GitHub 自动源码归档。未见单独命名的 SBOM、license、notice 或 attestation 资产；固定仓库树/配方中未识别到 SBOM 生成步骤。四个实际本地 JAR 内没有 LICENSE/COPYING/NOTICE 条目。调试符号 ZIP 没有下载或检查，因此不能推断上游所有位置都没有这些材料。

后续仍需补齐应用分发的 notices 和对应源码材料，确定 helper 历史提交，核对实际 release APK 成员与哈希，并完成已知安全公告的处置。固定配方和资产哈希缩小了来源不确定性，但不是可复现构建证明或许可证全面放行。

[原生安全审计](native-security-summary.md)已经补充精确提交查询、官方公告、版本范围比较和源码条件；mpv/FFmpeg/Mbed TLS 的官方公告还揭示了 OSV 提交查询未返回的结果。因此安全检查仍未通过，本轮没有升级或修复这些原生组件。
