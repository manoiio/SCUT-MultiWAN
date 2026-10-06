# SCUT-MultiWAN

华南理工校园网 OpenWrt 双无线与有线 WAN 维护：原生 Qualcomm 无线、USB MT7921AU 无线及校园有线，通过 ECMP 分担 LAN 连接。

已在 Linksys MX4200 V1、OpenWrt 25.12.5、Linux 6.12.94、BusyBox ash 上部署验证。脚本依赖该设备现有的无线、网络及防火墙配置，不是通用一键安装包。

## 主要行为

- Native 使用 radio0/phy0 或 radio2/phy2；USB 使用 radio3/phy3。保留原生 MAC，不固定 BSSID。
- 原生 ath11k 速率维护只作用于 phy0/phy2，限制 MCS7/MCS9；新关联前 15 秒暂不依据 RX 降档/升档，仍处理真实网关丢包和 TX failure；USB 保留正常速率控制。
- 白天分钟维护检查 Native/USB 的传统 `no HT` 关联；关联成熟且当前 AP 缓存宣告 HT/HE 时，首次符合条件即请求重关联，失败按 1/5/15 分钟退避并串行处理。保留会话/IP/接口匹配、Portal 锁以及所有日期的夜间禁止重关联规则；该流程不执行 Portal 认证。
- Portal 登录/注销通过全局文件锁串行化。持久会话记录保留超时后的不确定状态，未确认释放旧会话时不继续登录。
- 仅明确重定向到校园 Portal 时才自动认证；普通公网超时不会触发盲目登录。
- 路由表 103、优先级 103，规则为 `iif br-lan lookup 103`。三路健康时权重 1:1:1；故障链路移出，双无线健康时保留 1:1。
- 普通工作日及官方补班周末在 GMT+8 的 00:06–07:00 静默；普通休息周末和官方放假日采用午夜保护及有限恢复。未知年度默认静默。
- 夜间不做完整扫描、Native 优化切换或无线重启；每天 07:00 强制 Native 检查，USB/ECMP 分别在 07:01/07:02 错峰执行。
- 每月 1 日 12:13 从中国政府网更新当年与次年清单；下载或校验失败保留旧清单。

ECMP 按连接分担流量，单个下载连接不等于两路带宽相加。

2026-10-06 的只读资源检查未见轻载内存/闪存压力；用户目标为三路合计下行接近 300 Mbps，尚未完成该负载下的转发、延迟和长期内存验收。各模块存储限制、同款设备 ath11k 负载风险及优化优先级见 [资源容量评估](docs/resource-capacity-review-20261006.md)。

## 网络体验改进（已部署）

2026-10-06 新版本使用 Bilibili 主 / 京东副 HTTPS，增加白天连续 MCS 采样、延迟升档、健康路由恢复确认与探测合并、扫描失败退避、保留候选 DHCP、有线挑战锁等待及 07:00 有线启动检查。普通工作日/补班日 00:06–07:00 静默保留。113 组路由器隔离回归、19 项有线协议 mock 已通过；2026-10-06 02:12:35（GMT+8）已部署，02:13:50 真实三路验证后解除自动回滚。新版有线已完成认证、心跳及同会话挑战；临时额度已撤销，保留实际 3 次记录。性能短测、规则和限制见 [改进说明](docs/network-experience-changes-20261006.md)，上线分阶段方案见 [候选部署说明](deployment/experience-20261006/README.md)。

## 文件

2026-10-06 12:49–12:51 Native 与 USB 分别重关联后恢复至 40 MHz HE。13:05 部署白天重关联保护，13:20 放宽为首次确认即修复、失败按 1/5/15 分钟退避，并在分钟任务中串行检查两路。部署前 161 组、修订前 139 组回归，以及最终修订的 28 组专项和 3 组静默检查分别在路由器 BusyBox ash 上通过；三路连通性与保留校验通过。长期复发和实际吞吐仍待观察。触发条件、验证边界和定向回滚见 [无线关联恢复](docs/legacy-association-recovery-20261006.md)。

| 路径 | 内容 |
| --- | --- |
| `candidate/` | 维护脚本及热插拔钩子，目录结构对应路由器根目录 |
| `tests/build_router_tests.py` | 生成隔离的 BusyBox ash 回归测试 |
| `deployment/` | 稳定性、夜间策略、有线、体验改进、Portal 响应限制及 `legacy-recovery-20261006/`、`legacy-relaxed-20261006/` 部署/回滚记录 |
| `docs/` | 网络体验、资源容量、Portal 响应限制和无线关联恢复评估/实施记录 |
| `examples/campus-portal.conf.example` | 不含真实账号密码的配置示例 |
| `THIRD_PARTY_NOTICES.md`、`LICENSES/` | 第三方来源、复用范围及许可证 |
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

夜间策略在 2026-10-05 23:20（GMT+8）部署；2026-10-06 有线扩展已核对原有 81 组与 19 组有线隔离检查，另通过 14 项无真实网络操作的协议回归。定时表参考见 `examples/crontab.quiet-window.example`。真实午夜恢复及 07:00 晨间行为仍需观察。

随后将 `tests/router-suite.tar` 复制到目标 OpenWrt 的 `/tmp`，在确认 `/tmp/scut-multiwan-tests-experience-20261006` 没有其他用途后执行：

```sh
mkdir -p /tmp/scut-multiwan-tests-experience-20261006
tar -xf /tmp/router-suite.tar -C /tmp/scut-multiwan-tests-experience-20261006
sh /tmp/scut-multiwan-tests-experience-20261006/run.sh
```

测试将网络、无线、Portal 和路由命令替换为 mock，并重写脚本路径以隔离到该临时目录。当前生成包含 167 组检查；这不代表真实认证失败、漫游或夜间运行已经全部实测。不要在 Mac 上直接运行生成的 `run.sh`，它依赖 OpenWrt/Linux 环境。

四个 HTTP Portal 入口的 1 MiB 响应限制已于 2026-10-06 03:11:49（GMT+8）部署；完整响应保留原处理，超限/传输不完整保留会话保护。139 组路由器隔离检查及 7 项实际 curl 合成 HTTP 检查已通过；部署后配置/会话/额度未变、三路 HTTPS 正常，真实下一次认证仍待观察。详见 [容量限制与验证边界](docs/portal-response-limit-20261006.md)。

## 部署与回滚

`deployment/install.sh` 和 `rollback.sh` 是本次生产修复记录，绑定 `/root/scut-multiwan-backup-20261005-2005` 和 `/tmp/scut-multiwan-deploy`，并要求原脚本与备份一致。**不要在另一台路由器上直接执行，也不要在已修复的路由器上重复执行。**

新部署须先备份目标设备、调整设备映射及部署路径，并重新生成校验清单。替换前在 `/tmp` 检查非空文件、shell 语法和关键逻辑，再复制到目标文件系统的同级临时文件，通过重命名替换；保留可执行的回滚入口。

本仓库不包含原始备份、真实网络配置、认证配置、会话记录或 SSH 密码。原路由器上的回滚路径见 `OPERATIONS.txt`。

## 有线 WAN 扩展

有线使用物理 `wan`（Internet 口），按网络中心分配的信息设置静态 IPv4、网关和 DNS。用户确认账号允许两个无线会话和一个有线会话同时在线；有线已选择沿用 Native 凭据，凭据仍只留在路由器 `/etc/campus-portal.conf`。不需要学校的桌面客户端。

`tools/build_wired_client.py` 与 `tools/wired-main.c` 对开源 [scutclient](https://github.com/scutclient/scutclient) v3.1.3 做可复现的源码适配，并将适配后的上游协议实现编译进 ARM64 Linux/musl 静态程序。构建器先核对 `tools/scutclient-v3.1.3.sha256` 中的上游文件哈希，再修改 `auth.c` 并与本项目适配器一起编译。上游代码采用 AGPL-3.0；来源、改动范围及许可证副本见 [第三方来源说明](THIRD_PARTY_NOTICES.md) 和 `LICENSES/scutclient-AGPL-3.0.txt`。使用 Zig 0.15.2 交叉编译，在路由器上执行，不需要把编译器或桌面运行环境装到路由器。生成源码、二进制和含实际网络参数的部署包放在被忽略的 `work/` 或 `/private/tmp`。

```sh
python3 tools/build_wired_client.py \
  --source /path/to/fresh/scutclient-3.1.3 \
  --zig /path/to/zig \
  --output work/scutclient-wired
```

生产服务为 `/etc/init.d/scut-wired`，配置格式见 `examples/scut-wired.conf.example`。认证程序从标准输入读凭据，不在 argv 中传密码，不输出原始认证报文/服务器文本。首次登录、确认注销和已建立会话的服务器挑战均使用真实全局 Portal 锁；每次启动只尝试一次，重连由 procd 和持久守卫控制。会话内挑战不发送新的 EAPOL Start，不当作断线后的新登录。

有线夜间同样遵守现有日历和 00:06–00:25 保护；允许夜间最多两次启动认证、间隔至少 900 秒，注销不确定时停止当夜继续尝试。已有连接继续保活，普通工作日不启动认证；07:00 后不受夜间额度阻断。记录在 `/etc/scut-multiwan/wired.session` 和 `wired.night-budget`，不得删除这些记录绕过保护。

`dualwan-refresh` 可管理 Native、USB 和有线三条链路：有线须有已完成 UDP 心跳的有效进程身份、绑定接口的 HTTPS 200 和可用网关，才加入表 103。保留 `iif br-lan` 和连接哈希策略；三路健康时权重 1:1:1，两路无线独立保持 1:1；故障链路移除，全失败移除策略。认证退出触发健康路由刷新，热插拔及原有定时刷新仍保留。

`tests/wired-cases.sh` 验证路由、额度、锁及会话记录；`tests/wired-protocol.c` 对服务器挑战、重复成功报文和报文长度做无真实网络操作的协议回归。mock 和协议测试都不代表长期有线认证已通过，真实接入结果以 `OPERATIONS.txt` 最新记录为准。

`deployment/wired-20261006/` 绑定本次基线与专用备份，不是通用安装器，不得重复安装。回滚会先确认释放已有有线会话，释放不确定时拒绝删除记录或继续回滚。不会通过 Wi-Fi Portal 的 IP unbind 接口注销有线会话。

## 节假日与周末夜间联网

已部署普通休息周末判断、官方放假/补班清单、00:06–00:25 保护、00:25 后有限认证恢复和按日期手动覆盖。每条链路每夜最多两次恢复认证、间隔至少 15 分钟；登录后必须通过公网 HTTPS 验证。接口或无线关联消失时留待 07:00 修复，保留其他健康链路。

2026 年清单已从官方通知取得；2027 年通知尚未检索到，未知年度默认静默。月度更新不保证发现另发的临时通知。实际规则、手动处理和限制见 [夜间联网策略](docs/overnight-policy.md)，部署证据和专用回滚入口见 `OPERATIONS.txt`。
