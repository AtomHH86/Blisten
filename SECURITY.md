# 安全问题处理

Blisten 已在 [AtomHH86/Blisten](https://github.com/AtomHH86/Blisten) 启用 GitHub 私密漏洞报告。请通过[私密报告入口](https://github.com/AtomHH86/Blisten/security/advisories/new)提交安全问题。本项目不承诺历史版本维护或固定响应时间。

发现安全问题时，先记录受影响的提交或版本、运行环境、影响范围和最小复现步骤。不要在公开 Issue 中提交有效凭据、个人数据、签名密钥或可直接利用的敏感细节；复现材料请使用合成数据。

普通播放、搜索或安装问题请参阅 [SUPPORT.md](SUPPORT.md)。

## 开发与发布

本仓库忽略发布证书和 `key.properties`。若凭据曾进入 Git 历史，仅删除当前文件不足以撤销泄露，应先撤销或轮换凭据，再处理历史记录。

CI 仅执行分析和测试，仓库令牌权限为只读；发布签名不进入 CI。正式发布前应检查依赖、安装包签名和实际升级行为，不能以单元测试通过替代发布验证。
