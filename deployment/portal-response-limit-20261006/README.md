# Portal 响应上限部署记录（已执行）

只适用于 2026-10-06 本轮核对的四个生产 `.impl` 哈希。用户确认接受“未来超过 1 MiB 的合法响应会被拒绝”这一边界，批准部署；03:11:49 已安装，03:12:27 后续核验通过。不得重复执行。

- `baseline.sha256`：部署前四个入口，取当前 HEAD，已与生产核对一致。
- `candidate.sha256`：本地候选四文件，检查包内 `files/`。
- `installed.sha256`：候选安装后的四文件校验值。
- `final-installed.sha256`：部署后已在设备核验的同一四文件清单。
- `install.sh`：固定暂存目录 `/tmp/scut-portal-response-limit-20261006`；先校验非空、字节数、哈希、语法及关键逻辑，再获取真实 Portal 锁，核对生产基线、备份和逐文件原子替换。出现可捕获错误恢复四个原文件；不控制服务或发送认证请求。
- `rollback.sh`：仅恢复专用备份的四个脚本，同样持有真实 Portal 锁；不改变配置、会话、额度、路由或有线引擎。

专用备份为 `/root/scut-multiwan-portal-limit-backup-20261006`（700）；手动回滚入口为 `sh /root/scut-multiwan-portal-limit-backup-20261006/rollback.sh`。回滚只恢复四个脚本，实际回滚未执行。不要重跑本安装器，也不要使用历史广范围回滚。设备端 `preserved.sha256` 验证配置、认证配置、cron、三个会话和三个额度未变，不包含配置原文，也不下载到本机。

本轮将 installer/rollback/三个清单与四个 candidate 文件按 `files/usr/bin/...` 打包到专属暂存目录，包不包含真实凭据或配置。首次预检因 BusyBox flock 不支持 `-w` 在任何备份/替换前停止；核对原哈希后改用 `flock -n` 有界等待并重检语法，最终成功。包装脚本记录对应此设备/基线，不是通用安装器。

139 组 BusyBox mock、7 项实际 curl 合成 HTTP 结果和无法保证绝对零影响的边界见 [实现说明](../../docs/portal-response-limit-20261006.md)。
