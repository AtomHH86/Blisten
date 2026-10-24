# Blisten 的 Android 音频原生库插件

本目录基于 [media_kit_libs_android_audio 1.3.8](https://pub.dev/packages/media_kit_libs_android_audio/versions/1.3.8) 的 Android 包修改，保留原始 MIT [LICENSE](LICENSE)。上游源码项目为 [media-kit/media-kit](https://github.com/media-kit/media-kit)。本地包不发布到 pub.dev。

JNI helper Java 文件、`settings.gradle` 与 AndroidManifest 均保留上游原文；插件包名、类名、`@Keep` 和 AndroidManifest 的 `extractNativeLibs="true"` 继续保留。Java 层通过既有名称加载 `mpv` 和 `mediakitandroidhelper`，既有 JNI 与 media_kit 调用接口不变。主插件仅追加下述可信 CA 通道。

Blisten 保留 `media_kit_libs_audio` 聚合包，只在应用 `dependency_overrides` 中把 Android 子包指向本目录。修改范围：

- 移除 Gradle 下载旧版 JAR 的逻辑，使用 Android 标准 `src/main/jniLibs/<ABI>/` 输入。
- Gradle 插件版本与项目对齐为 8.11.1；最低 Android API 设为自建库使用的 24。
- `preBuild` 验证本次构建所需 ABI 的库集合和 SHA-256、当前源码锁与构建配方指纹，以及随 APK 分发的许可证文本；缺失、存在额外 `.so` 或指纹过期时立即失败。
- 增加 `blisten/native_tls` 引擎通道的 `trustedCaFile` 方法：使用默认 X509TrustManager 的当前信任锚，在后台任务队列中原子导出 PEM 到应用 no-backup 目录。没有可信 CA 或写入失败时返回明确错误，不提供关闭 TLS 校验的回退；不扫描系统证书路径，detach 时清除 handler。导出是调用时的信任锚快照，不等于原生播放器完整实现 Android Network Security Config。
- `.so`、准备清单和复制的许可证文本是本地生成内容，不提交 Git。可复现来源、补丁及原生组件许可证保存在根目录 `tool/native-audio/`。原生库的许可证不因本插件的 MIT 许可证而改变。

## 准备与构建

在 Blisten 仓库根目录设置共享 Android 环境，然后准备专用模拟器所需 x86_64 库：

```bash
source tool/android-env.sh
python3 tool/native-audio/build.py x86_64
python3 tool/prepare-native-audio.py x86_64
flutter build apk --debug --target-platform android-x64
```

构建四类发布 APK 前，改用 `all`：

```bash
python3 tool/native-audio/build.py all
python3 tool/prepare-native-audio.py all
```

构建工具链与源码固定版本以 `tool/native-audio/build.py`、`sources.lock.json` 及同目录说明为准。准备步骤核对每个库的清单摘要、ELF 架构、API 与精确 `.so` 集合，并确认 `sources_lock_sha256` 及 `build_inputs` 对应当前 `build.py`、`sources.lock.json`、`ffmpeg-options.txt` 和全部 `patches/**/*.patch`，再复制到插件目录；先验证全部请求的输入，再替换已有输出。该目录不位于 `build/`，因此 `flutter clean` 后无需重新准备已校验的库。源码或构建配置修改后应重新构建并准备。

Gradle 的 `target-platform` 决定普通 Flutter 构建需要哪些 ABI；正式打包脚本的 `blistenTargetAbis` 参数优先。插件只检查输入，不另行设置 ABI 过滤。未指定目标时要求三个支持的 ABI：arm64-v8a、armeabi-v7a 和 x86_64。

APK 中的 `assets/native-audio/` 包含原生组件许可证、许可证摘要清单及对应 ABI 构建清单；完整源码和重链接材料由 `tool/native-audio/` 构建流程另行准备，不把大体积源码归档塞入 APK。正式发布时须同时交付对应版本的分发材料。

准备脚本的本地 guard 测试：

```bash
python3 -m unittest tool/tests/test_prepare_native_audio.py
```

可信 CA 导出逻辑还可运行 `python3 -m unittest tool/tests/test_native_tls_store.py`。这组 JVM 检查使用真实 JVM 信任锚和 Android API 替身，只验证 PEM 格式、空列表失败、刷新与写入回滚；真实 Android 的信任锚和 TLS 验证须另行通过模拟器或设备集成测试。
