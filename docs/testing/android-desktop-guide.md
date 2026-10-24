# 在电脑上测试 Android 应用

当前配置适用于这台 Intel Mac（macOS 13.7.8）。Flutter、Java、SDK、依赖缓存和模拟器放在仓库父目录的 `.flutter-sdk`、`.android-toolchain`，不依赖临时目录长期存在。无需连接手机或安装 Android Studio。

迁移前实际通过情况见[模拟器验收记录](2026-10-23-android-emulator.md)；该记录保留原项目身份。B听视觉实施见[设计记录](2026-10-24-bting-design.md)，本轮修复与最新实测见[质量修复验收](2026-10-24-quality-repairs.md)，1.2 结果见[本版验收](2026-10-24-v1.2-release.md)，正式发布须满足[发布门槛](release-gates.md)。

## 常用命令

在 `Blisten` 仓库目录执行：

```bash
tool/test-android.sh                 # 默认：分析/组件 + Android构建/lint + 模拟器回归
tool/test-android.sh unit            # 快速静态分析及单元/组件测试
tool/test-android.sh lint            # 调试应用构建与原生 lint，无模拟器
tool/test-android.sh integration     # 仅模拟器回归及跨进程恢复
tool/test-android.sh online          # 可选：真实 B 站联网冒烟测试
```

脚本默认以无窗口模式启动专用模拟器 `abts_api35_x86_64`，图形和原生音频仍启用；只接受模拟器目标，并核对设备身份。若模拟器已经运行，会复用当前进程。旧的 `dev.pages.abts.debug` 不作为测试目标。测试使用 `com.bting.audio.debug`（B听·测试），会清理该模拟器测试包内的数据。不要在此专用测试应用中保存需要长期保留的收藏或登录账号。实体手机不参与这些命令。

结果位于 `build/desktop-tests/<时间>-<进程号>/`：`run.log`、工具版本、设备信息、`exit-code.txt`；集成检查另有 `panel-screenshots/` 与 `screenshots/`，保存深浅主题、200% 文字、导入、播放及主题切换的实测 PNG。返回码为 `0` 才表示所选检查全部通过；失败时脚本停止并保留日志。截图保存成功不等于视觉检查通过，修改布局后仍需打开查看。日志仅供本机排障，联网日志可能含临时网络信息，分享前应脱敏。

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

- 单元/组件：旧数据兼容、四种搜索模式、四频道专属分类、晚返回的分页隔离、重试关键词、BV / 链接 / 短链解析、导入错误、倍速键、续播选择、书架和缓存模式。
- 视觉与交互组件：320dp / 200% 字体、明暗主题、实际按钮文字对比度、触控尺寸、选中语义、空态入口、删除确认、登录和分页重试、键盘下输入可达。
- 模拟器固定数据：真实 Android 音频解码播放、四种独立倍率、媒体会话处理器暂停/继续、长音频分 P 断点、歌曲重新选择回到第一 P、缓存落盘和无网络源时的本地播放、搜索与导入页面操作。
- 1.2 新增：全局手动收藏、四模式各真实播放一分钟、缓存播放不收藏、四视图切换和频道移动、停止/清除后的本地预览、歌曲/听书跨进程静默预览及显式播放规则。
- 既有回归：凭据迁移/会话竞争、持续播放自动保存、加载期间暂停、缓存取消与清理、按 CID 恢复、设置前台刷新、两种定时入口、目录重排选章和面板大字显示。
- 音频焦点：拒绝/延迟/临时和永久丢失用受控通道事件验证；Activity 销毁后的生命周期另用真实系统 noisy 广播及原生回调观察，不模拟 Dart 暂停。
- 播放重试：延迟目录/重连不能覆盖停止或新选择；新选择失败恢复最后成功会话；重试保留分 P / 偏移并刷新过期地址；实际原生媒体失败可见且可重试。
- 跨进程：先用真实播放器产生并保存进度，再结束应用进程；新进程核对四种倍率和进度，听书/演唱会续播，歌曲从头开始。这不等同于写入尚未完成时突然断电的恢复测试。
- 拒绝通知权限：运行器在最后的视觉播放套件前撤销权限并设置拒绝标记，验证应用内导航和播放；退出时恢复测试包通知权限。此项不等于所有 Android 版本的通知栏和锁屏控制都通过。
- 联网冒烟：独立调用真实 B 站听书/听歌/听现场及儿歌/动画/故事搜索、视频详情和音频地址解析，运行原生在线播放；网络、平台限制或资源失效可能导致其独立失败。

固定数据测试的 API 响应和静音 WAV 来自测试内部服务；音频通过本地 HTTPS 传输，测试播放器仅增加对测试证书的信任并保持 TLS 校验开启。播放器、Android 存储和媒体服务均使用真实实现。它证明播放与持久化逻辑，不证明 B 站持续可用，也不证明扬声器的主观音质。媒体控制用例调用真实音频服务处理器，不代表通知栏按钮的投递链路已验收。通知栏直接点击、蓝牙、电话打断、厂商后台省电、长时间播放、Android 7 最低版本和 16 KiB 内存页兼容仍需相应系统或实机测试。

运行器使用 Flutter `integration_test` 配合 `flutter drive --keep-app-running`，测试结束后显式停止进程而保留应用数据。不要直接用两次 `flutter test` 替代重启测试：当前 Flutter 版本会在每次集成测试结束后卸载应用，清除要验证的进度。

测试基础设施的负向入口是 `integration_test/harness_failure.dart`，它故意制造初始化异常、清理异常或初始化超时，供维护运行器时检查非零退出码；不包含在日常回归中。原生初始化单独允许 90 秒，其余钩子限制为 25 秒，并记录初始化阶段耗时。

## 独立专项检查

先加载本机工具链，以下命令只作用于专用模拟器内的 debug 包：

```bash
source tool/android-env.sh
python3 -B tool/verify-local-backup.py
python3 -B tool/verify-audio-focus-lifetime.py --evidence-dir build/lifetime-manual-001
```

备份脚本使用合成数据和本地备份传输，恢复原系统设置并清理测试数据；禁止用于个人设备或账号。寿命脚本已包含在 `all/integration`，单独运行时证据目录须使用新名称，不覆盖既有日志；它核实 Activity 不在、前台 AudioService 在、受保护广播成功且真实原生回调到达后，才认定通过。

GitHub CI 包含快速检查、Android debug 构建和原生 lint；精确源码对应的远程运行结果见各版验收记录和仓库 Actions。性能、ARM64、低版本、完整 TalkBack、签名与升级仍按发布门槛逐项验收。

## 四种正式安装包

项目已发布正式签名 APK，并提供可重复打包脚本。新维护者须先配置自己的 `android/key.properties` 和发布证书，再执行 `tool/build-android-apks.sh`；详细参数以 `--help` 为准。

打包脚本分别构建 ARM64、ARMv7、x86_64 和包含这三种 ABI 的 universal，保留相同版本号，检查实际 ABI、签名、大小及 SHA-256。`apk-metadata.py --release` 同时强制检查 64 位原生库的 ELF 装载段与直接加载时的 ZIP 数据偏移满足 16KiB 条件，失败时整批不发布；32 位库仍报告结构，不因仅 4KiB 对齐误拒绝。静态检查不替代 16KiB 系统运行。不要把之前估计的 26 / 23 / 28 / 73 MB 写成新版本实测结果。签名一致、包名一致且版本号不降低才满足覆盖升级的基本条件；发布时仍需验证实际安装和升级。

B听使用独立包名，源码从 `1.0.0+1` 开始；此后发布应同步 `pubspec.yaml` 与 `lib/core/app_meta.dart` 的版本并递增构建号。安装包名称为 `Blisten-v<版本>-<ABI>.apk`，清单自动采用项目版本。当前维护者已配置 B听专用正式证书；保留证书才能覆盖升级 B听，不能覆盖原作者不同包名和签名的应用。

方法参考：[Flutter 集成测试](https://docs.flutter.dev/testing/integration-tests)、[Android Emulator](https://developer.android.com/studio/run/emulator)、[Flutter Android 发布](https://docs.flutter.dev/deployment/android)。
