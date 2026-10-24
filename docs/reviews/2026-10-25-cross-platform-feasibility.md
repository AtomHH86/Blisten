# B听：PWA、微信小程序与 iOS 可行性评估

评估日期：2026-10-25。源码基线：已发布的 `v1.2.0`（`bc5413e02b970d793dc50e3c46f1d581d9aa4797`）。按用户要求，在 Android 发布、附件回读和公开更新识别完成后开展本评估。

本轮完成源码、依赖和本机工具链检查，并核对官方平台资料；**没有构建或部署 PWA、小程序、iOS，没有访问用户服务器，也没有申请账号或提交审核**。下文是立项判断和验收方案，不是这些平台已经跑通的证明。

## 1. 建议先做什么

**继续维护 Android；先用现有域名做官网和下载入口，再做小范围 PWA 播放验证。若目标是稳定的 iPhone 熄屏收听，iOS 应作为正式客户端方向；微信小程序暂排最后，先核实类目资格和音源适配。**

| 方向 | 可行性判断 | 主要门槛 | 建议 |
| --- | --- | --- | --- |
| 官网／下载页 | 技术工作量较小，与现有 App 可独立进行 | 域名、HTTPS、服务器位置与适用备案、维护安排 | 最先使用现有服务器的方式 |
| PWA（可添加到主屏幕的网页） | 界面与业务可复用，完整听音体验尚待验证 | B站接口跨域、媒体请求头、长音频后台连续播放、浏览器存储 | 先做播放样机，通过后再迁移完整界面 |
| iOS → TestFlight | 最适合复用现有 Flutter 代码；需要补原生能力 | 合适的 Mac/Xcode、iPhone 测试、后台音频、来源许可 | 若主目标是 iPhone 使用，优先于完整小程序 |
| iOS → App Store | 有技术路径，不能承诺审核通过 | 第三方服务与内容权利、隐私、地区要求、审核 | 不把 TestFlight 当作已获商店准入 |
| 微信小程序 | 可做独立产品，但不是现有工程一键打包 | 主体／类目资格、后台音频审批、合法域名和来源限制、客户端另行实现 | 先资格核验和单页音源验证，暂不投入完整改造 |

这里的排序是结合当前代码与音频产品目标作出的建议，不是各平台官方对本项目的评价。

## 2. 当前工程有哪些能用、哪些不能直接用

实际仓库有 `android/`、`windows/`，没有 `ios/`、`web/` 或微信小程序宿主。Flutter 官方支持的部署目标包括 iOS 和 Web，但不包括微信小程序；本项目也没有额外的小程序转换工具链。[Flutter 支持平台](https://docs.flutter.dev/reference/supported-platforms)

| 现有部分 | 可复用价值／需要调整 | 源码证据（v1.2.0） |
| --- | --- | --- |
| 四频道、分类、倍速、续播、手动收藏规则 | iOS/Web 可复用 Dart 逻辑和 Flutter 组件；小程序复用规则和测试案例，另写实现 | `lib/models/content_mode.dart:1`、`lib/player/playback_preferences.dart:5`、`lib/data/seed_books.dart:365` |
| 收藏、最近收听、关注 | 目前是本地 SharedPreferences，没有服务器同步 | `lib/core/storage/shelf_store.dart:178`、`lib/core/storage/follow_store.dart:22` |
| 播放请求 | 原生链路显式设置 User-Agent 和 B站 Referer，不能直接假设浏览器／小程序也能设置 | `lib/player/book_player.dart:923`、`:1071` |
| 登录凭据 | `abts/credentials` 只在 Android 实现，初始化就会调用；iOS 需安全存储适配，Web 首轮宜明确匿名模式 | `lib/core/storage/credential_store.dart:11`、`lib/core/network/bili_client.dart:117`、Android `MainActivity.kt:27` |
| 本地缓存 | 使用文件目录、下载临时文件（.part）、校验和重命名；Web/小程序需各自实现，iOS需目录与生命周期适配 | `lib/core/storage/cache_store.dart:705`、`:1112` |
| 焦点与后台播放 | 自有焦点插件仅注册 Android；现有 `audio_service` 是复用基础，不能替代 iOS 中断测试 | `packages/blisten_audio_focus/pubspec.yaml:14`、`lib/services/audio_focus.dart:31`、`lib/main.dart:65` |
| 外链、图片保存、设备设置 | 部分非 Android 分支返回 false／跳过；需增加平台实现或隐藏不适用入口 | `lib/services/browser.dart:14`、`gallery_service.dart:24`、`device_service.dart:17` |
| 更新 | 更新源为 GitHub Release，安装入口使用 universal APK，iOS/Web/小程序必须分平台处理 | `lib/main.dart:158`、`lib/services/app_update.dart:100` |
| 验收 | 当前原生测试和 CI 为 Android；通用单元测试可继续使用 | `tool/test-android.sh:2`、`.github/workflows/ci.yml:16` |

生产代码有 7 个文件直接导入 `dart:io`。Web 不能原样使用本机文件系统和 `Platform.is…` 调用，需要条件导入或最小平台适配；这属于迁移工作，不是把一个构建开关打开。[Flutter Web FAQ](https://docs.flutter.dev/platform-integration/web/faq)

## 3. PWA：先证明能连续听，再搬完整界面

PWA 可以用域名访问，也可在支持的浏览器里添加到主屏幕；需要应用 manifest 和安全的 HTTPS 部署。可安装并不等于已经具有离线播放和后台服务能力。[安装条件](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable)

最关键的四项适配是：

1. **搜索和取流请求。** 浏览器脚本受跨域规则约束，Cookie、Origin、Referer 等也不能照搬原生任意设置。服务器端请求成功，不能证明用户浏览器请求成功；还要分别测试接口、封面和音频加载。[CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS)、[请求头限制](https://developer.mozilla.org/en-US/docs/Glossary/Forbidden_request_header)
2. **播放器请求方式。** 本机锁定的 `media_kit 1.2.6` Web 后端在普通非 HLS 分支只设置媒体元素 `src`；HLS 分支才使用 XHR 设置请求头（依赖源码 `lib/src/player/web/player/real.dart:1491–1522`）。因此当前 B站音频 URL 的来源校验、Range 跳转、过期重取都需真实浏览器验证。本轮没有验证某个 B站 URL 的浏览器可播性。
3. **熄屏、切后台和分 P 连播。** Media Session 可连接系统媒体控件，但浏览器支持存在差异；它本身不保证 App 式长期后台运行。必须分别测试 iPhone Safari、添加到主屏幕后，以及 Android Chrome。首播保持用户点击，符合现有“不自动播放”规则，也能处理浏览器自动播放限制。[Media Session](https://developer.mozilla.org/en-US/docs/Web/API/Media_Session_API)、[自动播放规则](https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Autoplay)
4. **离线数据。** 收藏与进度可用浏览器存储，音频缓存需另设计。浏览器有配额和回收策略，不能承诺像 Android 私有文件一样长期保留大量音频。[存储配额和回收](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria)

首轮样机建议只做匿名搜索／BV 导入、在线播放、进度、手动收藏和系统媒体控制；暂不做登录、音频离线下载和跨设备同步。沿用现有配色、四频道、单行收藏入口和迷你播放器，在核心链路通过后补响应式布局。若浏览器播放无法在获准的来源条件下稳定工作，应保留官网用途，停止完整 PWA 投入。

## 4. iOS：工程复用较好，发布有独立门槛

需要增加 iOS 宿主、签名与图标配置、后台音频声明、音频会话／中断处理、安全凭据存储、外链打开和 iOS 更新路径。缓存、TLS 验证及原生音频库也须单独验收；Android 本轮的证据不能直接继承为 iOS 通过。iOS 依赖中已存在音频库条目，只能说明有依赖基础，不能说明已经编译成功。

本机实测为 **macOS 13.7.8、Intel x86_64**，当前只有 Command Line Tools，没有完整 Xcode。Apple 当前要求自 2026-04-28 起上传使用 **Xcode 26 或更高版本、iOS 26 SDK 或更高版本**；Xcode 26 要求 macOS 15.6 或更高版本。因此当前配置不能完成符合要求的正式构建。需要能运行对应工具链的 Mac 或合规的 macOS 构建环境；先核验现有硬件升级条件，再决定是否购置设备。SDK 要求不等于 App 的用户最低系统必须设为 iOS 26。[上传要求](https://developer.apple.com/news/upcoming-requirements/?id=02032026a)、[Xcode 系统要求](https://developer.apple.com/xcode/system-requirements)

Apple Developer Program 为 **99 美元／会员年**，按地区结算；个人和组织的注册／商店显示身份不同。TestFlight 最多支持 100 名内部测试者、10,000 名外部测试者，内部测试者须是有相应内容访问权限的 App Store Connect 团队用户，普通用户应走外部测试。每个构建测试有效期为 90 天；首次外部测试需要审核，后续构建也可能审核。它适合测试迭代，不能当成免审核的永久分发办法。[开发者注册](https://developer.apple.com/programs/enroll/)、[TestFlight 流程](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

**商店审核的关键是第三方来源。** App Review 5.2.2 要求使用第三方服务符合相应许可；5.2.3 涉及未经明确授权保存、转换或下载第三方媒体，并要求确认流媒体使用符合来源平台条款。本轮没有取得 B站服务使用许可或具体内容权利证明。因此，不能判断当前完整形态一定能上架；仅删除离线缓存也不足以作出这种判断。开源代码的 MIT 许可不等于视频／音乐的使用许可。[Apple 审核指南 5.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property)

发布前还需核对插件隐私清单、Required Reason API 和商店隐私说明；若面向中国大陆，要按实际业务核验 App 备案及适用内容材料。已有域名备案不能直接替代这些材料。[隐私清单](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)、[App 信息及中国大陆要求](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)

建议顺序：工具链与来源材料核验 → 真 iPhone 原生播放样机 → 内部 TestFlight → 外部测试审核 → 稳定性／隐私／内容材料齐备后提交 App Store。不能提前承诺审核时长或结果。

## 5. 微信小程序：资格与真实音源优先

微信具备 `wx.getBackgroundAudioManager()`，官方类型定义说明后台音频需要 `requiredBackgroundModes` 配置，正式版还需审核。为 `src` 赋值会开始播放，所以冷启动只能恢复本地预览，等用户点击后才设置播放源，防止违背 B听 的既定交互。[微信官方接口定义](https://github.com/wechat-miniprogram/api-typings/blob/master/types/wx/lib.wx.api.d.ts#L22539)

该播放器的 `referrerPolicy` 只提供 `origin`／`no-referrer`，来源由微信页面决定，不能照搬 Android 自定义 B站 Referer 的方式。需要验证真正可获准使用的媒体地址、拖动与续播，而不是只验证一个自有 MP3 能播就宣称 B站链路可行。[微信官方属性定义](https://github.com/wechat-miniprogram/api-typings/blob/master/types/wx/lib.wx.api.d.ts#L878)

小程序通讯域名需要预设，相关网络接口要求 HTTPS 和域名 ICP 备案；小程序应用备案也需按适用规则处理。域名与服务器是基础条件，不能代替主体资格和内容材料。[微信官方服务器配置说明](https://pay.wechatpay.cn/doc/v3/partner/4012088031)、[工信部应用备案通知](https://www.miit.gov.cn/zwgk/zcwj/wjfb/tz/art/2023/art_920db564162e4312916a01bed6540ad8.html)

**未核实项：** 微信现行音乐／有声读物等具体类目的完整主体和证照清单，及后台音频审批的适用范围。微信文档站本轮无法直接读取，技术能力由微信官方 GitHub 类型定义补证，没有用第三方转载冒充现行审核要求。立项前应在[类目材料入口](https://developers.weixin.qq.com/miniprogram/product/material/)及[微信公众平台](https://mp.weixin.qq.com/)核实。本文不能据此断言个人主体一定可开通，或一定不可开通。

如果资格和来源条件满足，再单独实现一个搜索→播放→后台→恢复的页面；通过后再按现有设计规范做四频道完整客户端。小程序不是当前 Flutter 项目的普通编译目标，前端工程和原生能力适配需要独立维护。

## 6. 已有域名和服务器怎么用

建议首先用于官网、下载指引、版本说明、帮助和隐私政策；下一步才考虑获准的配置接口、收藏／进度同步。当前收藏和历史全部在本地，不能因为增加网站就自动同步。

暂不默认把服务器做成媒体转发站。若以后考虑转发，要先核验来源许可、接口使用边界、访问控制、带宽和运维成本；集中转发还会把接口失败影响集中到同一服务，不能当作“加一台服务器就解决跨域”的完整方案。本轮不部署转发、不保存用户 B站 Cookie。

一个仅供容量估算的例子：假设音频平均 **192 kbps**，转发每用户每小时约 **86.4 MB**，100 人同时听约 **19.2 Mbps** 出站带宽，尚未计协议开销与重试。这不是本版实际码率，也不是现有服务器的实测能力。服务器位置、带宽、月流量额度、系统和域名备案状态尚未知，暂不能给出承载人数或总费用。

## 7. 立项后的验收门槛

| 阶段 | 最小工作 | 通过标准／停止条件 |
| --- | --- | --- |
| A：来源和环境 | 明确允许使用的内容／服务方式；核验服务器、域名、Apple 工具链、微信类目 | 材料和技术入口可用；不满足时只保留官网／Android维护，暂不投入相应完整端 |
| B：PWA 播放样机 | 真实 HTTPS 域名、匿名搜索与 BV、音频元素／媒体控件 | Android Chrome、iPhone Safari、主屏幕模式分别连续听至少30分钟，覆盖锁屏、后台、分 P、seek、地址过期、断网恢复；失败明确记录，不关闭浏览器安全机制 |
| C：iOS 播放样机 | 宿主、凭据、音频会话、外链和更新适配 | 真 iPhone 上验证四模式、锁屏、耳机／来电打断、蓝牙、重启静默、缓存与 TLS 失败处理；Archive 与内部 TestFlight 安装成功 |
| D：微信单页样机 | 获批能力、合法域名、真实允许使用的音源 | 真机微信前后台播放、拖动、恢复、失败提示通过；确认主体类目可发布再做完整页面 |
| E：正式产品 | 复用 B听 视觉规范，完善平台测试、隐私和发布流程 | 各端独立验收及所需审核通过；未经通过的能力不作为已支持宣传 |

建议给样机设定独立的小预算和停止条件，而不是现在承诺三个完整版本的工期。当前材料足以确定以上顺序；准确排期需在来源、工具链和样机结果明确后再估算。

本轮不需要重新设计品牌。后续仍以现有 B听 设计规范、四频道和“手动收藏＋独立最近收听＋静默预览”为共同标准，仅按各平台的系统行为适配。
