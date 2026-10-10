# 2026-10-10 日志报告复核

时间：13:42–13:46 GMT+8。设备与 Mac 均仅只读检查；没有认证、注销、
路由修改、服务重启或系统电源设置变更。仓库仅补充诊断记录。

## 当前状态与上次修复的实际恢复证据

boot ID 仍为 `d1c57078-6dca-4b07-a9e0-b8b23b0c607e`，13:42 uptime
49508 秒，与昨晚 23:57:21 启动一致。system.log 670901 字节，单有线
LAN ready=true，表 103 为 Native/USB/wan 三路 1:1:1。

07:11:37 有线晨间 attempt=1；07:11:41 新版 discovery round=1 明确
确认旧会话释放，07:11:44 完成 UDP 心跳，07:11:46 公网确认成功。
路由复核前两次 deferred/code=0，对应保留的恢复确认观察期，第三次
07:12:17 ready/attempts=3，实际三路路由恢复。不是新的整机冷启动，
不能据此宣称新 S11 日志归档已通过真实重启验证。

截至 13:44，807 次采样中最低可用内存 94848 KiB（约 92.6 MiB），
最高温度 57.2℃；1 分钟负载最高 0.80 出现在本轮检查期间的 13:42:01，
不能用它否定原报告截至 13:38 的 0.39。所查日志未命中 OOM/panic/
ath11k fatal/crash、I/O error 或 UBIFS error。

## 157 条 odhcpd 记录的来源

实际计数为 stale 39、renew 39、piofile updated 79；与 LAN2 的
39 次物理 carrier down 对应。内核计数 carrier_changes=79，
up_count=40、down_count=39；WAN 只有初始一次 link up，无 down。
日志先出现 LAN2 PHY down，随后 br-lan link down、ULA stale，
链路几秒后恢复并 renew。这不是普通 WAN DHCPv6 续租的证据。

路由器 LAN 邻居 MAC 与本机 en0 一致，本机默认到路由器也使用 en0。
把这 39 个 down 时间与 Mac `pmset -g log` 当日 Sleep/DarkWake/Wake
记录逐一比较，39/39 位于最近电源事件前后 12 秒内，无未匹配项。
例如 13:14:08 Mac DarkWake 与 LAN2 down 同秒，之后链路以 1000Mbps
恢复；12:58:41 的 down 紧随 Mac 回到睡眠，恢复时协商 100Mbps。
这是 Mac 睡眠/维护唤醒引发链路重协商的强相关证据，不能据此认定
路由器端口损坏；本轮没有改 Mac 省电设置。

[odhcpd 上游前缀处理](https://github.com/openwrt/odhcpd/blob/master/src/router.c)
分别对 stale 与 renew 记录日志；
[链路事件处理](https://github.com/openwrt/odhcpd/blob/master/src/netlink.c)
会按接口 RUNNING 状态刷新服务。因此不建议仅为这组日志修改 DHCPv6
或降低日志等级掩盖链路事件。

## Native 清理告警与可改善的源码点

07:40 切换时出现不支持命令、wpa_supplicant rmdir 权限拒绝，以及
wan1 停止中 notify_proto 权限拒绝。07:40:23 候选关联/DHCP/速率就绪，
07:40:33 确认释放旧会话，07:40:38 完成切换，watchdog 返回成功。
当前 phy0-sta0 已消失，无临时扫描接口，wpa_supplicant 留有 global、
phy2-sta0、phy3-sta0 三个控制入口。两无线在同 AP，信号约 -40/-42dBm，
40MHz HE；没有发现本次清理导致旧接口遗留或当前无线失效。

值得做的低优先级稳健性改进：`native-best` 的 `disable_radio()`
没有检查 ifdown/wifi down 的返回码，函数最终返回 uci commit 的
状态；`finish_switch()` 据此继续验证新线路。应在有界等待中核实旧
WAN 确实停止、旧 Native 关联确实消失，失败记录固定阶段并安全退出，
避免未来真正的清理失败被最后的成功命令掩盖。不能只依据某个命令
返回码中止已完成的正确清理；应以实际接口状态为准。本轮未修改代码。

## 启动告警

`mtdsplit` 报未在原始 rootfs MTD 找到 squashfs，但随后内核从 UBI
rootfs 创建 ubiblock0_0，成功挂载 squashfs；UBIFS journal recovery
completed，overlay 正常读写。没有因此修复分区或文件系统的依据。

两条 procd signal 1 只在启动期出现，未找到本项目脚本主动向 procd
发送 HUP 的来源，后续没有重复或服务管理异常。不知道这两条信号的
确切发送者，不应归因其导致此前重启。

结论：当前没有必须立即修复的运行故障；Native 清理后置条件值得
小范围补强。IPv6 告警已找到 Mac 电源行为的对应证据，当前不需据此
改动路由器。整机重启原因仍未定位，持久日志继续提供自然观察证据。

## 用户授权后的后续修复

以上为 13:42 只读审计结论。用户随后要求全部修复正常场景的误告警，
14:07–14:11 已部署日志展示等级分类、独立原始副本、LuCI 原始查看
入口及 Native 清理后置条件。没有改变 Mac 电源设置、放宽无线权限、
刷机或重启设备。当前容量和验证边界以
[本次部署记录](../deployment/log-policy-20261010/README.md) 为准。
