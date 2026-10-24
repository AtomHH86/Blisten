# Blisten 共用工程：PWA / iOS 第一阶段

沿用已确认的品牌、四频道、手动收藏、独立最近收听及冷启动静默规则。一个 Git 仓库共享 lib/，android/ios/web 是平台宿主，输出分别是 APK、iOS App/Archive、PWA 静态站点文件。

## 本阶段成功标准

1. Android 1.2.1 更新修复先独立验证发布，保留不可变标签；跨平台改动另起分支，不混入该 APK。
2. web/ 与 ios/ 宿主加入现有仓库。Web 能 release 编译，真实浏览器冷启动及导航可用；已有本地播放 fixture 验证播放/暂停/seek/进度保存/静默恢复。原 Android 分析及测试继续通过。
3. Web 明确匿名模式、暂不支持音频离线下载；不调用 Android 通道、不保存登录 Cookie、不展示 APK 更新对话框。当前服务端未指定，先直接测真实来源的跨域能力，失败如实记录，不关闭浏览器安全机制。
4. iOS 最低 15.0，沿用 com.bting.audio 身份与品牌；Keychain、安全外链、音频会话/中断和后台音频声明接入。使用指定 Xcode26.2 的 GitHub macOS CI 编译无签名模拟器/设备 App。未完成真机、签名、TestFlight 前不声称 iOS 可正式安装。
5. 原生 iOS HTTPS 音频必须验证证书；尚未得到可测试信任链前关闭真实音源打开，明确提示。不允许以关闭 TLS 校验来通过样机。
6. 工具脚本、平台支持边界和测试证据入库；新平台不自动发布到 Android 最新版本渠道。

## 实施块

- 缓存：保留 native 实现，抽出共用模型，以条件 export 提供 Web 不支持离线下载的实现；UI 提供清楚状态。
- 平台服务：Web 安全外链、匿名凭据、Android 通知/设备设置/保存图片能力边界；iOS Keychain、外链和音频会话。
- 播放器：条件导入 native TLS 配置，Web 编译时不引用 NativePlayer 的 native-only API；保留播放规则。
- 宿主及验证：生成 web/ios 工程与现有图标，Web 构建/本地测试脚本，iOS CI。首阶段不缓存流媒体或登录响应，网站壳离线能力单独说明。

## 不在本阶段作出的承诺

真实 B站浏览器链路、iPhone Safari 长时后台/锁屏、iOS 证书链、正式签名、TestFlight 和 Store 审核都需要独立通过。当前无服务器登录配置，不部署公网转发、不上传用户账号。网站/原生各设备的本地收藏不会自动同步。
