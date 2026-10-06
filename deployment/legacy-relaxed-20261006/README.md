# 白天重关联放宽修订

用户明确授权，2026-10-06 13:20:09 GMT+8部署两个维护脚本。绑定13:05初版基线，不得重复安装。

取消目标公网与后备门槛，首次确认即修复；失败按1/5/15分钟退避。Native/USB每分钟串行处理，全局恢复锁覆盖整个流程。保留夜间、会话匹配和Portal互斥；helper不登录/注销/重启DHCP。

既有139组回归通过，最终28组专项及3组静默检查共31组在实际BusyBox ash通过。生产非空/字节数/语法/基线与候选哈希检查通过，以同级临时文件原子替换。配置、cron、三路会话及额度保留校验通过，六项HTTPS200，HE速率与1:1:1路由正常。

专用备份（700）：/root/scut-multiwan-legacy-relaxed-backup-20261006。
定向回滚：sh /root/scut-multiwan-legacy-relaxed-backup-20261006/rollback.sh。
仅恢复两个脚本和临时状态格式，保留实际尝试，不修改持久会话/额度。语法已查，未实际回滚。

详见docs/legacy-association-recovery-20261006.md及OPERATIONS.txt。没有人为制造生产退化，长期自然复发仍待观察；未提交或推送。
