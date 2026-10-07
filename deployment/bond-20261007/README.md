# 2026-10-07 单连接代理部署记录

这是绑定此次设备基线的历史安装/回滚包，不是通用安装器。已经部署，不得直接重跑 install。私有配置、令牌、证书私钥、二进制转移包及 signed URL 不在仓库。

生产行为、使用方式、验收表和限制见 [运行说明](../../docs/vps-bond-proxy-20261007.md)。源码位于 `tools/bond-proxy/`，Router init/path helper 位于 `candidate/`；VPS queue/service 与两端 install/rollback 脚本在本目录。

13:12 面板选联通专线。首版 TLS 后 MPTCP fallback；15 分钟 VPS 自动回滚在 13:33 生效，Router 首版 nohup 在 BusyBox 不存在，未建立有效 guard。13:41:55 人工执行首版 Router 专用回滚后，改为忽略 HUP 的子 shell 并确认存活。VPS v2 13:38:09、Router v2 13:41:59 安装，双方 30 分钟保护；TLS 前固定标识交换及 TLS 后 MPTCP 检查解决 fallback，随后真实三子流下载验收。13:49 关闭 benchmark；14:02 后确认服务、配置 SHA 及三路 HTTPS，取消 v2 双方自动回滚保护。无校园认证、DHCP、无线或整机重启操作。

构建使用 Go 1.27.1、CGO_ENABLED=0，Linux ARM64/AMD64，仅标准库：

```text
Router: 6095008 bytes
2765c12133d08a791b53fc017bb8f853ac71f60e23ba0492889f3f8a4ec36ce6
VPS: 6570144 bytes
d8627d14b6c6fac856a425d7709f3bdf26cdb6ac044a5130a18bce94dcd8b0c9
```

运行配置为 `/etc/scut-bond/client.json`（Router）、`server.json`（VPS），权限 600；目录 700，禁止打印或上传。VPS private key 不离开服务器。生产 `benchmark=false`，需真实安装时自行生成双方相同高熵令牌和证书，不能使用文档占位值。迁移到其他机器需重新核对 SSH、qdisc、私有路由、端口、内核 MPTCP、LAN 和无线接口，不能套用旧基线。

回滚入口为两端 `/root/scut-bond-backup-20261007-v2/rollback.sh`。保留备份和部署的生产文件；清理的是临时 stage、转移包、签名 URL 与测试载荷。面板线路必须另行手动恢复，当前有意保持联通专线。

`evidence/` 为非敏感逐秒验收日志和流量估算，包括被排除的 TUN 对照及两次全文件代理结果；全部真实下载完整校验，不把局部速度当成全程平均。Go race tests 已通过，未实测整机重启或长期故障切换。现有其他未提交文件保持原状，未 commit/push。
