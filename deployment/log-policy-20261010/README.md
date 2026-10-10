# 2026-10-10 日志等级与 Native 清理修复

14:07 部署；14:09 补充开机校时后的时钟基准刷新；14:11 验证并确认保护。
用户要求修复正常 Mac 睡眠/维护、正常启动及无线清理产生的误告警。
本目录的安装/回滚脚本绑定本次基线，不能重复安装或当成通用部署器。

## 已部署行为

- `/sbin/logread` 改指向 `/usr/bin/scut-logread`，静态 ARM64 helper 在
  `tools/log-policy.c`；原生 `/usr/libexec/logread-ubox` 和 logd/ubus 原始
  流保持不变。`logread --raw` 直接调用原生程序，远程 syslog 模式也透传。
- 正常 cron 启动行改为 info；明确成功的 PIO 文件更新改为 info。
  LAN 失去 carrier 后 5 秒内、与配置 ULA 匹配的 stale，以及它后
  15 秒内同一前缀的 renew 改为 info。无相应链路事件、陌生/公网前缀、
  超过观察窗口及真正写入失败保留原等级。
- 仅 UBI block 启动参数与 `/rom` squashfs 实际挂载均成立、内核
  启动 10 秒内的精确 rootfs mtdsplit 提示改为 info。其他挂载、I/O、
  UBIFS 或 panic 错误保留。procd 的精确信号 1 只在 120 秒启动窗口
  改为 notice，晚期重复及其他信号保留 err；未定位信号发送者。
- Native 候选/关闭窗口中的精确不支持命令改为 debug。共享控制目录的
  精确 rmdir 权限拒绝只有在接口移除与仍存活的共享控制 socket 可证实，
  或旧 Native 接口已消失的关闭事务中，才改为 info。没有放宽权限。
- `native-best disable_radio()` 记录 ifdown/wifi down 返回码，并在
  至多 12 轮中确认 WAN up=false、旧接口已消失或明确 Not connected。
  命令非零但状态符合要求可继续；未知/仍在线状态保留失败并走原来的
  先释放候选再恢复旧线路逻辑，不能伪报切换成功。
- LuCI 系统日志默认用既有 ACL 允许的 syslog-wrapper 读取最近 1000
  行常规日志；原有设施、等级、文本筛选保留。按钮“查看原始记录”恢复
  原有 ubus/RAM 日志视图，“返回常规日志”回到分类视图。没有增加 ACL。

## 原始记录与容量

`/etc/scut-logs/system.log` 是分类视图；`raw.log` 保留原文原等级。
各自最多约 2 MiB 活动文件加 2 MiB `.old`，单行可能略超阈值。
每条先同步原始文件，再写分类文件，写入失败明确报错。
四份启动前尾部归档优先取 raw（缺失时兼容旧 system 文件），共约
4 MiB。常规轮转加启动归档约 12 MiB；一次性备份不计入此预算。
目录权限 700，文件 600；没有读取/复制认证配置内容或记录 Portal 原响应。

查看：

```sh
logread                 # 最近 RAM 记录的分类视图
logread --raw            # 原始 RAM 记录
tail /etc/scut-logs/system.log
tail /etc/scut-logs/raw.log
```

## 验证与限制

- 225 组完整隔离回归在真实路由器 BusyBox ash 通过，其中新增 3 组
  覆盖成功清理、失败及未知状态；没有真实认证/切换。
- 42 项 ARM64 C 分类用例、18 项流处理检查（raw、轮转、透传参数、
  文件权限、写入失败及 TERM 后子进程/PID 清理）通过。
- 29 项隔离日志归档/路由恢复检查通过，其中新增 raw 归档优先检查。
- 10 项前端 mock 检查通过，也用设备实际 LuCI Class/super 实现运行，
  包括原始/常规按钮切换。未使用真实登录的浏览器做页面验收；当前
  可用浏览器没有路由器登录会话。已校验部署 JS 与页面读取命令。
- 实际历史 raw/system 均 5990 行，157 条正常 RFC9096 原始 warn 对应
  157 条分类 info；两条启动 signal 1 已变为 notice，已确认的启动
  mtdsplit 为 info，07:40 清理记录按相应规则分类，未删除历史消息。
- 有线、Native、USB 分别绑定 HTTPS HEAD，均 200，耗时约
  105/127/117ms。单有线默认、三路 1:1:1 路由、配置/会话/额度哈希
  保持；boot ID 与 logd PID 1622 未变。只替换文件 follower，无整机
  重启、重新认证、无线切换、macOS 电源设置变更。
- 自然发生的新切换、下一次 Mac 睡眠、下一次冷启动仍待观察；这些
  回归不证明整机重启的根因已解决。

备份 `/root/scut-log-policy-backup-20261010`（700），含原脚本、链接
目标、原日志与 follower 交接期间 RAM 副本。保护已确认。专用回滚：

```sh
sh /root/scut-log-policy-backup-20261010/rollback.sh
```

回滚只恢复本次脚本、链接及页面，保留收集的原始证据；不会认证、
修改网络配置或重启设备。不得用早期广范围回滚撤销本次修改。

复现构建（Zig 0.15.2，本地工具路径见本次操作记录）：

```sh
zig cc -target aarch64-linux-musl -static -Os -Wall -Wextra -Werror \
  tools/log-policy.c -o scut-logread-policy
```
