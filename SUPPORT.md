# 获取帮助

先查看 [README](README.md) 和[电脑测试指南](docs/testing/android-desktop-guide.md)。问题反馈与功能建议请提交至 [AtomHH86/Blisten Issues](https://github.com/AtomHH86/Blisten/issues)，并选择对应的 Issue 模板。

报告问题时提供应用版本与构建号、设备或模拟器型号、Android 版本、所用模式、复现步骤和预期结果。资源相关问题可附可公开访问的 BV 号或链接，并说明是否使用缓存。日志只需保留与故障相关的片段，分享前删除账号信息、Cookie、Token 和本机敏感路径。

电脑自动测试的日志保存在 `build/desktop-tests/<时间>-<进程号>/`。请同时提供执行的测试命令和 `exit-code.txt`；退出码为 `0` 才表示该次所选检查全部通过。真实 B 站测试独立于固定数据回归，其失败也可能来自网络、资源失效或平台接口变化。

安全漏洞请按 [SECURITY.md](SECURITY.md) 处理。本项目目前未承诺客服服务时间、响应时限或设备全覆盖。
