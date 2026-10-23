# B听独立身份改造验收 — 2026-10-23

## 已完成范围

在 Blisten 仓库中将应用名统一为 B听、口号改为“闭上眼听 B 站”，Android 身份为 `com.bting.audio` / `com.bting.audio.debug`，Dart 包为 `blisten`，独立源码版本 `1.0.0+1`。保持原播放规则、数据键和原生 MethodChannel，使用新包名独立数据空间，不执行旧数据迁移。

README 和关于页明确基于[阿B听书](https://github.com/fengqiao57/abts)修改，保留原始 MIT 许可与版权。上游更新源已关闭，未配置的本项目链接不可点击；友盟依赖与原生/Dart 初始化均移除。

统一收藏、三模式与混合内容文案时，发现缓存明细删除最后一项会读取空列表的问题；新增单条/全部删除用例，先复现 `StateError: No element`，再固定弹窗打开时的单位，空态不再异常。未改播放或删除的业务含义。

## 本轮验证

完整命令：`tool/test-android.sh all`

日志：`build/desktop-tests/20261023-231548-50106/run.log`；退出码 **0**。

- `flutter analyze`：无问题。
- 单元/组件：**63 项通过，1 项可选截图跳过**。
- Python APK 打包脚本检查：**10 项通过**。
- Android 15 / API 35 / x86_64 专用模拟器：**5 个原生功能场景通过**，涵盖独立倍速、媒体控制、三模式续播、离线缓存和搜索/导入界面。
- 跨进程恢复：保存 PID **3383**，验证 PID **3542**，两阶段均通过。
- 正式打包门禁：缺少 `key.properties` 时退出 1，未进行正式构建。

新增的三项身份测试先观察旧实现失败，再验证未配置更新源时不创建网络客户端、关于页真实上游链接、未发布入口禁用。全量检查发现的一处 Dart 字符串格式和四处旧 UI 文案定位已修正，未降低业务断言。

机器可读摘要：[身份验收证据](evidence/2026-10-23-bting-identity.json)。原始日志及调试构建产物仅保存在被忽略的 `build/` 中。

## 普通启动与并存检查

另以 `lib/main.dart` 构建普通 x86_64 Flutter 调试包并安装到专用模拟器，验证 applicationId 为 `com.bting.audio.debug`、版本 `1.0.0+1`、最低 API 24、debuggable=true。启动 `com.bting.audio.MainActivity` 成功，UI 层级和实际截图均确认“收藏 / 发现 / 我的”已显示。

新旧应用同时安装：旧测试包 appId=10210，新包 appId=10209，数据目录分别为 `/data/user/0/dev.pages.abts.debug` 与 `/data/user/0/com.bting.audio.debug`。旧包的版本、安装/更新时间、数据目录与 inode 在测试前后保持一致；未读取或迁移其用户内容。

普通 APK 的 dex 中包含新 MainActivity，未发现 `com.umeng` 类；依赖与原生初始化移除结果已在实际构建验证。调试包仅含 x86_64 Flutter 引擎，其他插件 ABI 的附带库不意味着可作为 universal 正式包发布。

普通首页截图（仍使用旧主题，非生图设计稿）：

![B听独立身份首页](../screenshots/bting-identity-home.png)

## 视觉状态与边界

使用内置 imagegen 生成三个独立方向，原图和完整 prompts 已保存在 [设计提案](../design/bting-v1/README.md)。它们是设计概念板，不是已实现页面的截图。用户尚未选定，正式图标、启动图和主题配色暂不替换。

本轮未重复真实 B 站联网冒烟，未编译 Windows，未生成正式签名证书或四种发布 APK，未创建远程仓库或运行 GitHub Actions。模拟器固定音频测试不构成主观音质、所有设备兼容性或线上资源持续可用性证明。
