# 2026-10-07 LAN 三模式部署记录

已按用户要求部署 LuCI 三按钮及全协议 IP 隧道，并按用户选择持久保存单有线出口。操作见 [LAN 使用说明](../../docs/lan-egress-modes.md)。这些脚本绑定本轮设备基线，**不是通用安装器，不要重复运行安装脚本**。

## 设备改动

路由器新增 mode/watch、DNS/TUN procd 服务、hotplug、两个 allowlist RPC 包装入口及 LuCI 菜单页面。新增 fw4 TUN 区域及 LAN 转发，`dhcp.lan.ra_default=1`，未重启原 dnsmasq、认证或无线。专用规则 90/91/94、表 106 和自有 nft 表控制 LAN；原表 103、路径表 201–203及原认证配置/会话保持。

新 VPS 新增独立 57502 服务、TUN、受限转发/NAT、IPv4/IPv6 forwarding 和 ens18 accept_ra=2，并复用已确认的有线 45 / 无线 50 队列；原 57501 程序和配置未替换。路由器原 `scut-bond` 客户端仅增加模式跟随、直接模式的路由标记和 SIGHUP 关闭旧连接；切换按钮不重启路径 helper。

路由器原先缺少 kmod-tun，安装匹配 `6.12.94-r1` 的官方发布包。该下载包没有 APK 签名块，默认安装拒绝 UNTRUSTED；核对官方 HTTPS sha256sums 后，仅对本地指定文件使用 `apk add --no-network --allow-untrusted`。SHA-256 为 `d3dc39ebeab829483a8f2e3d834b9f38096f4195f4203908d4cf351514db0f9c`。未改全局信任设置。

首次 TUN 实现先注册 Go fd 再 TUNSETIFF，造成已握手但后续收包不醒；修为 ioctl 之后再创建 os.File，隔离 namespace 延迟收包检查及真实 LAN 隧道验证通过。早期失败样本不计为通过。Cloudflare HTTPS 在 VPS 直连也超时，TCP 对照改为已确认可达的相同 Bilibili/IP 查询端点。

## 备份和确认

| 主机/范围 | 设备上的专用回滚 | 确认时间 GMT+8 |
| --- | --- | --- |
| Router：新 LAN 控制、防火墙/DHCP | `sh /root/scut-lan-modes-backup-20261007/rollback.sh` | 21:14:00 |
| Router：1088 模式跟随 | `sh /root/scut-lan-proxy-backup-20261007/rollback.sh` | 21:29:04 |
| VPS：独立 IP 隧道、转发及两项 tc filter | `sh /root/scut-lan-modes-backup-20261007/rollback.sh` | 21:11:55 |

备份目录均权限 700。三个自动回滚保护已在验证后确认并解除。Router 基础回滚会先调用 1088 专用回滚（如存在），再恢复原三网策略及原防火墙/DHCP；VPS 回滚只删除此次服务/TUN/自有 NAT 和 filter，恢复已备份 sysctl，不改原 Web 代理。不要使用早期广范围回滚撤销本次部署。

## 验证和计量

详细最终三模式物理 LAN + 显式代理结果见 [acceptance.json](evidence/acceptance.json)，其他校验摘要见 [verification.json](evidence/verification.json)。Go race 通过，8 项 mock 在真实路由器 BusyBox ash 上通过；mock 不执行真实 ip/nft/服务。测试生成器 `tests/build_lan_mode_tests.py` 生成独立 tar，须在 Linux/OpenWrt `/tmp/scut-lan-tests-v2` 解包运行，不能直接运行 cases 文件。

21:30:30 新 VPS RX 24,195,187,638 / TX 32,856,004,815 字节。沿用全部历史及控制/构建预留，保守累计 61,625,491,783 / 62,000,000,000 字节，余 374,508,217 字节。本轮未做大文件测速。最后为 wired、ready=true，服务恢复已实测；整机冷启动、实际 IPv6 LAN 主机和长期 IP 隧道吞吐未验收。已有无线固件问题的历史修复未被本次部署替换，也未据小流量检查宣称固件 fatal 消失。

本地源代码、文档和部署证据已更新；未提交或推送 Git。
