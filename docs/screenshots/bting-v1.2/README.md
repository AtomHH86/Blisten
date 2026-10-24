# B听 1.2 代表截图

## 固定测试数据的 debug 画面

以下图片来自 `build/desktop-tests/20261025-011451-75603/screenshots/`，为 API35 x86_64 专用 Android 模拟器上 debug 包的实际渲染截图，使用固定测试数据。三张均经过实际像素检查；仅展示相应布局和状态，不代表线上资源可用性、ARM 真机或全部设备覆盖。

图片直接复制自最终主视觉运行，未裁切、重绘或修改像素。原始测试生成 52 张主截图，实际查看范围为 15 张关键样本及 2 张追加样本；另有最终面板 8 张。代表截图不扩写为全部截图逐张验收。完整运行与正式签名包验证范围见[本版验收记录](../../testing/2026-10-24-v1.2-release.md)。

| 图片 | 内容 | 原始像素 | SHA256 |
| --- | --- | --- | --- |
| [light-discover.png](light-discover.png) | 浅色发现页：四频道入口与听书专属分类 | 720 × 1280 | `93ad277f82e82c5fcf71c717af62572d1a4e1cf649008606156cf401f488a04f` |
| [dark-320dp-200-recent-paused.png](dark-320dp-200-recent-paused.png) | 深色在听视图：320dp、200% 字号与暂停中的迷你播放器 | 720 × 1280 | `1e1dfb70b4df2ae7a18d81ea7d71f6c6cf9e7522c6e89b656a8af9420e0bd6fb` |
| [light-320dp-200-favorites-paused.png](light-320dp-200-favorites-paused.png) | 浅色收藏视图：320dp、200% 字号、频道分组与迷你播放器 | 720 × 1280 | `25cdd65ce184a92d64a2778f27f9da079b1433d6a35bcd2cc771a1d2eb509790` |

## 正式包公开更新画面

以下图片来自 `build/v1.2-readiness/apk-blackbox/`，是在同一 API35 x86_64 专用模拟器上的正式包与浏览器真实公开检查，不使用更新夹具。已逐张查看像素并直接复制原图。旧版自动检查前只重置了成功检查的 24 小时冷却字段，其他偏好已核对未变。

浏览器只验证真实 Release URL 与通用 APK 下载确认框，该次浏览器下载已取消；另外将独立匿名下载的 GitHub universal 包通过 ADB 安装并核验实际安装字节，没有操作 Android 安装器界面。最新提示只采用 `public-latest-frame-3.png`；旧 `public-new-latest-visible.png` 仍是检查中，不作为成功截图。

| 图片 | 内容 | 原始像素 | SHA256 |
| --- | --- | --- | --- |
| [public-old-auto-update.png](public-old-auto-update.png) | 正式 1.1 自动检查真实公开 Release，显示最新 1.2.0 | 720 × 1280 | `27f7f4fa0f9a9f8766c34ae687ecac4f7357436450a9096d090928dcce707a8f` |
| [public-browser-download.png](public-browser-download.png) | 真实 universal APK URL 触发浏览器通用下载确认；本次浏览器下载已取消 | 720 × 1280 | `baa31e152f6bfab4454dd04ed8b95ed6f29a22673ce1aa8872ac9a1f51ebeded` |
| [public-latest-frame-3.png](public-latest-frame-3.png) | 正式 1.2 实际显示“已是最新版本 1.2.0” | 720 × 1280 | `508544873408d7f49b5bc5bb380f0f63fe9320ab0dd638ed5b6fddb62b44e51a` |
