# SCUT-MultiWAN

华南理工校园网 OpenWrt 双无线 WAN 维护脚本：一条原生 Qualcomm 无线链路，加一条 USB MT7921AU 无线链路，通过 ECMP 分担 LAN 连接。

已在 Linksys MX4200 V1、OpenWrt 25.12.5、Linux 6.12.94、BusyBox ash 上部署验证。脚本依赖该设备现有的无线、网络及防火墙配置，不是通用一键安装包。

## 主要行为

- Native 使用 radio0/phy0 或 radio2/phy2；USB 使用 radio3/phy3。保留原生 MAC，不固定 BSSID。
- 原生 ath11k 速率维护只作用于 phy0/phy2，限制 MCS7/MCS9；新关联前 15 秒暂不依据 RX 降档/升档，仍处理真实网关丢包和 TX failure；USB 保留正常速率控制。
- Portal 登录/注销通过全局文件锁串行化。持久会话记录保留超时后的不确定状态，未确认释放旧会话时不继续登录。
- 仅明确重定向到校园 Portal 时才自动认证；普通公网超时不会触发盲目登录。
- 路由表 103、优先级 103，规则为 `iif br-lan lookup 103`。双路健康时权重 1:1；单路故障时切换至健康链路。
- 普通工作日及官方补班周末在 GMT+8 的 00:06–07:00 静默；普通休息周末和官方放假日采用午夜保护及有限恢复。未知年度默认静默。
- 夜间不做完整扫描、Native 优化切换或无线重启；每天 07:00 强制 Native 检查，USB/ECMP 分别在 07:01/07:02 错峰执行。
- 每月 1 日 12:13 从中国政府网更新当年与次年清单；下载或校验失败保留旧清单。

ECMP 按连接分担流量，单个下载连接不等于两路带宽相加。

## 文件

| 路径 | 内容 |
| --- | --- |
| `candidate/` | 维护脚本及热插拔钩子，目录结构对应路由器根目录 |
| `tests/build_router_tests.py` | 生成隔离的 BusyBox ash 回归测试 |
| `deployment/` | 历史稳定性修复及 `holiday-20261005/` 夜间策略部署/回滚记录 |
| `examples/campus-portal.conf.example` | 不含真实账号密码的配置示例 |
| `OPERATIONS.txt` | 本次修复与验证记录 |

`candidate/usr/bin` 包含四个 Portal 入口包装脚本；它们在原路由器上已存在，所以没有列入本次 13 个替换文件清单。

## 使用前提

需要 `iw`、`ubus`、`uci`、`curl`、`flock`、完整 iproute2、`sysctl` 和 BusyBox ash。Native 对应 `wan1/wan2`、无线节 `wifinet3/wifinet4`，USB 对应 `usbwan`。实际名称不同需先调整脚本映射；同时确认 WAN 防火墙 NAT、DHCP、DNS 和校园认证状态。

真实认证配置只保存在路由器 `/etc/campus-portal.conf`，权限应为 `600`。不要把账号、密码、运行日志或原始备份提交到仓库。

会话记录位于 `/etc/scut-multiwan/native.session` 和 `usb.session`。首次部署需要从已经验证在线的当前链路建立记录；记录缺失或损坏时脚本会拒绝继续认证，不要通过删除记录绕过保护。

## 测试

在开发机器上生成测试包：

```sh
python3 tests/build_router_tests.py
```

当前夜间策略在 2026-10-05 23:20（GMT+8）部署，81 组隔离 mock 回归通过。定时表参考见 `examples/crontab.quiet-window.example`。真实午夜恢复及 07:00 晨间行为仍需观察。

随后将 `tests/router-suite.tar` 复制到目标 OpenWrt 的 `/tmp`，在确认 `/tmp/scut-multiwan-tests-holidays-20261005` 没有其他用途后执行：

```sh
mkdir -p /tmp/scut-multiwan-tests-holidays-20261005
tar -xf /tmp/router-suite.tar -C /tmp/scut-multiwan-tests-holidays-20261005
sh /tmp/scut-multiwan-tests-holidays-20261005/run.sh
```

测试将网络、无线、Portal 和路由命令替换为 mock，并重写脚本路径以隔离到该临时目录。2026-10-05 在目标路由器实际 BusyBox ash 上通过 81 组回归；这不代表真实认证失败、漫游或夜间运行已经全部实测。不要在 Mac 上直接运行生成的 `run.sh`，它依赖 OpenWrt/Linux 环境。

## 部署与回滚

`deployment/install.sh` 和 `rollback.sh` 是本次生产修复记录，绑定 `/root/scut-multiwan-backup-20261005-2005` 和 `/tmp/scut-multiwan-deploy`，并要求原脚本与备份一致。**不要在另一台路由器上直接执行，也不要在已修复的路由器上重复执行。**

新部署须先备份目标设备、调整设备映射及部署路径，并重新生成校验清单。替换前在 `/tmp` 检查非空文件、shell 语法和关键逻辑，再复制到目标文件系统的同级临时文件，通过重命名替换；保留可执行的回滚入口。

本仓库不包含原始备份、真实网络配置、认证配置、会话记录或 SSH 密码。原路由器上的回滚路径见 `OPERATIONS.txt`。

## 节假日与周末夜间联网

已部署普通休息周末判断、官方放假/补班清单、00:06–00:25 保护、00:25 后有限认证恢复和按日期手动覆盖。每条链路每夜最多两次恢复认证、间隔至少 15 分钟；登录后必须通过公网 HTTPS 验证。接口或无线关联消失时留待 07:00 修复，保留其他健康链路。

2026 年清单已从官方通知取得；2027 年通知尚未检索到，未知年度默认静默。月度更新不保证发现另发的临时通知。实际规则、手动处理和限制见 [夜间联网策略](docs/overnight-policy.md)，部署证据和专用回滚入口见 `OPERATIONS.txt`。
