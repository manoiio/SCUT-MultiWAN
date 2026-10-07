# 2026-10-07 恢复修复部署记录

此安装器绑定 `baseline.sha256`，不是通用安装器，不得重复运行。
`install.sh` 已于 08:48:25 部署两个脚本与 DHCP DNS 选项；
`install-wired.sh` 已于 08:52:06 部署有线同会话挑战等待修复。
本地不包含实际 DHCP 配置备份、账号或生成的二进制。

备份与回滚仅在路由器：

* `/root/scut-multiwan-recovery-backup-20261007/rollback.sh`
* `/root/scut-multiwan-recovery-wired-backup-20261007/rollback.sh`

两个目录权限 700。代码回滚不会恢复旧无线关联或会话记录。
有线回滚须由停止路径确认释放，不能删除会话记录绕过。
实际回滚尚未执行；两份备份原始哈希与 rollback 语法已经验证。

验证包括：173 组 BusyBox ash mock、最终 9 组恢复专项、25 项有线协议
mock、独立真实 DNS 查询、自动 radio0→radio2 切换、真实 35 秒 Portal
锁等待后有线同一 PID/starttime 完成心跳、三路 HTTPS 与 1:1:1 路由。
最终生产哈希见 `final-installed.sha256`。详细限制见
`../../docs/recovery-fixes-20261007.md`，操作证据见 `../../OPERATIONS.txt`。

08:56:35 `update.sh` 完成最终日志/退避清理修订；原始备份不变，
回滚使用的 installed.sha256 已更新。08:57 再次自动选优保留 radio2。
