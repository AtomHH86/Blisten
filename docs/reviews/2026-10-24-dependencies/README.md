# Blisten 依赖、许可证与原生安全审计

本目录记录 **2026-10-24** 的审计结果和可追溯证据。已整理依赖清单、原生音频库来源与已知安全公告；**尚未通过原生安全和分发材料的发布检查**。本次没有升级依赖、替换原生二进制、复现攻击或执行发布。

建议先读本页，再按需要查看[依赖清单与 OSV 结果](dependency-audit-evidence.md)、[原生库来源与许可证](native-source-audit.md)、[原生安全公告与适用条件](native-security-summary.md)。

## 这些数字分别表示什么

| 数字 | 已确认含义 | 不能据此得出的结论 |
|---|---|---|
| Dart 锁文件 123 项 | 115 个 hosted Pub 包、7 个 SDK 包、1 个本地 path 包；加上根应用后，许可证清单有 124 项 | 不是最终安装包的完整软件物料清单（SBOM），也不包含原生库全部内部组件 |
| Pub 查询 115 项，OSV 匹配 0 项 | 查询时，这些精确包名和版本没有返回 OSV 公告 | 不代表没有漏洞，也不覆盖 Flutter 引擎和原生捆绑组件 |
| Maven 97 项 | 来自既有 app **debug lint model** 的 97 个唯一坐标 | 不是 release 运行时依赖图或 release SBOM；含测试框架的 debug 图不能代替正式包核验 |
| 原生 JAR 4 个 | 本地四种 ABI 的 JAR 均与上游 v1.1.8 发布资产的 SHA256、大小及 Pub 包固定的 MD5 一致 | 不等于已从源码可复现构建，也不能证明最终 APK 实际包含哪些文件 |
| Mbed TLS 公告 49 项，其中 42 项包含 3.6.1、7 项排除 | 对官方 2024—2026 年公告范围逐项比较所得，42 项中含 1 项没有 CVE 编号 | **不是 Blisten 已证实存在 42 个漏洞**；是否编译相关功能、是否可从应用触达仍需判断 |

## 四个原生 JAR 从哪里来

锁定的 `media_kit_libs_android_audio 1.3.8` 指向上游 [libmpv-android-audio-build v1.1.8](https://github.com/media-kit/libmpv-android-audio-build/releases/tag/v1.1.8)。发布元数据对应构建仓库提交 `87744be8b337c50ed54961249b7a97c5e8cc37c9`，发布时间为 `2025-08-02T14:17:29Z`。本地文件与该发布资产的字节一致性已核对，详见[资产哈希证据](native-asset-identity.json)。

构建配方选择 mpv 0.35.1、FFmpeg 6.0、Mbed TLS 3.6.1、libxml2 2.10.3；辅助库从未固定提交的 `main` 分支构建。二进制字符串支持 mpv/FFmpeg 的版本及部分许可证判断；Mbed TLS/libxml2 的精确二进制修订仍只有构建配方证据。辅助库的发布时提交、源码到二进制可复现性和最终包内成员尚未闭环。

## 发布前仍需完成

1. **处理原生安全公告。** 保留版本匹配结果，核对实际编译和链接后的功能、应用可触达的调用路径及补丁情况，再决定升级、修补或有证据的例外接受。OSV 没有匹配、裁剪部分解码器或应用主要用于音频，都不能直接作为放行依据。
2. **补齐分发材料。** 根据最终包含的组件整理第三方 notices、许可证、必要的源码提供材料及组件例外；查明辅助库历史提交。四个 JAR 内没有 LICENSE/COPYING/NOTICE 文件，封装层 MIT 许可证不能代替 mpv、FFmpeg 等内部组件的材料。这里没有认定整个应用必须采用某一种许可证。
3. **核对实际 release。** 记录准备发布版本依赖图中的 AAR/JAR 及其哈希，核对它们与 APK 原生库成员、DEX 产物的对应关系，确认 debug 图中的 JUnit/Guava 测试依赖是否进入正式包，再评估相关 API 的使用情况。当前 97 项 Maven 清单不能完成这一步。

下一轮原生库工作应先提出可核验的升级或修补方案，固定组件、补丁和辅助库提交，并重新生成来源与许可证材料。实施后再验证四种 ABI、16 KiB 页兼容、播放、缓存和后台场景。这里没有选择或安装新的版本，不能把文档整理记为已完成升级或已全部排除安全风险。

## 证据文件索引

| 用途 | 文件 |
|---|---|
| Dart 锁定依赖、许可证文件哈希 | [JSON](dart-license-inventory.json)、[CSV](dart-license-inventory.csv) |
| 既有 debug Maven 图、POM 声明与继承来源 | [native-license-inventory.json](native-license-inventory.json) |
| 115 个 Pub + 97 个 Maven 的 OSV 查询 | [osv-evidence.json](osv-evidence.json) |
| 上游发布、标签和资产元数据 | [native-upstream-metadata.json](native-upstream-metadata.json) |
| 本地 JAR 与发布资产一致性 | [native-asset-identity.json](native-asset-identity.json) |
| 固定构建配方、补丁与工具版本 | [native-upstream-recipes.json](native-upstream-recipes.json) |
| 组件标签对应提交、组件许可证 | [native-component-tag-commits.json](native-component-tag-commits.json)、[native-component-licenses.json](native-component-licenses.json) |
| 本地二进制字符串及成员哈希 | [native-binary-strings.json](native-binary-strings.json) |
| 四个原生组件精确提交的 OSV 查询 | [native-security-evidence.json](native-security-evidence.json) |
| 官方安全公告和源码条件摘取 | [native-security-official-evidence.json](native-security-official-evidence.json) |
| Mbed TLS 逐项版本范围比较 | [JSON](native-security-mbedtls-matrix.json)、[CSV](native-security-mbedtls-matrix.csv) |
| 去除注释后核对的默认配置宏 | [native-security-build-conditions.json](native-security-build-conditions.json) |

`native-security-official-evidence.json` **已移除原始响应的 `text` 字段**，保留 URL、原始响应 SHA256，以及 `plain`（提取后的文本）、`table_rows` 等解析字段。它提供来源和解析结果，不是原始 HTML/源码镜像；不能把规范化后的 `plain` 重新哈希，并要求它等于原始响应 SHA256。此说明只针对该文件，不表示其他配方、许可证证据中的文本也已删除。

清单中的本机路径已用 `${PROJECT}`、`${ANDROID_TOOLCHAIN}`、`${FLUTTER_SDK}` 等占位符表示。它们用于说明来源位置，不是可直接访问的当前绝对路径。本目录没有附带可完整重建本次审计的自动化脚本；后续刷新时应重新核验输入、构建变体、查询日期和公告覆盖范围。
