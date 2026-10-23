# Blisten 开发约定

## 项目边界

- 本目录是 Blisten 的独立 Git 仓库；后续源码、测试、文档和打包改动均在这里完成。
- 同级 `abts/` 是迁移前保留的仓库，不作为后续开发目录，不从中读取运行所需源码。
- `upstream` 仅用于原项目来源和后续对照；未获发布授权时不创建远程仓库、不推送、不发布 Release。
- 保留 `LICENSE` 中的原始 MIT 版权，来源信息见 `docs/project-origin.md`。

## 修改原则

- 编码前检查现有实现、配置和已确认上下文；可验证事实不得猜测。
- 最小修改，保留原注释和文件风格；不要顺手重构无关模块。
- Android 包名、数据键、原生通道、签名、版本号是兼容接口，不能仅为名称统一而替换。
- 听书、歌曲、演唱会均使用 B 站来源；三种倍速和续播规则保持独立。
- 当前身份：应用 B听、Dart 包 blisten、Android com.bting.audio（调试 .debug）；内部 abts_* 数据键和 abts/* 通道为保留接口。
- 用户已选 B「闭眼听友」并认可整体 UI 方向。视觉与交互修改前阅读 docs/design/bting-design-system-v1.md；概念图见 docs/design/bting-v1/。规范已建立，正式视觉实施状态以实际代码和验收记录为准。
- 新页面/功能优先复用规范中的颜色、组件、文案和状态模式；按 docs/design/new-feature-design-template.md 补必要流程。普通可逆细节自行按规范落实，不反复询问用户；品牌、导航、播放/删除、数据或权限边界变化须说明影响。
- 新艺术资产遵守用户要求使用生图模型，保留提示词和源图；实际控件、布局和文字仍由代码实现。界面改动核查深浅主题、大字、小屏及相关加载/空态/错误态，不能将概念图当实测证据。
- 修复先建立可复现检查，按风险验证；文案和路径机械修改不强制新增测试。

## 本机测试

```bash
tool/test-android.sh unit          # 分析、单元/组件、打包元数据检查
tool/test-android.sh integration   # 专用模拟器，含跨进程恢复
tool/test-android.sh online        # 真实 B 站联网冒烟，独立于确定性回归
```

默认 `tool/test-android.sh` 同时运行 unit 和 integration。工具链由 `tool/android-env.sh` 从仓库父目录加载，SDK/Flutter/AVD 不入库。脚本只操作专用模拟器，禁止改为自动选择连接的手机。测试会重置模拟器内测试应用的数据。

- 运行脚本期间不要修改正在执行的脚本文件。
- 集成测试使用 `flutter drive --keep-app-running`，不要用会卸载应用的两次 `flutter test` 替代进程恢复检查。
- 日志位于 `build/desktop-tests/`，提交前脱敏并仅保留必要证据摘要。
- 原始文件可能使用 CRLF；保留既有换行，使用 `git -c core.whitespace=cr-at-eol diff --check` 检查。

## 打包

使用 `tool/build-android-apks.sh`，要求正式签名并检查四种 ABI、包名、版本和证书。不要把直接 Gradle 构建得到的 debug 签名 release 当成正式包。证书、`key.properties`、账号 Cookie、构建缓存及 APK 不入库。正式版本、签名和发布行为须以用户当前授权为准。
