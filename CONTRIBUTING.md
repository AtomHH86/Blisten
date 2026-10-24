# 参与 Blisten 开发

后续开发以本仓库为准。修改前阅读 [README](README.md) 和相关测试，保持改动集中；缺陷修复优先增加能复现问题的检查。较大的规则或兼容性变化，应先说明使用场景、预期行为和迁移影响。

## 环境与快速检查

当前测试基线使用 Flutter **3.38.10**（内含 Dart 3.10.9）和 Python 3。Android 构建另需 Java 17、Android SDK 及项目要求的 NDK。依赖版本保存在 `pubspec.lock` 中；仅在需要升级依赖时更新锁文件。

已配置这台电脑的共享工具链时，在仓库根目录执行：

```bash
tool/test-android.sh unit
```

其他电脑安装对应工具后，可直接执行与 CI 相同的检查：

```bash
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test test --no-pub --reporter expanded
python3 -B -m unittest discover -s tool/tests -p 'test_*.py' -v
```

GitHub Actions 固定 Flutter 版本与提交，执行上述检查；配置文件是 [.github/workflows/ci.yml](.github/workflows/ci.yml)。工作流不生成正式安装包。首次上传仓库后，仍需确认 Actions 中的实际运行结果。

## Android 原生音频与回归

Android 改为从固定源码构建音频库，本地插件不会下载旧预编译 JAR。首次构建或改变原生来源后，先完成下列准备；配方、工具版本和源码分发要求见[原生构建说明](tool/native-audio/README.md)。

```bash
source tool/android-env.sh
python3 tool/native-audio/build.py x86_64
python3 tool/prepare-native-audio.py x86_64
# 四包发布需要将上述两条命令的 x86_64 改为 all。
```

生成库保存在被忽略的插件目录，`flutter clean` 不删除已经准备好的库。来源、补丁或构建配方改变后，旧库会被校验拒绝，必须重新构建和准备。

涉及播放器、断点、模式规则、缓存或 Android 代码的改动，还应运行专用模拟器测试：

```bash
tool/test-android.sh integration
# 真实 B 站接口变更时按需执行，结果受网络和平台状态影响：
tool/test-android.sh online
```

环境配置、日志位置和测试边界见[电脑测试指南](docs/testing/android-desktop-guide.md)。固定数据测试可重复验证应用逻辑；联网测试单独运行。修改测试运行器时，还应验证异常能产生非零退出码。

## 提交与 Pull Request

界面与交互改动遵循 [B听视觉与交互规范 v1.1](docs/design/bting-design-system-v1.md)。新增功能使用 [设计单](docs/design/new-feature-design-template.md) 说明入口、组件、状态与数据影响；简单改动可在 PR 中简写。优先复用现有主题与组件，新增设计规则同步文档；不因界面改版静默改变播放、收藏或删除规则。

涉及界面时，说明深浅主题、文字缩放、小屏、相关空态/失败态的检查结果，并附必要实测截图。新艺术资产按项目约定使用生图模型，保存提示词和源图；生成的概念稿不作为应用运行验证。

从 `main` 创建 `codex/` 短期分支，一次提交聚焦一个问题。修复前检查点、分阶段提交和回退步骤见[版本与回退指南](docs/development/version-control.md)。提交信息说明改动目的；PR 说明触发场景、最终行为、已执行的验证和未覆盖的范围。不要为无关文件统一格式。

涉及听书、歌曲或演唱会时，检查其他模式是否受影响；涉及持久化时，保留旧数据读取兼容性，或提供明确的迁移方案。包名、发布签名和版本号变更会影响安装与升级，必须在 PR 中说明。

签名证书、`key.properties`、Cookie、Token、个人数据、SDK、依赖缓存和 APK 不应进入源码提交。正式包使用 `tool/build-android-apks.sh` 生成，具体要求见电脑测试指南。

应用自有代码沿用 [MIT 许可证](LICENSE)。捆绑的原生音频组件另有 LGPL、Apache 等许可证；不得以应用 MIT 声明替代第三方通知、对应源码与重新链接材料。贡献应保留上游版权和新增第三方代码所需的声明。
