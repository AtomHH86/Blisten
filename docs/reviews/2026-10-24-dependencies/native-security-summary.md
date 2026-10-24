# 原生组件已知安全公告审计

审计日期：2026-10-24。使用公开的精确源码提交查询 OSV，并另查官方维护者公告与固定源码/构建条件。本次没有升级或替换二进制、复现攻击、运行工具链或上传私有材料。**包名、版本或提交的匹配，不等于 Blisten 已被证明可利用。**

## 覆盖范围与 OSV 结果

[native-security-evidence.json](native-security-evidence.json) 记录四个精确提交查询、完整且按顺序对应的返回，以及匹配公告全文；此次没有未完成分页。这一部分直接检查原生组件，不能用此前 115 个 Pub 包“零匹配”代替。

| 配方组件 | 查询提交 | OSV 返回 |
|---|---|---|
| mpv 0.35.1 | 140ec21c89d671d392877a7f3b91d67e7d7b9239 | 未返回提交范围匹配 |
| FFmpeg n6.0 | ea3d24bbe3c58b171e55fe2151fc7ffaca3ab3d2 | 未返回提交范围匹配 |
| Mbed TLS 3.6.1 | 71c569d44bf3a8bd53d874c81ee8ac644dd6e9e3 | 未返回提交范围匹配 |
| libxml2 v2.10.3 | f507d167f1755b7eaea09fb1a44d29aab828b6d1 | CVE-2023-28484、CVE-2023-29469、CVE-2023-54354、OSV-2021-777 |

下面的官方检查发现前三项 OSV 返回中未包含的重要公告。因此 **零提交匹配不能标为安全检查通过**。

[官方证据 JSON](native-security-official-evidence.json) 的查询时间为 `2026-10-24T05:49:53.837725Z`。交付文件已移除原始响应 `text` 字段，仅保留 URL、原始响应 SHA256 和 `plain`、`table_rows` 等解析字段；`plain` 是提取后的文本，不是原始 HTML/源码。该文件不提供原始响应镜像，不能用解析后的文本重算并验证原始响应哈希。

## mpv：版本匹配，但公告涉及终端环境

[维护者公告 GHSA-546v-22c3-7927](https://github.com/mpv-player/mpv/security/advisories/GHSA-546v-22c3-7927) 指定低于 `0.41.0` 的版本，包含 `0.35.1`。场景是媒体元数据中的终端转义序列，可能影响终端或剪贴板。

配方禁用 cplayer，只构建 libmpv；锁定 media_kit 的生成 API 文档说明 libmpv client API 不访问 stdin/stdout/stderr/terminal，相当于 no-terminal。这使公告中的交互式终端 PoC 与通常的 Android 嵌入播放存在实质差别。本次没有证明应用中的终端利用路径，但应保留版本匹配及其上下文，不能据此认定应用有此漏洞或整个库已安全。三个本地 mpv 补丁涉及 AudioTrack、VM 集成和 libass，不是该终端问题的修复。

## FFmpeg：6.0 分支修复与裁剪后的构建条件

[FFmpeg 官方安全页](https://ffmpeg.org/security.html) 将 CVE-2023-47342 列为 `6.0.1` 修复，晚于本次基础版本 n6.0。[官方回补提交](https://github.com/FFmpeg/FFmpeg/commit/07e3223dd0213cc5f0b65e98a6e1b1500d09ece0) 修复 RTSP 流索引处理；报告路径涉及 H264 RTP 解析。

固定配方先禁用所有 demuxer/decoder/parser，再选择性启用音频及图像相关路径；没有启用 RTSP demuxer 或 H264 decoder。这是公告路径可能未进入此构建的具体源码配置依据，不是二进制可达性证明。所带的一个 FFmpeg 补丁修改 DASH base-URL 转义，不是该 RTSP 修复。

本次检查覆盖官方 6.0 分支段落及选定源码条件，没有穷尽所有后续 FFmpeg 公告对 6.0 的潜在影响，也没有宣称裁剪后的整个 FFmpeg 已安全。

## Mbed TLS：49 项公告中的 42 项版本范围包含 3.6.1

遍历[官方 2024 年起的安全公告索引](https://mbed-tls.readthedocs.io/en/latest/security-advisories/)，获得 **49 个唯一公告页面**。逐项比较受影响范围，**42 项包含 3.6.1，其中 1 项没有 CVE 编号；7 项排除 3.6.1**。这是版本范围计数，**不是 42 个已证实的应用漏洞**。

完整 ID、范围、日期、URL 和条件备注见[JSON 矩阵](native-security-mbedtls-matrix.json)与[CSV 矩阵](native-security-mbedtls-matrix.csv)。所记录公告日期均不晚于 `2026-07-07`，早于本次审计日期；2024 年之前的公告未作穷尽复审。

7 项排除结果为：CVE-2024-23170 与 CVE-2024-23775 的相关范围截至 3.5.1；CVE-2024-28960 截至 3.5.2；CVE-2024-45158 仅涉及 3.6.0；CVE-2024-45159 截至 3.6.0；CVE-2026-54434 涉及 4.1.0 / TF-PSA-Crypto 1.1.0；CVE-2026-50713 的相关范围从 3.6.3 开始。逐项原始范围仍以矩阵所记录的官方表格为准。

| 公告 | 配方 / 源码条件与剩余不确定性 |
|---|---|
| CVE-2024-49195，opaque-key export | 需要 USE_PSA_CRYPTO；固定版本的默认配置未定义该宏，配方未见覆盖 |
| CVE-2025-27809，hostname authentication default | FFmpeg n6.0 对非数字客户端主机调用 mbedtls_ssl_set_hostname，字面 IP 路径跳过；不能据此全面放行 TLS |
| CVE-2025-27810，handshake error handling | 版本范围包含 3.6.1；仍有内存分配或硬件错误前提，未找到原生补丁回补 |
| CVE-2025-52496，AESNI detection | 涉及 x86/amd64、线程和编译器条件；配方使用 Clang，维护者表示未观察到 Clang 产生受影响输出，但未证明此二进制条件 |
| CVE-2025-52497，encrypted PEM parsing | 需要不可信加密 PEM 和非 NULL 密码；解析器默认开启，应用 API 可达性未证明 |
| CVE-2026-73096 / CVE-2026-50588 | early-data / ECJPAKE 在固定默认宏中关闭，配方未见覆盖 |
| CVE-2026-50583 | 指定 driver-only ECC；固定默认配置使用内置 ECP |
| CVE-2026-50580 | 需要 ECDHE-PSK 和超长 PSK identity；默认启用该交换方式，实际应用配置和路径未证明 |

[native-security-build-conditions.json](native-security-build-conditions.json) 记录了去除注释后核对的默认配置宏。它们是源码/配方线索，不是实际生成头文件或二进制功能证明。固定原生树中没有 Mbed TLS 补丁；部分公告相关功能/API 默认仍开启，不能因为这是音频应用就整体排除匹配项。

## libxml2：直接修复、封装层记录与模糊测试记录

官方 [v2.10.4 NEWS](https://github.com/GNOME/libxml2/blob/v2.10.4/NEWS) 明确修复 CVE-2023-28484（schema NULL 解引用）和 CVE-2023-29469（空字典字符串哈希），晚于本次基础版本 2.10.3。

对照 [v2.10.3 configure.ac](https://github.com/GNOME/libxml2/blob/v2.10.3/configure.ac)，配方的 `--with-minimum --with-threads --with-tree` 默认禁用 schemas、XInclude 和 XPointer。这可能排除 schema 公告和 OSV-2021-777 中报告的 XInclude/XPointer 路径。字典代码没有同样的排除依据，仍需检查实际链接和使用。FFmpeg 的 demuxer 子集没有显式启用 DASH，所以 configure 中启用 libxml2 不证明所有 XML 功能都保留在静态链接结果中。

CVE-2023-54354 描述的是捆绑该 libxml2 的 **Nokogiri 封装层**，涉及重叠的 schema 缺陷。Nokogiri 不是 Blisten 依赖，不能把这条记录额外计为一个已证明的应用问题。OSV-2021-777 是模糊测试发现，不是独立 CVE。固定原生补丁集中没有 libxml2 补丁。

## 发布检查结论

已知原生版本匹配和若干构建约束已有具体证据，但**原生安全发布检查尚未通过**。需要保留官方匹配项，核实实际编译/链接功能与应用可达路径，再决定下一轮升级、修补或有证据的例外接受。本次没有复现应用利用，也没有进行原生升级或修复。

Pub 或原生 OSV 的零匹配、部分编解码器裁剪、封装层 MIT 通知都不能独立完成这些检查。配套的[来源与许可证审计](native-source-audit.md)还列有历史 helper 提交、完整分发材料、实际 release 成员及源码可复现性边界。
