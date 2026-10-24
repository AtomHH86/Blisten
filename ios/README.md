# B听 iOS 宿主

应用标识为 `com.bting.audio`，显示名为 B听，最低系统 iOS 15.0。宿主使用 Flutter 3.38.10 和 CocoaPods，声明 `UIBackgroundModes: audio`。

原生通道包括本机 Keychain 凭据、仅 HTTP/HTTPS 的外部浏览器、带请求号的音频会话和中断处理。Keychain 条目不启用同步，使用 `AfterFirstUnlockThisDeviceOnly`；这允许首次解锁后的后台读取并防止迁移到另一台设备，不保证卸载应用时删除。写入 `nil` 会删除该凭据条目。

音频会话只在播放请求时激活。打断结束后，只有原请求仍有效、打断前已激活、系统允许恢复且重新激活成功，才向 Dart 发送恢复事件。用户暂停、耳机断开或新请求都会使旧恢复上下文失效。

`blisten/native_tls` 的 `trustedCaFile` 当前返回 `ios_tls_not_configured`。在可信 CA 策略及真实 libmpv 证书链验证完成前，在线原生音频保持失败关闭；本地音频不因此禁用。不能通过关闭 TLS 校验或伪造 CA 文件消除该错误。

## 编译与验证

`.github/workflows/ios.yml` 使用 `macos-15`，显式选择 Xcode 26.2，校验 Flutter 固定 commit，再执行无签名模拟器 debug 与设备 release 编译。它不会签名、安装、提交 TestFlight 或发布 App Store。

`ios/Podfile.lock` 来自首次成功的 [真实 CI 构建](https://github.com/AtomHH86/Blisten/actions/runs/40122819258)，与构建日志、工具链版本一起取回并提交；后续 CI 会检查构建没有改写锁文件。`pubspec.lock` 和 media-kit iOS 下载包版本/校验值已经固定。runner 的 macOS 补丁、CocoaPods 等预装版本会变化，实际版本保留在每次证据中。

```bash
flutter pub get --enforce-lockfile
flutter build ios --simulator --debug --no-codesign --no-pub
flutter build ios --release --no-codesign --no-pub
```

本机仅具备 Command Line Tools 时，可运行 `swiftc -frontend -parse ios/Runner/*.swift` 做语法检查，不能将其当成 iOS 编译通过。模拟器运行、真机 Keychain/权限、锁屏、电话/Siri/闹钟打断、打断期间手动暂停、蓝牙与耳机断开、前后台切换仍需实际验证。特别需要确认 media-kit、audio_service 和 audio_session 没有相互覆盖 AVAudioSession 配置。

## 品牌资源

`python3 ios/tool/prepare-assets.py` 复用仓库现有 `tool/prepare-brand-assets.py` 的 `sips` 缩放函数，从已批准的 `icon-source.png` 与 `mascot-source.png` 导出 iOS 图标和启动资源；不生成新图、不修改原画。启动背景沿用设计规范的浅色 `#FFF8ED` 与深色 `#152342`。
