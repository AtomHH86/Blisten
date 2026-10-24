# Blisten 公开发布内容审查

审查日期：2026-10-24。结论：在下述扫描范围内，未发现真实账号凭据、正式签名私钥或构建产物误入版本库的发布阻塞。本记录不包含凭据值、真实个人邮箱、本机用户名或正式签名秘密。

本次为只读审查；没有联网、修改被审查文件、执行 Git 写入或重写历史。以下数量对应审查时的快照，不代表后续提交的文件数量。

| 范围 | 数量与方法 |
| --- | --- |
| 当前已跟踪文件 | 346 个；通过 `git ls-files` 枚举，检查文件名、内容模式及大小 |
| 未忽略的待新增文件 | 44 个；通过 `git ls-files --others --exclude-standard` 枚举，按相同规则检查 |
| Git 可达历史 | 704 个 blob；通过 `git rev-list --objects --all` 和 `git cat-file` 读取，检查历史文件内容及路径，并另查提交元数据中的凭据模式 |
| 已跟踪截图 | 46 张；使用 Tesseract 英文和简体中文 OCR，检查令牌、Cookie、手机号及邮箱模式；全部完成，未命中这些模式 |
| 忽略规则 | 核对 `.gitignore`、`git check-ignore` 及实际跟踪列表，确认敏感区与生成目录未被跟踪 |
| 原始版权 | 比较根目录 `LICENSE` 与最早可达历史版本，内容逐字节一致 |

检测使用私钥标记、常见服务令牌格式、凭据字段或 Cookie 字面量、带凭据的 URL、个人目录路径及敏感文件名等模式。候选项进一步按文件用途和测试上下文分类；检查输出仅保留路径、类别、数量和结论，没有输出匹配到的秘密值。

| 路径或范围 | 审查结果 |
| --- | --- |
| `integration_test/support/localhost_certificate.dart` | 包含固定的公开测试私钥，用于本地 TLS 夹具；引用仅来自集成测试，不是正式 Android 签名私钥，也不是真实账号凭据 |
| `integration_test/credential_storage_test.dart`、`test/auth_session_test.dart`、`tool/verify-local-backup.py` | Cookie 字面量具有明确的合成测试上下文，未发现真实会话 Cookie |
| `android/key.properties`、`打包数据/` | 正式签名配置与材料所在范围已被忽略，实际跟踪项为零；可达历史中未发现正式签名容器或私钥 |
| `*.jks`、`*.keystore`、`*.p12`、`*.pfx`、`.env` 及本机凭据配置 | 忽略规则覆盖正式签名材料和本机秘密配置；未发现这些秘密被纳入当前待公开文件或可达历史 |
| `*.log`、`build/`、`dist/` | 日志与构建输出已被忽略，相应目录实际跟踪项为零 |
| `packages/media_kit_libs_android_audio/android/src/main/jniLibs/`、`packages/media_kit_libs_android_audio/android/src/main/assets/native-audio/` | 本地生成的原生库及分发材料副本已被忽略，实际跟踪项为零 |
| Git 可达历史 | 未发现正式凭据或误入库的签名容器、原生二进制、构建归档和构建目录；没有超过 10 MiB 的文件 |
| 当前较大文件 | 主要为设计图与截图；未发现大体积构建输出 |
| 根目录 `LICENSE` | 原始 MIT 版权及许可文本保持不变，应继续保留 |

审查曾在 `docs/development/version-control.md`、`docs/project-origin.md` 和 `docs/superpowers/plans/2026-10-23-blisten-project.md` 中发现本机用户目录信息。主流程已将当前文件中的相关路径改为 `/path/to/workspace` 占位符。旧路径仍存在于既有 Git 历史，本轮未重写历史；这些信息属于环境路径元数据，不是签名凭据或账号秘密。

本结论的边界是当前待公开文件和 `--all` 可达历史。未读取被忽略的签名秘密、日志内容或本机 CLI 登录存储，也不涵盖不可达 Git 对象。模式检测不能证明不存在任意格式的秘密；截图 OCR 不能覆盖无法识别的文字或非文本信息。固定测试私钥的存在不应被误报为正式签名泄漏，也不能将本次“未发现”表述为对任何后续新增内容的永久保证。

本记录仅检查源码仓库公开内容；最终 APK、Release 附件及实际远程发布结果由对应发布验收另行核对。
