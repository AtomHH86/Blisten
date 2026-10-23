# 变更记录

## Unreleased — Blisten

- 从已验证的 abts 扩展建立独立 Git 项目，保留上游历史与 MIT 许可。
- 增加 Blisten 项目说明、来源记录、开发约定、贡献指南、Issue/PR 模板与 GitHub Actions 快速检查。
- 复用现有电脑 Android 工具链；后续开发、测试和打包在 Blisten 目录执行。

尚未发布新的正式版本或四种签名 APK；代码中的 `1.2.0+3` 是迁移基线，不代表 Blisten 已发布同名版本。

## 迁移基线 — 2026-10-23

继承本地提交 `d9f7c5b`：

- 保留听书，增加歌曲和演唱会搜索、链接/BV 导入及独立倍速与续播规则。
- 隔离 Android 调试包，加入真机与模拟器测试记录。
- 补齐单元/组件、Android 原生播放、离线缓存、跨进程恢复和真实 B 站联网测试。
- 提供四 ABI 正式打包和签名/元数据校验脚本。
- 修复缓存过程中新增任务时活动下载请求的分 P 信息（page / part / order）丢失的问题。

此前上游变更见 Git 历史和 [迁移前 README](docs/upstream/abts-readme.md)。
