# Blisten Project Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 将已验证的 abts 扩展建立为独立的 Blisten 本地 Git 项目，具备可供 GitHub 托管的文档、协作模板和持续检查，并从新目录执行后续开发。

**Architecture:** 从现有提交完整克隆，不依赖旧仓库对象或源文件，保留上游历史和 MIT 版权。工具链位于工作区父目录，可供新项目复用；项目自身不包含 SDK、缓存、证书或 APK。GitHub 远端尚未创建，不配置虚构的 origin 或发布链接。

**Tech Stack:** Flutter 3.38.10 / Dart 3.10.9、Android SDK、JDK 17、Bash、Python unittest、GitHub Actions。

## Global Constraints

- 唯一后续开发目录：`/path/to/workspace/Blisten`。
- 保留原 `abts` 仓库，不在迁移过程中修改旧目录。
- 保留听书、歌曲、演唱会功能及既有测试；不生成正式签名安装包。
- 原始 MIT 版权不可删除；历史测试报告保留原身份与路径，不能改称新仓库的验收证据。
- Android 包名涉及安装和数据空间，按用户确认的范围修改；数据键和原生通道不是品牌展示文案。
- 不发布远端，不提交证书、账号数据、本机路径配置、SDK、构建缓存与 APK。

---

### Task 1: 独立仓库与开发入口

**Files:** `README.md`, `AGENTS.md`, `CHANGELOG.md`, `docs/project-origin.md`, `docs/index.html`, `.gitignore`。

- [x] 从已验证的 `d9f7c5b` 使用 `git clone --no-local --no-hardlinks --no-tags --single-branch` 创建新目录。
- [x] 默认分支改为 `main`，移除指向本地旧仓库的 origin，添加原作者仓库为 upstream，并将 upstream push URL 设置为 `DISABLED`。
- [x] README 说明功能、测试、打包、最低 Android 7.0、项目来源及当前未发布状态。
- [x] AGENTS 固定后续开发入口；来源文档明确继承版本与提交，区分历史证据和当前迁移验收。
- [x] 当前入口页不得把原作者下载页当成 Blisten 发布页；保留来源和原始历史文件。

验证：`git remote -v`、`git log --oneline -5`、`git status --short`；检查本地链接存在，检查跟踪文件不含构建产物与签名文件。

### Task 2: GitHub 协作与自动检查

**Files:** `.github/workflows/ci.yml`, `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md`, `CONTRIBUTING.md`, `SECURITY.md`, `SUPPORT.md`, `.editorconfig`。

- [x] 添加中文贡献和支持说明、缺陷/功能模板、PR 验证清单。
- [x] CI 固定 Flutter 3.38.10，最小只读权限，执行 `flutter pub get`、`flutter analyze`、`flutter test test`、`python3 -m unittest discover -s tool/tests -v`。
- [x] 不添加尚未运行的成功徽章；安全反馈说明不包含虚构邮箱或未启用的私密通道。

验证：YAML 解析、检查 workflow 命令与本机命令一致；本地执行同等分析与测试。

### Task 3: 明确应用身份边界

**Files:** `README.md`, `docs/project-origin.md`。

- [x] 向用户说明显示名、包名与数据空间的区别；更名范围答复尚待，相关应用改动未执行。
- [x] 本轮独立完成仓库迁移，保留显示名、Dart/Android 包名、数据键、原生通道及 APK 文件名前缀。
- [x] 在 README 与来源说明明确关于页、更新源和统计归属仍是迁移基线，不能把当前构建当成独立品牌正式版。

应用更名属于待确认的后续动作：确认后同步处理展示、更新源和统计配置，并按最终身份复验。本次未将其列为已完成。

### Task 4: 验收与交付

**Files:** `docs/testing/2026-10-23-blisten-migration.md`、本计划。

- [x] 在 Blisten 目录分别运行 `tool/test-android.sh unit` 与 `tool/test-android.sh integration`（与 all 的两个阶段相同），记录实际日志、计数和结果。
- [x] 检查正式签名缺失时打包脚本安全退出，不产出正式包。
- [x] 检查 `git -c core.whitespace=cr-at-eol diff --check`，完成新仓库提交。
- [x] 打开新项目 README，交付实际路径、测试结果及远程尚未发布状态。
