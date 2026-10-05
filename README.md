# SCUT-MultiWAN

华南理工校园网 OpenWrt 双无线 WAN 维护脚本：一条原生 Qualcomm 无线链路，加一条 USB MT7921AU 无线链路，通过 ECMP 分担 LAN 连接。

已在 Linksys MX4200 V1、OpenWrt 25.12.5、Linux 6.12.94、BusyBox ash 上部署验证。脚本依赖该设备现有的无线、网络及防火墙配置，不是通用一键安装包。

## 主要行为

- Native 使用 radio0/phy0 或 radio2/phy2；USB 使用 radio3/phy3。保留原生 MAC，不固定 BSSID。
- 原生 ath11k 速率维护只作用于 phy0/phy2，限制 MCS7/MCS9；USB 保留正常速率控制。
- Portal 登录/注销通过全局文件锁串行化。持久会话记录保留超时后的不确定状态，未确认释放旧会话时不继续登录。
- 仅明确重定向到校园 Portal 时才自动认证；普通公网超时不会触发盲目登录。
- 路由表 103、优先级 103，规则为 `iif br-lan lookup 103`。双路健康时权重 1:1；单路故障时切换至健康链路。
- 每日 00:06–07:29（路由器需配置 GMT+8）停止自动扫描、切换、认证、恢复与路由刷新。

ECMP 按连接分担流量，单个下载连接不等于两路带宽相加。

## 文件

| 路径 | 内容 |
| --- | --- |
| `candidate/` | 维护脚本及热插拔钩子，目录结构对应路由器根目录 |
| `tests/build_router_tests.py` | 生成隔离的 BusyBox ash 回归测试 |
| `deployment/` | 2026-10-05 这次修复的部署/回滚脚本及 13 个替换文件清单 |
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

随后将 `tests/router-suite.tar` 复制到目标 OpenWrt 的 `/tmp`，在确认 `/tmp/scut-multiwan-tests` 没有其他用途后执行：

```sh
mkdir -p /tmp/scut-multiwan-tests
tar -xf /tmp/router-suite.tar -C /tmp/scut-multiwan-tests
sh /tmp/scut-multiwan-tests/run.sh
```

测试将网络、无线、Portal 和路由命令替换为 mock，并重写脚本路径以隔离到该临时目录。2026-10-05 在目标路由器实际 BusyBox ash 上通过 38 组回归；这不代表真实认证失败、漫游或夜间运行已经全部实测。不要在 Mac 上直接运行生成的 `run.sh`，它依赖 OpenWrt/Linux 环境。

## 部署与回滚

`deployment/install.sh` 和 `rollback.sh` 是本次生产修复记录，绑定 `/root/scut-multiwan-backup-20261005-2005` 和 `/tmp/scut-multiwan-deploy`，并要求原脚本与备份一致。**不要在另一台路由器上直接执行，也不要在已修复的路由器上重复执行。**

新部署须先备份目标设备、调整设备映射及部署路径，并重新生成校验清单。替换前在 `/tmp` 检查非空文件、shell 语法和关键逻辑，再复制到目标文件系统的同级临时文件，通过重命名替换；保留可执行的回滚入口。

本仓库不包含原始备份、真实网络配置、认证配置、会话记录或 SSH 密码。原路由器上的回滚路径见 `OPERATIONS.txt`。
