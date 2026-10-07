# 新 VPS 三路单连接代理（2026-10-07 已部署）

现已提供 LAN HTTP/HTTPS CONNECT/SOCKS5 代理 `192.168.1.1:1088`。新 VPS 保持面板“联通专线”，IPv4 出口为 `58.252.223.164`；香港和 sglg 没有参与此生产路径。实现单连接聚合，但 **300Mbps 尚未达到**。现有三路各约50Mbps的证据对应约150Mbps聚合容量。19:05生产已改为每代理socket BBR、有线子流45Mbit、两无线50Mbit。固定CDN IP两次约一分钟达到123.62/124.38Mbps，最低约五秒91.41/110.29Mbps。正常域名模式发现CDN .18供数不足后，加入仅在当前DNS答案有效时优先.17的配置；19:46真实域名900MiB单连接58.88秒完成，全程128.23Mbps、最低约五秒112.17Mbps、已知完整哈希一致。19:53:32最终确认此版本并解除自动回滚；本次约一分钟样本达标，其他时段/CDN域名及长期稳定尚未证明。详见[最新入口/出口与生产验收](../deployment/ingress-20261007/README.md)。

## 路径与使用

```text
本机一个 HTTP/TCP 下载
  → 路由器 LAN 192.168.1.1:1088
  → 一个认证 TLS 1.3 / MPTCP 连接，三条校园 WAN 子流
  → 新 VPS 58.252.223.164:57501
  → 一个普通 TCP / HTTPS 连接到 115 CDN
```

115 看到的是 VPS 联通出口，取直链时 IP 与下载 IP 不同仍可能被提供方拒绝。保留原直链的完整 User-Agent。代理没有拆文件、并发 Range 或重组；CDN HTTPS 从客户端到 CDN 保持证书验证。对 HTTPS，VPS 转发加密字节，不能读取 URL 的查询参数。

下载器选择 HTTP 代理 `http://192.168.1.1:1088`，或 SOCKS5 `socks5h://192.168.1.1:1088`，并将下载线程数设为 1。无需修改 Mac 全局代理。已有 TUN 可能影响直连对照，需要显式绑定物理接口；LAN 代理请求应直达路由器。

本机系统 curl / LibreSSL 在新文件 CDN 握手失败；本机 Python / OpenSSL 3.6.4 已通过同 CDN 验证。提供标准库单请求下载入口 [bond-download.py](../tools/bond-download.py)。把完整直链和 User-Agent 分别保存在权限 600 的纯文本文件，避免签名 URL 出现在进程参数和历史记录：

```sh
python3 tools/bond-download.py \
  --url-file /private/tmp/url.txt \
  --user-agent-file /private/tmp/ua.txt \
  --output /private/tmp/download.mkv \
  --max-bytes 545507548
```

`--max-bytes` 应按实际文件大小设置；验证开头 1KiB 可加 `--range-bytes 1024 --max-bytes 1024` 并使用新输出路径。脚本不重试、不跟随重定向、不并发，校验证书及响应长度，成功输出字节数、速度和 SHA-256；失败保留 `.part`，错误不打印直链。这个新文件验证脚本已实际成功下载 1KiB；545MB 同 IP 公平对照使用专门测试客户端。

## 实际验收

完整文件为 545,507,548 字节。绑定 en0、相同 User-Agent、相同 CDN IPv4 `120.222.194.36`、同一 Python/OpenSSL 实现，顺序测试，没有互相重叠。速度包含连接和首字节等待：

| 测试 | 数据量 | 用时 | 全程平均 |
|---|---:|---:|---:|
| 直连物理接口 | 545,507,548 B | 94.918 s | 45.977 Mbps |
| 三路代理第 1 次 | 545,507,548 B | 39.293 s | 111.063 Mbps |
| 三路代理第 2 次 | 545,507,548 B | 49.271 s | 88.573 Mbps |
| 合成数据单连接 | 512 MiB | 30.832 s | 139.304 Mbps |
| 原 115 文件直连 | 64 MiB | 11.210 s | 47.893 Mbps |
| 原 115 文件三路代理 | 64 MiB | 4.434 s | 121.092 Mbps |

545MB 三组均 HTTP 206、`Content-Range: bytes 0-545507547/545507548`，完整 SHA-256 一致：

```text
3ed39f415584ce270050d907ca404177f1ae333f770101f8d117ed1cacc9ab1f
```

第一组代理多数时段 138–140Mbps，中段跌落使全程均值降至 111Mbps；第二组进一步波动，不能把局部峰值写成稳定速度。第二组回落时 VPS 上游 CDN socket 的 Recv-Q 仍有约 4.4–4.6MiB，同时 MPTCP 有重传，支持瓶颈在 VPS→校园路由器这一段；无法仅凭这些计数定位运营商整形、无线丢包或子流乱序的具体责任。

VPS `ss -Mni` 在真实下载中确认 `subflows:2 / subflows_total:3`，无 fallback；专用 FQ 队列确认三个 throttled flows。第一次 545MB 过程中三条 TCP delivery rate 约 49.7–51.4Mbps。512MiB 验收时路由器 Go RSS 约 7.5MiB、最低 MemAvailable 约 122MiB，未发生本轮重启。资源样本不能证明长期稳定。

早先未绑定 IP_BOUND_IF 的大文件“直连”误经 utun4，完整传输了同等数据，**不计入速度对照，仍计入流量**。原系统 curl 握手失败/超时样本也不计入性能结果。保留两次代理的全部逐秒结果，不选择性只呈现较快的一组。

## 首次部署参数与保留范围（最新覆盖见上方记录）

- Router：Go 静态 ARM64 程序，procd `scut-bond` 的 paths/proxy 两实例；最大两个 LAN 客户端，仅接受 `192.168.1.0/24`，绑定 `192.168.1.1`，GOMEMLIMIT=24MiB、GOGC=50。
- VPS：Go 静态 AMD64 程序，systemd `scut-bond`，非登录专用用户 scutbond；MemoryMax=128MiB，仅为每 socket 强制缓冲保留 CAP_NET_ADMIN。监听 57501，认证令牌只在两端私有配置中。私钥只在 VPS，路由器仅持有公开证书。
- 传输：保持全局 CUBIC，router receive / VPS send 每 socket 强制 4MiB；MPTCP limits 未改，允许两个附加子流。
- VPS ens18：root prio 分类，只有 IPv4 TCP 源端口 57501 进入 FQ，quantum/initial_quantum 1448、每流 maxrate 50Mbit；其余流量 fq_codel。不是把整块网卡限到 50Mbps。
- Router 路径：每 20 秒读取既有健康表 103，为 VPS 单个地址维护表 201–203、优先级 80–82 的源地址及目标地址规则；附加 endpoint 202/203。保留 pref103 的 `iif br-lan` 和三路等权，脚本不做认证、扫描、DHCP 或无线操作。
- TLS 前先交换固定公开 8 字节标识，再进行标准 TLS 1.3；此顺序解决了本环境初版 TLS 后退回普通 TCP 的兼容问题。连接在 TLS 后再次检查 MPTCP，fallback 会拒绝。没有关闭证书验证、降低 TLS 版本或改动标准密码套件。
- 目标只允许公网 IPv4 HTTP/HTTPS 端口 80/443，拒绝私网、保留地址和含私网结果的 DNS；错误令牌、私网目标、不受信证书拒绝行为已实际验证。

benchmark **已关闭**，512MiB 发生器只在验收期间开启。生产没有自动测速任务。两端服务已启用开机启动，本轮已重启代理服务验证运行；实际整机重启、WAN 故障迁移、长期播放、夜间运行尚未验证。路径 helper 的 mock 故障矩阵尚未覆盖，不将 Go 单元测试当成该部分生产故障证明。

证书有效期一年，续期需同步路由器信任证书。运营商线路或公网入口改变时，需一起更新 client/server endpoint、路径 helper 与回滚中的目标地址；不能只改面板。MPTCP endpoints 为内核全局状态，今后添加其他 MPTCP 应用需检查冲突。

## 检查和回滚

```sh
# Router
/etc/init.d/scut-bond status
ip route show table 103
ip mptcp endpoint show
sha256sum -c /root/scut-bond-backup-20261007-v2/preserved.sha256

# VPS
systemctl status scut-bond scut-bond-queue
ss -Mni
tc -s qdisc show dev ens18
```

本轮专用备份位于两端 `/root/scut-bond-backup-20261007-v2`，权限 700；旧历史广范围回滚不能用于此代理。两端临时自动回滚保护在真实验收及原配置校验后已撤销。

需要撤销此部署时，先分别在 Router 和 VPS 执行：

```sh
sh /root/scut-bond-backup-20261007-v2/rollback.sh
```

它只移除本轮代理、专用路径与 VPS 分类队列，保留校园服务和配置。若需要连面板运营商选择也回到试验前状态，手动切回“联通家宽”；脚本不能恢复供应商面板设置，家宽原指定 IPv4 端口不可达。此次实现是有意保持联通专线。

## 流量与验证边界

用户追加 5GB，累计上限 13GB。沿用上一阶段保守合并 7,839,569,206B，再加新 VPS NIC TX+RX 增量 3,345,512,953B、两次本机直连及原 64MiB 直连 1,158,123,960B，并预留 60MB 直连协议开销/小请求，共约 **12.403GB**，低于上限。误走 TUN 的下载计入两次本机直连；VPS 转发同时统计收和发。本轮未再使用旧 VPS/HK/sglg。

Go race 单元回归通过；shell 语法检查通过；真实 HTTP CONNECT、普通 HTTP、SOCKS5、115 内容及认证拒绝已验证。未安装依赖包，未提交或推送 Git。原配置/三份校园会话 SHA 校验保持一致，三路绑定 HTTPS HEAD 最终均 200。

源码、回滚脚本和非敏感验收日志见 [本轮部署目录](../deployment/bond-20261007/README.md)。令牌、带签名直链、真实私有配置与转移包不进入版本库。
