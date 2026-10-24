# 审查复现用例

这些用例针对基线 `273df4a` 断言**正确行为**。本轮 17 项全部失败，实际输出与[审查报告](../README.md)相符，属于缺陷复现证据；不是应用修复，也不是普通 CI 的通过基线。故放在 `docs/` 而不放入日常 `test/`。

所有账号值、媒体、API 响应均为合成数据；原生套件使用本机 HTTPS fixture。没有真实账号 Cookie。不要把假测试证书或重定向机制带入生产网络代码。

## 命令

在 Blisten 目录执行，Flutter/Gradle/ADB 不并发运行：

```bash
source tool/android-env.sh
flutter test docs/reviews/2026-10-24/probes/api_review_test.dart docs/reviews/2026-10-24/probes/ux_review_test.dart --no-pub --reporter expanded
# 当前基线预期非零：12 个行为断言失败。
export ABTS_EMULATOR_PORT=5554
review_device="$(tool/android-emulator.sh start --headless)" || exit $?
flutter drive --driver=test_driver/integration.dart --target=docs/reviews/2026-10-24/probes/playback_review_test.dart -d "$review_device" --no-pub --keep-app-running --timeout=600
# 当前基线预期非零：5 个行为断言失败，setup/teardown不计场景数。
adb -s "$review_device" shell am force-stop com.bting.audio.debug
tool/android-emulator.sh stop
```

原生用例清理专用模拟器测试应用的本地数据；不要在这个测试包保存重要内容。驱动失败后仍需执行停止/关闭命令。探针里的 6 秒、3 秒等待均有明确观察目的；后续能注入时钟的单元逻辑应使用可控时钟。

## 本轮结果对应

| 文件 / 场景 | 对应问题 | 正确预期 | 本轮实际 |
| --- | --- | --- | --- |
| API：UP 全失败 | R07 | 抛出加载错误 | 返回空内容、没有异常 |
| API：热门首次失败 | R07 | 抛出加载错误 | 返回空列表 |
| API：服务端失效 | R08 | isLogin=false | true |
| API：预热日志 | R01 | 不含假 session | 包含完整假 session |
| API：退出后旧 nav | R08 | 保持退出 | true |
| API：三次并发 | R09 | 相邻至少400ms观察阈值 | 出现0ms |
| UX：章节失败提示 | R12 | 无“正在播放” | 有该文本 |
| UX：320/360dp ×100% | R10 | 无布局异常 | 两例均溢出48px |
| UX：320/360dp ×200% | R10 | 无布局异常 | 两例均溢出285px |
| UX：10分钟预设 | R11 | 1个选中 | 5个选中 |
| Native R-PLAY-01 | R02 | 连续播放已存≥2000ms | 0ms |
| Native R-PLAY-02 | R03 | 延迟返回后仍暂停 | playing=true |
| Native R-PLAY-03 | R06 | loadFailed | bookGone |
| Native R-PLAY-04 | R05 | 恢复cid503 | cid501 |
| Native R-PLAY-05 | R02 | 停止后保留≥19000ms | 0ms |

R-PLAY-04 做的是实际缓存播放、内存记录按存储格式的 JSON 序列化往返和换会话，未重新读取磁盘，也未跨进程。原有 restart 套件另已重跑通过。代码通过静态分析；API/UX 用例在 docs 路径中对 SharedPreferences 的测试专用接口有局部说明，不改变生产分析规则。

修复时逐个迁入常规测试，并把预期行为修到通过；不能通过 `skip`、放宽断言或更改观察顺序隐藏问题。若实现改动使构造失效，应重建等价用户路径并说明证据变化。
