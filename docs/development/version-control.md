# Blisten 版本与回退指南

建立日期：2026-10-24。项目目录：`/Users/atom/chatgpt/vibeREA/Blisten`。

## 当前保护状态

Blisten 原本已有独立 Git 历史，本次在此基础上补齐主分支、固定检查点和可恢复的离线备份，未重新初始化仓库或改写历史。保留同级 abts 不动。本次不开始质量修复、不创建 GitHub 远程仓库、不发布 APK。

| 名称 | 指向/用途 |
| --- | --- |
| `checkpoint/review-2026-10-24` | `c68d2d6`，全面审查与改进方案；尚不含后来的 UP 主一级搜索 |
| `checkpoint/search-categories-2026-10-24` | `a16cf5b`，已验证的四分类搜索和 UP 主页模式选择 |
| `baseline/pre-quality-fixes-2026-10-24` | 本次 Git 保护完成时的提交：源代码与 a16cf5b 相同，增加版本规则和本指南；正式修复前的推荐回退点 |
| `main` | 汇总当前已验收的本地版本；此前落后的 3 个提交已快进合入 |
| `codex/quality-phase-a` | 从修复前基线创建的工作分支，本次只准备，不写修复代码 |
| `codex/bting-design-v1` | 保留原视觉与搜索开发分支，不删除 |

标签是固定书签，不随后续提交自动移动；分支会随提交推进。标签不使用正式 v1.0.0 发布名，不改变 pubspec 或 APK 版本。后续不能强制覆盖修复前基线。

`upstream` 仅指向原阿B听书，推送地址为 `DISABLED`。尚无 Blisten 的 `origin`。旧克隆留下的无效 `origin/HEAD` 引用已保留原文后移除，提交对象未删除。仓库本地提交身份沿用既有提交者“海纳百川 <atom@iMac.local>”，没有改动全局配置；正式联网协作时可再配置合适的提交邮箱。

## 日常开发怎样保留退路

1. 开始前执行 `git status --short --branch`，确认分支和待保存改动。
2. 在 `codex/quality-phase-a` 修阶段 A；一次只处理一个可验收问题，保留失败复现，修复后运行必要回归。
3. 用具体文件路径暂存，检查 `git diff --cached --stat` 和 `git diff --cached`，确认不含无关文件、凭据或构建产物后提交。
4. 每项修复提交说明问题、最终行为和验证。批次回归通过后，将对应分支以 `git merge --ff-only` 合入 `main`，再建一个新的带说明检查点，记录测试结果。
5. 下一阶段从最新 `main` 创建新 `codex/` 分支；如果快进失败，先查分叉，不用强制覆盖解决。

检查点命名示例：`checkpoint/quality-phase-a-2026-10-25`。它只是后续命名示例，当前没有创建，也不能因本指南存在就认定阶段 A 已完成。

`.gitignore` 排除构建/SDK缓存、APK/AAB、Git bundle、本地 .env、签名私钥等；不排除公开的本机 HTTPS 测试证书夹具。忽略规则只减少误操作，不能识别写进 Dart/文档中的秘密，因此仍需检查暂存差异。

## 想恢复到修复前：保留新历史的做法

最适合小白的指令：**“请把 Blisten 恢复到修复前检查点，保留后来的提交和未保存改动。”** 助手应先检查当前状态，再在恢复分支处理，不需要你手动删除文件。

以下命令只应在工作区已保存、`git status --short` 没有输出时执行。有修改先提交或明确另存，不要强行切换：

```bash
(
set -e
cd /Users/atom/chatgpt/vibeREA/Blisten
if [ -n "$(git status --porcelain)" ]; then
  printf '存在未保存改动，请先保存后再恢复。\n'
  exit 1
fi
git switch -c codex/restore-pre-quality baseline/pre-quality-fixes-2026-10-24
)
```

执行后，当前项目文件恢复到检查点，后来提交仍保留在原分支。`-c` 在同名分支已存在时会停止，不覆盖它；再次恢复时选一个新的分支名或先核对已有分支。确认版本合适后再决定是否集成到主分支。

如果只想撤销某一个已提交修复，先用 `git log --oneline --decorate` 找到提交，核对影响后用 `git revert` 生成一个撤销提交。存在依赖或冲突时需处理并回归，不能盲目一次撤销多项。这里只说明方法，不提供会误撤销当前 HEAD 的通用命令。

## 仓库损坏或被误删：从离线备份恢复

本机备份位置（不在项目 Git 目录内）：

```text
/Users/atom/chatgpt/vibeREA/Blisten-backups/2026-10-24-pre-quality-fixes/
  Blisten-pre-quality-2026-10-24.bundle
  SHA256SUMS
  verification.json
  git-before-protection.json
```

bundle 包含创建时的所有分支、标签和可达提交历史。已执行 `git bundle verify`，并在临时目录从 bundle 克隆、检出基线、核对全部跟踪文件和运行 Git 完整性检查。实际提交号、摘要及核对结果记录在同目录 `verification.json`。

不要覆盖正在用的 Blisten。下面整块命令在独立子 shell 中执行，任一步失败就停止，不会关闭当前终端。恢复到一个**尚不存在**的新目录：

```bash
(
set -e
cd /Users/atom/chatgpt/vibeREA/Blisten-backups/2026-10-24-pre-quality-fixes
shasum -a 256 -c SHA256SUMS
git clone --branch main ./Blisten-pre-quality-2026-10-24.bundle /Users/atom/chatgpt/vibeREA/Blisten-restored
cd /Users/atom/chatgpt/vibeREA/Blisten-restored
git switch -c codex/restored-baseline baseline/pre-quality-fixes-2026-10-24
git fsck --full --no-dangling
)
```

克隆后 `origin` 会指向本地 bundle 文件，不是 GitHub；原仓库的本地用户配置等也不在 bundle 内，需按实际环境重新配置。恢复演练在临时目录完成，不把另一个副本作为新的日常开发项目；日常修改仍只在 Blisten 中进行。

此备份在同一台电脑上，主要防误操作；重要里程碑可再复制到外置盘。后续新增提交不会自动写入旧 bundle，应另建日期明确的新备份并再次校验，不覆盖此初始备份。

## 保护的范围

- 包含：已提交源码、测试、设计资产、文档和 Git 提交历史。
- 不包含：未提交/被忽略文件、SDK、Flutter、依赖缓存、原始运行日志、签名私钥、真实账号信息、手机/模拟器里的收藏和播放数据。
- 回退源码不等于回退已安装 APK 或应用数据。后续若改数据格式，必须保持向后兼容或另设数据迁移与备份方案。
- 本次只改 Git 元数据、忽略规则与文档，没有改应用行为；验收使用真实备份恢复检查，不重复运行 Android 功能测试。当前质量问题仍以[审查报告](../reviews/2026-10-24/README.md)和[改进方案](../superpowers/plans/2026-10-24-quality-improvement.md)为准。
