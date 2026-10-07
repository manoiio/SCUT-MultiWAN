# 2026-10-07 有线重启恢复部署记录

专用于本次设备与基线，不是重复执行的安装器。

备份目录 `/root/scut-wired-reboot-backup-20261007` 保存原二进制、原守卫、保留配置清单、最终 installed.sha256 与 rollback.sh。先以诊断版本确认退出 75 的阶段，再验证候选的无网络协议测试。真实旧会话通过定向 Logoff 确认释放后恢复登录。最终修订在支持的服务停止流程确认注销后安装。

最终文件：`/usr/bin/scutclient-wired` 与 `/usr/bin/scut-wired-gate`。源码改动见 `tools/wired-logoff.inc`、`tools/build_wired_client.py`、`tools/wired-main.c` 和对应候选守卫；验证见 `docs/wired-reboot-recovery-20261007.md` 与 OPERATIONS.txt。

回滚：`sh /root/scut-wired-reboot-backup-20261007/rollback.sh`。脚本停止服务并验证引擎锁未被占用、readiness 已移除后恢复文件，不删除会话账本。没有 Git 提交或推送。
