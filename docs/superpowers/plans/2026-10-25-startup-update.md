# Startup Update Repair Implementation Plan

> For agentic workers: use subagent-driven-development, review each deliverable.

**Goal:** 修复成功检查后的冷启动漏查，并让更新提示只包含用户可见功能与修复。
**Architecture:** 保持现有AppUpdatePrompt状态机、Dio请求和安全下载验证，仅移除跨会话启动抑制并提取发布说明段落。
**Tech Stack:** Flutter3.38.10/Dart3.10.9、Dio、Android现有工具链。

## Global Constraints
- 包名com.bting.audio、签名、存储和播放规则保持兼容；不动已有v1.2.0标签。
- 旧1.1需手动升级一次，不能宣传远程修好了已安装代码。
- 只在Blisten目录修改，发布前必要检查通过。

### Task 1: 回归与最小修复
Files: lib/widgets/app_update_prompt.dart, lib/services/app_update.dart, test/app_update_prompt_test.dart, test/app_update_test.dart, integration_test/app_update_prompt_test.dart.
- [ ] 将旧24小时测试改为：首次成功后销毁widget、前移1分钟并重新挂载，有新版本则出现AlertDialog；先运行观察失败。
- [ ] `_checkAutomatically` 不因SharedPreferences旧时间返回，保留每个State仅一次启动检查、并发与前后台机制。
- [ ] 给parseRelease加结构化body测试：`## 新增功能\n- A\n## 问题修复\n- B\n## 开发记录\nsecret` 返回A和B而不含secret；无结构段落使用通用用户说明。先红后绿，严格URL验证不变。
- [ ] 更新native fixture验证最近成功时间已设置仍自动检查；不要仅删除fixture时间绕过问题。
- [ ] 跑 `flutter test test/app_update_prompt_test.dart test/app_update_test.dart --no-pub`，记录红绿输出并提交具体文件。

### Task 2: Review, test and release
- [ ] 独立审查T1；必要修正再复验。
- [ ] 根代理更新版本1.2.1+4和CHANGELOG，发布说明采用新增功能/问题修复两段。
- [ ] 全量host/script/analyze，Android build/lint和更新相关native；正式四APK静态核验和正式包冷启动/升级测试。
- [ ] 干净源码提交/CI，通过后发布四APK、校验和及原生来源材料；匿名回读并实测公开更新。旧包行为以记录为准。
