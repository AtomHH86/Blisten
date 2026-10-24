# B听：同一项目，分别构建三个平台

共用 `lib/` 中的四频道、收藏、最近收听、播放规则与界面。`android/`、`ios/`、`web/` 负责系统差异；不用维护三套产品代码。Android 的四种 CPU APK 是同一 Android 应用的不同构建，并不是另外四个项目。

| 目标 | 输出 | 当前边界 |
| --- | --- | --- |
| Android | 四种正式签名 APK | 1.2.1 独立修复版本；新平台改动不混入该发布标签 |
| Web / PWA | `build/web/` 静态站点文件 | 开发预览；匿名、无音频缓存；真实来源跨域、长时间后台和主屏幕安装待独立验收 |
| iOS | 模拟器 `.app`、无签名设备 `.app`；将来正式 Archive/IPA | iOS 15 起；先用 CI 编译；真实在线播放暂未开放，无 TestFlight 分发 |

## 本机 Web 预览

```bash
tool/build-web.sh app
python3 tool/serve-web.py --directory build/web --port 8768
```

打开 `http://127.0.0.1:8768`。沿用 B听图标与配色，manifest 提供主屏幕入口基础。当前关闭 Service Worker，不宣称离线启动；这样预览代码不会被旧缓存固定住。浏览器本地存储保留收藏、设置和进度，清除网站数据会删除这些资料，不自动跨设备同步。

Web 只尝试匿名直连接口，不读取或持久化 B站账号 Cookie。浏览器不能沿用原生的自定义 Referer / Cookie，因此 Android 可播不能证明 PWA 可播。没有实现或部署公网媒体转发；站点部署与真实来源接入需在域名/服务器条件明确后处理。

## 独立浏览器音频探针

```bash
tool/build-web.sh probe
python3 tool/serve-web.py --directory build/web-probe --port 8769
```

该入口使用 60 秒自行合成的低音量 WAV，真实调用 media_kit Web 引擎，测试点击播放、暂停、跳到30秒、1.5倍速和保存进度。只使用独立 `blisten_web_probe_position_ms` 键；刷新后展示保存值，不自动打开音源。探针成功仅证明本机引擎与浏览器存储，不证明 B站搜索/媒体、iPhone Safari 或熄屏收听可用。探针不包含在正式 App 入口或正式 APK 中。

## iOS

配置与编译命令见 [iOS 宿主说明](../../ios/README.md)。CI 固定 Flutter 3.38.10 与 Xcode26.2，验证无签名模拟器及设备构建；签名、真实 iPhone、TestFlight 和 Store 仍为独立步骤。

iOS 已有 Keychain、音频会话、中断/耳机事件与系统浏览器适配。当前原生音频库的 iOS 可信证书链尚未验证，在线播放明确失败关闭，不会通过关闭证书检查来打开音源。本地音频测试可独立开展。真实原生依赖及许可证必须在正式发行前单独审核，不能继承 Android 重编原生库的证明。

## 后续验收

1. 真实域名 HTTPS 下验证搜索、导入、封面和音频请求；跨域或来源限制未解决时，Web 仍是预览。
2. 分别验证 Android Chrome、iPhone Safari/主屏幕模式的30分钟播放、锁屏、分P、跳转、地址过期与断网恢复。
3. 补 iOS 证书信任及拒绝错误证书测试，再验证真机锁屏、电话/耳机/蓝牙、缓存与安全存储。
4. Apple 账号与签名就绪后归档，先 TestFlight；正式商店分发另需来源权利、隐私和审核材料。

本阶段结果以 [验收记录](../testing/2026-10-25-cross-platform-foundation.md) 为准；尚未通过的能力不列为已支持。
