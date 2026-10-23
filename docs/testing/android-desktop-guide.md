# 在电脑上测试 Android 应用

当前配置适用于这台 Intel Mac（macOS 13.7.8）。Flutter、Java、SDK、依赖缓存和模拟器放在仓库父目录的 `.flutter-sdk`、`.android-toolchain`，不依赖临时目录长期存在。无需连接手机或安装 Android Studio。

迁移前实际通过情况见[模拟器验收记录](2026-10-23-android-emulator.md)；该记录保留原项目身份。当前项目为 Blisten，迁移后验收另行记录。

## 常用命令

在 `Blisten` 仓库目录执行：

```bash
tool/test-android.sh                 # 默认：检查 + 模拟器回归 + 跨进程恢复
tool/test-android.sh unit            # 快速静态分析及单元/组件测试
tool/test-android.sh integration     # 仅模拟器回归及跨进程恢复
tool/test-android.sh online          # 可选：真实 B 站联网冒烟测试
```

脚本默认以无窗口模式启动专用模拟器 `abts_api35_x86_64`，图形和原生音频仍启用；只接受模拟器目标，并核对设备身份。若模拟器已经运行，会复用当前进程。旧的 `dev.pages.abts.debug` 不作为测试目标。测试使用 `com.bting.audio.debug`（B听·测试），会清理该模拟器测试包内的数据。不要在此专用测试应用中保存需要长期保留的收藏或登录账号。实体手机不参与这些命令。

结果位于 `build/desktop-tests/<时间>-<进程号>/`：`run.log`、工具版本、设备信息、`exit-code.txt`。返回码为 `0` 才表示所选检查全部通过；失败时脚本停止并保留日志。日志仅供本机排障，联网日志可能含临时网络信息，分享前应脱敏。

## 打开、使用与关闭模拟器

```bash
tool/android-emulator.sh status
tool/android-emulator.sh stop        # 测试结束后关闭
# 需要手动体验时，先结束已有无窗口实例，再打开窗口：
tool/android-emulator.sh start
# 替换集成测试入口，保留 debug 包数据：
source tool/android-env.sh
flutter run -d emulator-5554 -t lib/main.dart
```

手动体验结束后，先执行 `tool/android-emulator.sh stop`，再运行测试命令，让自动回归使用本机验证过的无窗口配置。

首次环境配置使用 `tool/setup-android-emulator.sh`，它固定模拟器和系统镜像版本并校验官方校验和。当前 Java、Android 命令行工具、Flutter 已安装；该脚本不是所有操作系统的全新开发环境安装器。迁移电脑时应先配置对应平台的工具链；Apple Silicon 需要 ARM64 主机模拟器及 ARM64 Android 系统镜像。

默认使用 Android Emulator 36.5.11、Android 15 / API 35、x86_64、2560 MiB 内存、2 核、720×1280、6 GB 数据分区。CPU 使用 Hypervisor.Framework 加速，图形使用软件渲染以适配本机。37.2.12 在本机实际播放时出现 CoreAudio 锁等待并崩溃，因此安装脚本固定到已实测的 36.5.11。测试启动前通过 ADB 给专用测试包授予通知权限，避免系统弹窗阻塞自动化。

## 验证内容与边界

- 单元/组件：旧数据兼容、三种搜索模式、晚返回的分页隔离、重试关键词、BV / 链接 / 短链解析、导入错误、倍速键、续播选择、书架和缓存模式。
- 模拟器固定数据：真实 Android 音频解码播放、三种独立倍率、媒体会话处理器暂停/继续、长音频分 P 断点、歌曲重新选择回到第一 P、缓存落盘和无网络源时的本地播放、搜索与导入页面操作。
- 跨进程：先用真实播放器产生并保存进度，再结束应用进程；新进程核对三种倍率和进度，听书/演唱会续播，歌曲从头开始。这不等同于写入尚未完成时突然断电的恢复测试。
- 联网冒烟：独立调用真实 B 站三种搜索、视频详情和音频地址解析，运行原生在线播放；网络、平台限制或资源失效可能导致其独立失败。

固定数据测试的 API 响应和静音 WAV 来自测试内部服务；音频通过本地 HTTPS 传输，测试播放器仅增加对测试证书的信任并保持 TLS 校验开启。播放器、Android 存储和媒体服务均使用真实实现。它证明播放与持久化逻辑，不证明 B 站持续可用，也不证明扬声器的主观音质。媒体控制用例调用真实音频服务处理器，不代表通知栏按钮的投递链路已验收。通知栏直接点击、蓝牙、电话打断、厂商后台省电、长时间播放、Android 7 最低版本和 16 KiB 内存页兼容仍需相应系统或实机测试。

运行器使用 Flutter `integration_test` 配合 `flutter drive --keep-app-running`，测试结束后显式停止进程而保留应用数据。不要直接用两次 `flutter test` 替代重启测试：当前 Flutter 版本会在每次集成测试结束后卸载应用，清除要验证的进度。

测试基础设施的负向入口是 `integration_test/harness_failure.dart`，它故意制造初始化异常、清理异常或初始化超时，供维护运行器时检查非零退出码；不包含在日常回归中。原生初始化单独允许 90 秒，其余钩子限制为 25 秒，并记录初始化阶段耗时。

## 四种正式安装包

本次交付可重复打包脚本，正式 APK 后续生成。先配置 `android/key.properties` 和发布证书，再执行 `tool/build-android-apks.sh`；详细参数以 `--help` 为准。

打包脚本分别构建 ARM64、ARMv7、x86_64 和包含这三种 ABI 的 universal，保留相同版本号，检查实际 ABI、签名、大小及 SHA-256。不要把之前估计的 26 / 23 / 28 / 73 MB 写成新版本实测结果。签名一致、包名一致且版本号不降低才满足覆盖升级的基本条件；发布时仍需验证实际安装和升级。

B听使用独立包名，源码从 `1.0.0+1` 开始；此后发布应同步 `pubspec.yaml` 与 `lib/core/app_meta.dart` 的版本并递增构建号。安装包名称为 `Blisten-v<版本>-<ABI>.apk`，清单自动采用项目版本。正式证书尚未配置，不能覆盖原作者的应用。

方法参考：[Flutter 集成测试](https://docs.flutter.dev/testing/integration-tests)、[Android Emulator](https://developer.android.com/studio/run/emulator)、[Flutter Android 发布](https://docs.flutter.dev/deployment/android)。
