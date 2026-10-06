# 2026-10-06 无线传统速率恢复

本目录是这轮修复的历史记录，不是通用安装器，不能重复安装。

临时 Native/USB 重关联脚本先后在健康后备链路、真实 Portal 锁及操作锁保护下执行。Native 12:49:57、USB 12:51:19 恢复到40 MHz HE模式；未修改配置、DHCP或认证会话。

最终161组隔离 BusyBox ash 回归通过。13:05:11 部署四个已有维护脚本及新增 helper，所有生产哈希和保留内容校验通过。详见 [修复说明](../../docs/legacy-association-recovery-20261006.md) 及 `OPERATIONS.txt`。

- 无线恢复前备份：路由器 `/root/scut-multiwan-legacy-backup-20261006`，700。
- 代码专用备份：`/root/scut-multiwan-legacy-code-backup-20261006`，700。
- 定向代码回滚：`sh /root/scut-multiwan-legacy-code-backup-20261006/rollback.sh`。
- `baseline.sha256` 是替换前四个已有文件；`candidate.sha256` 是安装的五个文件。回滚保留已恢复的关联与会话，不回退无线配置。

没有强制写入 Git、提交或推送。自然复发、长期稳定和实际吞吐尚未验收。
