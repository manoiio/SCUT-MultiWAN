# 2026-10-07 临时 IPv6 实验

本目录保存本次实验的历史脚本和非敏感证据，不是通用部署器。实验已清理，生产仍使用新 VPS 的 IPv4 代理。结论、临时接口、精确清理边界和流量额度见 `../../docs/vps-ipv6-test-20261007.md`。

`prepare-router-test.sh` / `prepare-vps-test.sh` 只记录首次启动阶段；后续测试调整了服务并发、预算、运行时间、BBR 和服务器 IPv6。依赖已经准备的临时二进制及私有生产配置，不能直接重跑。`router-cleanup.sh` 绑定本次真实地址、端点 ID 和路由表，只清理本次临时状态。生产路由器曾通过 `/root/scut-ipv6-backup-20261007/cleanup.sh` 执行，守卫已取消。

`evidence/*queue-change-excluded.log` 为中途调整队列后终止的排除样本，只计流量。`pair-result.json` 使用两个独立地址同时接收、按共同时间窗计算合计吞吐；三个启动错开的 parallel 日志不能将全程均值直接相加。

本目录没有复制代理 token、私有配置、证书私钥、面板密码或签名下载 URL。
