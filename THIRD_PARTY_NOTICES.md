# 第三方来源与许可证

## scutclient

- 上游项目：[scutclient/scutclient](https://github.com/scutclient/scutclient)，SCUT Dr.com(X) 的 C 客户端。
- 本项目有线客户端以 scutclient v3.1.3 源码为协议引擎基础；构建器校验的源文件及其 SHA-256 值列在 [`tools/scutclient-v3.1.3.sha256`](tools/scutclient-v3.1.3.sha256)。校验不匹配时构建会停止。
- 构建会编译上游的 `src/auth.c`、`src/drcom.c`、`src/functions.c`、`src/info.c`、`src/md5.c`，并使用对应上游头文件。`tools/build_wired_client.py` 对 `auth.c` 应用本项目补丁；生成程序还编入项目适配器 [`tools/wired-main.c`](tools/wired-main.c)。因此，生成的 `scutclient-wired` 包含改造后的上游代码，不是仅参考协议重新实现。
- 上游项目声明采用 GNU Affero General Public License version 3（AGPL-3.0）；许可证全文随本项目保存在 [`LICENSES/scutclient-AGPL-3.0.txt`](LICENSES/scutclient-AGPL-3.0.txt)。适配器和协议回归文件也标注为 AGPL-3.0-or-later。发布或再分发包含该代码的程序时，应随附适用的许可证及对应源代码，并保留上游版权和许可证声明。

### 本项目的适配

`tools/build_wired_client.py` 校验固定的上游输入后，在 `auth.c` 中加入有线会话守卫与回调，并调整 EAP/UDP 收发、挑战处理、报文边界和日志字段。`tools/wired-main.c` 将协议客户端接到项目的 Portal 全局锁、持久会话和认证额度控制，并通过标准输入接收凭据。OpenWrt 服务、会话/夜间守卫和路由健康检查位于 `candidate/`，由本项目维护；它们不属于上游仓库。

生成的上游改造源码、静态二进制和含真实网络参数的部署包不放入 Git；按 README 中的构建步骤，从匹配校验清单的上游源码树重建。
