# B听跨平台 A0 工程预览验收记录

日期：2026-10-25。本文记录共享 Flutter 项目的 Web / PWA 与 iOS 基础适配，不是正式跨平台发行声明。Android 1.2.1 更新修复使用独立发布源码与安装包，不能用本记录替代其 APK 发布验收。

本次代码验收提交：`6d44db9018942cfc173452007b9fde27a8340bd4`。后续仅补充验收文档时，不改变此代码与构建对应关系。

## 当前结论

同一项目已具备 Android、Web、iOS 的平台目录与适配入口；继续共享四频道、收藏、最近收听、界面和播放规则。三种平台分别构建，不共用一个安装文件。

本阶段状态是 **A0 工程预览**：最终代码已通过静态分析、417 项 Flutter 测试、102 项 Python 检查及 5 套 Android 原生专项；Web 生产入口及独立音频探针已重新构建，并完成本机浏览器交互与同源音频实测；最终 iOS 无签名模拟器与设备构建通过，三项 CI 均成功。**浏览器真实 B站接口访问失败，PWA 真实来源跨域未通过验收；iOS 在线播放当前明确关闭。** 未部署公网 PWA，未生成或上传 TestFlight 包，不宣称三端功能对等。

## 已完成的检查

原始日志保存在本机 `build/cross-platform-readiness/`，该目录不入 Git。以下计数来自实际日志终态，不把编译、跳过或占位工作流视作运行通过。

| 检查 | 结果 | 日志与说明 |
| --- | --- | --- |
| 最终 Flutter 全量单元/组件测试 | 417 通过、3 跳过 | `final-unit-accepted.txt`：`+417 ~3: All tests passed!`；跳过项未计为通过 |
| 最终 Python 打包与验证脚本检查 | 102 通过 | `final-unit-accepted.txt`：`Ran 102 tests`、`OK`，总脚本 `Result: 0` |
| Android 原生专项运行回归 | 5 套通过 | `native-regression.txt`：凭据存储、原生 TLS、播放模式、缓存清理与音频焦点全部 `Passed`；`native-source-commit.txt` 对应本次代码 |
| 缓存能力及既有缓存行为定向回归 | 36 通过 | `cache-green.txt`；覆盖 Web 不支持缓存的界面与调用边界，以及原生缓存回归 |
| Chrome 平台服务测试 | 3 通过 | `platform-green.txt`；外链校验、Web 匿名凭据、Web 不访问原生音频焦点通道 |
| iOS 在线播放限制与播放器交互定向回归 | 15 通过 | `ios-limit-green.txt`；验证未配置 iOS 信任链的明确错误，以及现有播放器交互 |
| 预览限制提示交互定向回归 | 13 通过 | `preview-limit-green.txt`；覆盖播放器、详情和最近收听，平台限制不误导用户反复重试 |
| 本机 Web 预览服务器 HTTP 检查 | 8 通过 | `web-server-green.txt`；验证新增 `tool/serve-web.py` 的 HTTP 行为 |
| 频道字体变化回归 | Chrome 1 通过、原生测试环境 1 通过 | `font-change-green-final.txt`、`font-native-green-final.txt`；仅 Web 字体动态加载触发频道文字尺寸刷新 |
| 最终 Flutter 静态分析 | 0 问题 | `final-unit-accepted.txt`：`No issues found!` |
| 最终 Web 共享应用生产构建 | 通过 | `web-complete-final-build.txt`：`Built build/web` |
| 最终 Web 独立音频探针生产构建 | 通过 | `probe-complete-final-build.txt`：`Built build/web-probe`，生成 60 秒测试 WAV |
| Web 输出关键资产检查 | 通过 | `web-output-integrity.json` 记录主站及探针的入口、manifest、JS、字体与品牌图标大小及 SHA-256 |
| 最终 Web CI | 通过 | [CI 40124144824](https://github.com/AtomHH86/Blisten/actions/runs/40124144824) |
| 最终 iOS 无签名模拟器及设备编译 | 通过 | [CI 40124144911](https://github.com/AtomHH86/Blisten/actions/runs/40124144911)；不代表已签名或在 iPhone 运行 |
| 最终分析、单元、Android 调试构建及 lint CI | 通过 | [CI 40124144878](https://github.com/AtomHH86/Blisten/actions/runs/40124144878) |

三个 CI 均对应上方代码提交。最终 iOS CI 产物中的 `Podfile.lock` 与已提交文件逐字节一致，Xcode 为 26.2。脱敏证据与本机日志摘要见 [验收证据](evidence/cross-platform-a0-verification.json)。

早期 `unit-full.txt` 的 409 项 Flutter 通过、3 项跳过与 94 项 Python 通过，仅记录过程阶段；最终全量结果以上表 `final-unit-accepted.txt` 为准，不与定向测试计数相加。原生专项日志的框架计数包含 setup / teardown，本报告按 5 套专项记录，不将该计数当作业务用例数量。构建日志中的 Wasm dry run 仅为工具检查，没有执行 Wasm 浏览器验收。

修复前检查曾复现失败：`cache-red.txt` 记录 4 项失败，`platform-red.txt` 记录 3 项失败，`ios-limit-red.txt` 记录 1 项失败；对应修改后以上定向日志转为通过。红灯日志证明针对性检查能捕获旧行为，不表示当前仍有同样失败。

## 浏览器实际运行

本机 Chromium 浏览器中使用独立音频探针与 60 秒自行合成 WAV，取得以下实际状态：

| 操作 | 实测结果 | 证据 |
| --- | --- | --- |
| 用户点击播放 | `playing: true`，播放位置推进到 1,031 ms | `probe-playing.json` |
| 暂停、跳到 30 秒、调整至 1.5 倍速并保存 | `position_ms: 30000`、`playing: false`、`rate: 1.5`、`lastSaved_ms: 30000` | `probe-controls.json` |
| 媒体范围请求 | HTTP 206；`Content-Range: bytes 44-103/2646044` | `probe-controls.json` |
| 刷新探针 | 保存值仍为 30,000 ms，`opened: false`、`playing: false`，未自动打开或播放音频 | `probe-reload.json` |
| 最终构建探针复验 | 播放后暂停，跳转、1.5 倍速与 30,000 ms 保存值再次正确 | `probe-complete-final-smoke.txt` |

初次使用 Python 标准 `http.server` 时，实际跳转后位置归零，不能算作跳转通过。新增 `tool/serve-web.py`，固定只监听 `127.0.0.1`，补齐媒体 Range 服务并通过 8 项 HTTP 测试；切换到该服务器后，取得上表跳转与保存结果。此服务只用于本机预览，不是公网来源转发。

实际 UI 检查还修复了两处问题：Chrome 动态加载中文字体后，频道文字尺寸没有及时刷新；Flutter 交替使用相对与绝对输出路径，导致增量构建误删资产。前者已用 Chrome 与原生定向测试验证，后者在 `tool/build-web.sh` 中统一绝对输出路径并增加构建后关键资产检查。最终主站与探针重新构建后，字体、图标及品牌图片完整。

最终 390 px 视口截图 `web-complete-mobile.png` 已实际查看，四频道与图标显示正确；`web-my-dark-final.png` 与 `web-theme-persisted.txt` 确认深色界面及设置持久化；`web-cache-snapshot.txt` 确认缓存入口明确提示网页版暂不支持离线音频缓存。这些结果覆盖本机浏览器，不能扩大为 iPhone Safari 或所有设备已通过。代表截图见 [预览截图说明](../screenshots/cross-platform-preview/README.md)。

真实来源检查没有通过：浏览器对 B站 `nav` 与视频搜索接口执行 fetch 均失败，见 `web-source-fetch.json`。其中 `nav` 的网络事件明确记录 HTTP 403 及 CORS `MissingAllowOriginHeader`，见 `web-source-network-events.json`；发现页也显示加载失败，见 `web-discover-attempt.png`。因此目前不能宣称 PWA 能搜索或播放 B站内容，同源 WAV 探针成功不能替代真实来源验收。

## 能力边界

| 项目 | 本阶段行为 | 尚不能据此确认的能力 |
| --- | --- | --- |
| Web 账户 | 匿名使用，不读取、持久化 B站账号 Cookie | 账户登录、大会员权限及跨设备同步 |
| Web 缓存 | 明确提示暂不支持离线音频缓存，避免触发原生文件路径 | 离线音频、离线启动；本阶段关闭 Service Worker |
| Web 音频探针 | 同源 WAV 实际播放、暂停、跳转、倍速、保存及刷新不自动播放已通过 | B站音频可播、正式播放器全链路、Safari、锁屏与长时间后台 |
| Web 来源访问 | 本机浏览器访问 B站接口实际失败；不部署媒体转发 | 真实搜索、导入、封面和媒体的跨域可达性 |
| iOS 宿主 | 已配置系统浏览器、Keychain、音频会话和中断适配代码，最终无签名 CI 编译通过 | 编译不能证明真机音频焦点、安全存储或其他系统行为已通过 |
| iOS 在线音频 | 未配置可信证书链时失败关闭，界面说明预览限制 | 不关闭证书检查换取播放；真实证书链与错误证书拒绝仍待验证 |
| 发布 | Android 独立补丁与 A0 预览分开交付 | 本阶段没有 PWA 公网部署、iOS 签名、TestFlight 或 Store 发布 |

## 待补充的运行结果

以下检查仍需继续或补充最终源码证据；已观察到的失败也保留在表内。

| 检查 | 当前状态 | 完成标准 |
| --- | --- | --- |
| 真实 B站浏览器请求 | 未通过；nav 403 与缺少跨域许可，搜索 fetch 失败 | 完成真实搜索、导入及媒体请求验收，不能将同源探针视作替代 |
| iOS 原生音频与真机 | 待验证 | 先解决可信证书链，再验证播放、锁屏、来电/耳机/蓝牙与安全存储 |
| PWA 实际域名部署 | 待域名及服务器连接信息 | HTTPS、来源请求、主屏幕安装与目标浏览器分别验收 |
| TestFlight | 待 Apple 账号与签名配置 | 归档、上传及真实测试分发均有独立证据 |

## Web 工程预览包

本地交付文件为 `dist/web-preview-6d44db9/Blisten-web-preview-6d44db9.zip`，对应本次代码提交。体积 11,676,689 字节，包含 33 个站点文件及 1 个说明文件；ZIP 完整性检查通过。SHA-256：

```text
b34a8e394ec111336836e5fe10bb32bcd549259938d6d70b1d45c86e1eefa546
```

配套 `manifest.json` 标识为 `engineering_preview_not_public_deployment`，并记录真实来源、登录、缓存、Safari/后台播放及离线启动限制。该压缩包用于工程预览，不是已部署的网站或可正式收听的 PWA 发行包。

## 后续门槛

工程编译完成后，继续按 [跨平台开发说明](../development/cross-platform.md) 验证来源接入与设备行为。真实来源跨域、iOS 证书信任、长时间后台播放任一项未通过时，对应平台保留预览标识，不列为已支持正式收听。

取得剩余运行结果后，仅更新有证据的条目。公网部署、App Store 材料及原生依赖许可证明分别验收，不从 Android 历史记录推定通过。
