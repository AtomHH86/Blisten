# 项目来源与迁移边界

Blisten 从 [fengqiao57/abts](https://github.com/fengqiao57/abts) 派生，保留其 Git 提交历史及原始 [MIT 许可证](../LICENSE)。这不是上游作者发布的版本，也不代表与哔哩哔哩存在官方关联。

本地迁移基线为 `d9f7c5b`，包含此前完成的：

- 听书、歌曲和演唱会模式，分别搜索与记忆倍速/续播规则。
- B 站链接、分享文本、短链接和 BV 号导入。
- 隔离的 Android 调试包与真机测试记录。
- 电脑 Android 模拟器回归、跨进程恢复、真实 B 站联网冒烟及四 ABI 打包脚本。
- 下载过程中新增任务时保留正在执行请求的分 P 信息（page / part / order）的缓存队列修复。

## 独立性

迁移采用 `git clone --no-local --no-hardlinks --no-tags --single-branch`，新仓库不依赖旧仓库的 Git 对象或源码文件。默认分支为 `main`。原仓库配置为 `upstream`，本机已禁用对它的推送；没有配置 `origin`，也尚未创建 Blisten 的 GitHub 远程仓库。

新目录是 `/path/to/workspace/Blisten`。现有 `.flutter-sdk` 与 `.android-toolchain` 位于其父目录并被复用，这是开发工具依赖，不是对旧 `abts/` 源码的依赖。更换电脑时按 [贡献指南](../CONTRIBUTING.md) 配置 Flutter 和 Android 环境。

## 当前应用身份

用户于 2026-10-23 确认独立应用方案：面向用户称为“B听”，口号“闭上眼听 B 站”，工程/仓库仍叫 Blisten。Android 包名为 `com.bting.audio`，调试包为 `com.bting.audio.debug`，Dart 包名为 `blisten`，独立源码版本为 `1.0.0+1`。

新包名使用独立数据空间，不自动迁移旧应用收藏、进度、缓存或登录。内部持久化键和原生通信通道仍可保留原命名，它们不代表继续共享旧应用数据。

原作者统计 SDK 已移除，上游 Release 更新源已关闭；上游链接仅用于来源和许可致谢。B听专用长期签名证书已于 2026-10-24 创建并完成本机恢复签名验证；GitHub 目标和应用更新地址已配置为 `AtomHH86/Blisten`，远程仓库待最终验收后创建，APK 状态见[当前验收记录](testing/2026-10-24-apk-release.md)。

视觉部分已使用生图模型生成三个方向，用户选择 B「闭眼听友」。正式图标、深浅主题及本版交互已落地，后续遵循[视觉与交互规范 v1.1](design/bting-design-system-v1.md)。

## 历史材料

`docs/testing/2026-10-23-android-device.md`、`2026-10-23-android-emulator.md` 及对应历史证据来自迁移前的 abts 扩展。其路径、应用名、提交和日志不可机械替换成 Blisten，以免改变证据含义。

`docs/upstream/abts-readme.md` 和 `abts-index.html` 保留迁移时的原说明与官网源文件作为历史参考；其中相对链接、下载入口与旧品牌不作为 Blisten 的当前入口。它们未部署为新网站。

当前操作说明以根目录 README 和 `docs/testing/android-desktop-guide.md` 为准。Blisten 的迁移后验收单独记录。

## 发布准备

GitHub 的 README、贡献指南、问题模板和自动检查在本仓库内维护。实际远程仓库创建后再配置 origin、仓库地址、反馈入口、更新源和 GitHub 仓库设置，不能使用原作者的 Releases 作为 Blisten 更新源。

正式 APK 只在本轮安装包检查与发布门槛通过后上传；实际发布状态以当前验收记录及 GitHub Release 回读结果为准。
