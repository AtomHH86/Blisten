# B听正式品牌资产

2026-10-24 使用内置 imagegen，基于用户选定的 B「闭眼听友」方向生成。完整提示词见 [prompts.md](prompts.md)。

- `mascot-source.png`：1254×1254 透明角色母版，用于开屏、空状态、Android 自适应图标前景。
- `icon-source.png`：1254×1254 深蓝方形图标母版，用于传统启动器图标、关于页及 Windows 图标。
- 项目中的平台资源由 `tool/prepare-brand-assets.py` 调用 macOS `sips` 确定性缩放，并打包 ICO；不对生成角色再做绘制或风格修改。
- Android 自适应前景使用 12% 内缩，Android 12+ 系统启动资源独立引用 1024px 母版，避免放大旧 96dp 位图；深浅系统背景分别为深蓝与奶油白。
- 原始概念板仍在上级目录，不能作为实测界面截图。实际验收见 [视觉实施测试记录](../../../testing/2026-10-24-bting-design.md)。

在项目根目录重新制作平台资源：

```bash
python3 tool/prepare-brand-assets.py
```

母版生成不是可逐像素复现的过程，因此保留这两张原始 PNG；后续打包只从已保存母版生成。Android、Flutter、Windows 资源均已提供，Windows 的实际编译与显示需在对应平台另验。
