# B听（Blisten）

**闭上眼听 B 站。**

B听（Blisten）基于开源项目 [阿B听书（fengqiao57/abts）](https://github.com/fengqiao57/abts) 修改而来，在原有听书功能基础上，增加听歌、听现场和听故事（儿童）频道、B 站链接/BV 号导入，以及按模式独立的倍速与续播规则。

感谢原项目作者及贡献者。本项目保留原始 MIT 许可证和版权声明，是独立维护的衍生版本。

本项目使用独立仓库 [AtomHH86/Blisten](https://github.com/AtomHH86/Blisten)。安装包与更新说明见 [GitHub Releases](https://github.com/AtomHH86/Blisten/releases)，问题反馈请提交 [Issue](https://github.com/AtomHH86/Blisten/issues)。后续开发以本目录为准，迁移来源见 [项目来源](docs/project-origin.md)。

## 功能

| 模式 | 搜索 | 倍速 | 重新选择资源时 |
| --- | --- | --- | --- |
| 听书 | 沿用有声小说分类、筛选和补搜 | 独立记忆，兼容旧设置 | 恢复分 P 与进度 |
| 听歌 | 按歌名、歌手搜索，不套用听书筛选 | 初始 1.0 倍，独立记忆 | 第一 P 从头开始 |
| 听现场 | 按歌手、场次等搜索 | 初始 1.0 倍，独立记忆 | 恢复分 P 与进度 |
| 听故事（儿童） | 儿歌、动画片、故事快捷搜索，不过滤短音频 | 初始 1.0 倍，独立记忆 | 恢复分 P 与进度 |

- 发现页按“听书 / 听歌 / 听现场 / 听故事”分为四大频道，每个频道有独立热门和分类；切回频道会恢复分类与滚动位置。
- 收藏页用一行切换“收藏 / 在听 / 缓存 / 关注”。收藏按四频道分组，数量多的频道优先；支持移动频道，保留进度和缓存。
- 所有频道均须用户手动收藏；播放、连播和缓存不会自动收藏。“在听”显示实际听过的内容，移出收藏后仍可继续播放和保留进度。
- 收藏、发现、我的三个主页面常驻迷你播放器；重启只显示上次收听内容，不自动联网播放。封面进入播放页，播放按钮才开始收听；播放时封面缓慢旋转。
- 搜索提供“听书 / 听歌 / 听现场 / 听故事 / UP 主”五个并列入口；UP 搜索支持分页，进入主页后可切换收听模式。
- 支持粘贴 BV 号、视频链接、分享文本和 `b23.tv` 短链接，选择频道后明确点击“添加到收藏”；显式分 P 链接可打开对应章节。
- 保留分 P 连播、暂停/恢复、倍速、睡眠定时、后台播放、锁屏媒体控制、收藏和离线缓存。
- 缺少模式字段的历史收藏、缓存和进度默认按听书读取；已有模式保持不变。暂停后继续播放与主动重新选择歌曲是不同操作。
- 儿童内容仅收听声音，动画不显示视频；搜索结果来自 B 站，不代表已经过年龄审核。听故事统一断点续播。
- 从 1.1 起，进入首页后后台检查更新，成功检查间隔 24 小时；无更新或失败不弹窗。也可随时进入“我的 → 检查更新”；下载由浏览器完成，安装需 Android 确认。旧版 1.0 需手动检查才能发现 1.1。
- 音频来自 B 站视频；不提供独立歌曲库。不含跨视频歌单、随机/循环播放或整场演唱会自动分曲。

以下为 B听 1.0 在 Android 模拟器中的历史实测画面，使用固定测试数据；不代表线上资源可用性。更多深浅主题、大字和启动截图见[视觉与交互验收记录](docs/testing/2026-10-24-bting-design.md)。

<img src="docs/screenshots/bting-v1/light-empty-collection.png" width="220" alt="B听浅色收藏空态" /> <img src="docs/screenshots/bting-v1/dark-player.png" width="220" alt="B听深色播放器" /> <img src="docs/screenshots/bting-v1/light-import.png" width="220" alt="B听三模式资源导入" />

## 当前应用身份

- 工程/仓库：Blisten；应用显示名：B听；口号：闭上眼听 B 站。
- 正式包：`com.bting.audio`；调试包：`com.bting.audio.debug`（B听·测试）。
- Dart 包：`blisten`；独立版本：`1.2.0+3`；继续使用 B听正式签名，兼容覆盖升级。
- 新包名使用独立数据空间，可与阿B听书并存；本版不自动迁移阿B听书的收藏、进度、缓存或登录状态；B听 1.0 可直接覆盖升级并保留本地数据。
- 底部导航：收藏 / 发现 / 我的；收听入口：听书 / 听歌 / 听现场 / 听故事。
- 原作者统计 SDK 已移除；仓库、问题反馈和自动/手动检查更新均指向 Blisten，独立官网暂未设置。上游链接仅用于来源致谢，不检查上游 Release。
- 已落实 B「闭眼听友」正式图标、启动、深浅主题及相关交互。[视觉与交互规范 v1.3](docs/design/bting-design-system-v1.md) 是后续开发基线；母版和提示词见 [品牌资产](docs/design/bting-v1/production/README.md)，验证范围见[实施记录](docs/testing/2026-10-24-bting-design.md)。

本应用直接请求 B 站接口，音频、封面等请求也会访问对应资源服务。登录信息、收藏、播放进度和用户选择的离线音频保存在本机；卸载或清除应用数据会影响这些本地资料。移除统计不表示播放功能无需网络。自动与手动更新检查请求 GitHub 本项目的最新 Release，不携带 B 站 Cookie、收藏或收听记录。

## 版本保护

本项目已使用独立 Git 仓库。修复前固定检查点为 `baseline/pre-quality-fixes-2026-10-24`，包含审查材料和最新 UP 主搜索调整；正式修复在独立分支分批提交。[版本与回退指南](docs/development/version-control.md)提供恢复步骤和本机离线备份位置。Git 检查点不是 APK 发布版本，也不代表已修复审查发现的问题。

## 开发与测试

工具版本：Flutter **3.38.10**、Dart **3.10.9**；Android 构建使用 JDK 17。最低系统为 **Android 7.0 / API 24**。保留 Windows 源码，当前验收以 Android 为主。

这台电脑已配置共享工具链。首次 Android 构建需要先[编译并准备原生音频库](CONTRIBUTING.md#android-原生音频与回归)，之后进入 `Blisten/` 执行：

```bash
tool/test-android.sh unit          # 静态分析、单元/组件、打包元数据测试
tool/test-android.sh               # 上述检查 + Android 模拟器 + 跨进程恢复
tool/test-android.sh online        # 可选的真实 B 站联网搜索与播放
tool/android-emulator.sh stop      # 测试结束后关闭模拟器
```

全项目质量检查与后续安排见 [2026-10-24 审查报告](docs/reviews/2026-10-24/README.md)和[分阶段改进方案](docs/superpowers/plans/2026-10-24-quality-improvement.md)。审查基线的问题保留原始证据；后续搜索分类、UP 分页与模式选择的改动见[搜索调整验收](docs/testing/2026-10-24-search-categories.md)，质量修复结果见[修复验收](docs/testing/2026-10-24-quality-repairs.md)，1.1 的历史验证见[记录](docs/testing/2026-10-24-v1.1-release.md)，1.2 的频道、收藏与迷你播放器验证见[本版验收记录](docs/testing/2026-10-24-v1.2-release.md)。

完整操作和测试边界见 [电脑 Android 测试教程](docs/testing/android-desktop-guide.md)。测试仅使用专用模拟器，会重置其中的测试应用数据；无需连接手机。日志保存在 `build/desktop-tests/`。

在其他开发机上，先配置对应平台的 Flutter 和 Android 工具链；快速检查无需模拟器：

```bash
flutter pub get
flutter analyze --no-pub
flutter test test --no-pub
python3 -B -m unittest discover -s tool/tests -p 'test_*.py' -v
```

GitHub Actions 使用固定 Flutter 版本执行同样的快速检查。实际运行结果见 [GitHub Actions](https://github.com/AtomHH86/Blisten/actions/workflows/ci.yml)。贡献和环境说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 四种安装包

从 [GitHub Releases](https://github.com/AtomHH86/Blisten/releases) 下载正式版本。多数现代手机选择 **arm64-v8a**；需要 Android 7.0 及以上。1.2 的实际验收和发布状态见[本版验收记录](docs/testing/2026-10-24-v1.2-release.md)，1.0 的历史结果保留在[原记录](docs/testing/2026-10-24-apk-release.md)。ARM 真机和 16KiB 系统尚未实测。

下表暂保留已发布的 1.1 安装包；1.2 打包验收后更新文件名和实测体积。

| 安装包 | 实际体积（MB，十进制） | 适用设备 |
| --- | ---: | --- |
| `Blisten-v1.1.0-arm64-v8a.apk` | 27.99 | 大多数现代安卓手机、ARM64 Android 模拟器 |
| `Blisten-v1.1.0-armeabi-v7a.apk` | 24.85 | 支持 32 位 ARM 应用且满足最低系统版本的设备 |
| `Blisten-v1.1.0-x86_64.apk` | 30.27 | Intel / AMD 电脑上的 x86_64 Android 模拟器及对应设备 |
| `Blisten-v1.1.0-universal.apk` | 77.05 | 包含上述三种 ABI，体积较大；不含 32 位 x86 或 RISC-V |

先构建并准备三个 ABI 的原生库，再配置自己的 `android/key.properties` 和签名证书后运行：

```bash
python3 tool/native-audio/build.py all
python3 tool/prepare-native-audio.py all
tool/build-android-apks.sh --help
tool/build-android-apks.sh
```

脚本要求正式签名，核验每个包的 ABI、包名、版本、证书和文件哈希，并输出 `manifest.json` 与 `SHA256SUMS`。未配置签名时立即退出。四个包使用相同 versionCode；覆盖升级还要求包名、签名一致且版本号不降低。签名文件及 APK 不入 Git。

发布前需确定正式版本并同步更新 `pubspec.yaml`、`AppMeta.version` 和构建号。不要把直接 Gradle 构建时回退到 debug 签名的 release 包当成正式发布包。

## 目录

```text
lib/                 应用、B 站接口、存储、播放器和页面
android/             Android 原生通道与构建配置
windows/             保留的 Windows 平台源码
assets/              应用图标等资源
test/                单元与组件测试
integration_test/    Android 原生、恢复及联网测试
test_driver/         集成测试运行入口
tool/                模拟器、测试及四 ABI 打包脚本
docs/                操作教程、验收记录、项目来源和计划
.github/             CI、Issue 与 PR 模板
```

## 参与与来源

- [贡献指南](CONTRIBUTING.md) · [支持说明](SUPPORT.md) · [安全反馈](SECURITY.md)
- [变更记录](CHANGELOG.md) · [开发约定](AGENTS.md) · [项目来源](docs/project-origin.md)
- 上游项目：[阿B听书（fengqiao57/abts）](https://github.com/fengqiao57/abts)
- 许可证：[MIT](LICENSE)，保留 `BiliTingShu Contributors` 原始版权声明。

本项目与哔哩哔哩无官方关联。音频、封面和文字的权利属于原权利人；离线功能将用户选择的音频缓存到设备，本仓库不附带或分发这些媒体文件。请遵守平台规则和适用的内容授权。
