# LAN 前端缓存、按钮与布局修复（2026-10-08）

已安装于路由器并在用户现有 Edge 登录页面验证。菜单仍位于 `/cgi-bin/luci/admin/network/scut_lan`，最终前端加载 `network/scut_lan_e9b1431aabfb` 内容版本模块，规范源为 candidate/www/luci-static/resources/view/network/scut_lan.js。编辑源后先运行 `python3 tools/build_lan_view.py`，再安装生成资源与菜单并使 LuCI 菜单索引失效。生成器和测试防止菜单版本与规范源不一致；旧内容版本资源可供已打开的客户端使用。

用户 Edge 原页面只有旧三模式按钮，强制刷新和页面 URL 查询参数均仍显示旧视图；设备 HTTP 提供规范源的 SHA 已为新版本。切换菜单到内容版本模块并移走可重建的菜单索引后，原浏览器普通刷新即可显示新控件，未清浏览器全部缓存、未重新登录。

真实 DOM 又发现 `E('button', {disabled:false})` 会被 LuCI stringified 成存在的 HTML disabled 属性，六个按钮全部禁用。改为设置 button.disabled DOM 属性；前端 mock 改为按属性存在性模拟原始 E 行为，并覆盖空闲可用、操作中六按钮禁用、成功后重新可用。没有重复校园认证或注销。

布局上方为当前出口概览及三张切换卡片，高亮当前选择；下方独立三路登录卡片、登录/注销与每日计划。进一步压缩垂直间距，样式仅作用于 scut-panel，窄屏改为单列。三个标题可点击：Native 跳至当前 radio 的原生无线页面、USB 跳至 radio3、有线跳至 WAN 接口页面。三个链接均在真实 Edge 中逐一点击并核对目标，最后返回 LAN 页面。截图见 evidence/lan-layout.png。三路在线、六按钮 enabled、wired 当前高亮；没有点击执行登录/注销，没有改变 LAN 模式。

按用户最后修订，手动注销当天暂停自动登录，次日各路独立随机 07:00–07:40 的晨间任务仍尝试一次；当天也可手动恢复。失败或未知结果不重复当日晨间认证。后端仅在 wireless-control.sh 与 scut-lan-links 中增加独立 logout 暂停原因，便于正确呈现操作；调度器和 cron 保持上轮版本，未实施永久禁止晨间恢复的策略。隔离 BusyBox 完整 194 组通过，另 3 组启用真实随机调度功能标记的针对性测试通过，覆盖三路自动入口暂停、注销后 watchdog 拒绝认证、次日恢复和同日不重复。Node 前端回归与 git diff --check 通过。真实手动注销和次日自然晨间尚未实测。

最终边界补充：手动注销先持久登记当天的 morning-claimed 日期，因此即使当天晨间任务尚未运行，也会跳过；次日日期不同，仍可恢复。时间无效时保留暂停并拒绝注销执行，避免使用未知日期放行。单文件补丁另有专用备份 `/root/scut-logout-morning-backup-20261008`，可通过其 rollback.sh 只撤销本项边界修复；install-morning-claim.sh 绑定本轮基线，不是通用安装器。

该单文件补丁通过完整 195 组 BusyBox 回归后于 21:01 安装并确认；最终 helper SHA 为 9153485164696385a47d547d8fea3a4b16558c8219c4f56b106868eb3b63d4e3，两个部署保护均已确认。用户另强调 08:00 后注销也须允许同日手动重登，追加针对性回归验证了 08:05 注销 → watchdog 暂停 → 手动登录及公网验证成功 → watchdog 正常返回，1 组通过。成功手动登录删除该路暂停标记，恢复现有周期维护，并按已有 worker 流程立即刷新健康路由及页面探测；当天 morning-claimed 不限制 watchdog，失败仍保持暂停。本轮实际没有注销健康会话。

备份在设备 `/root/scut-lan-view-cache-backup-20261008`（700），包含原菜单、规范源、移动前的索引及两个后端脚本。回滚脚本持有 Portal 锁，恢复本轮五文件对应的原版本并使菜单索引失效，不重启网络或认证，旧版本模块留作静态资源。最终安装具备 600 秒自动回滚保护，20:51 验证后建立 day-confirmed 并停止保护进程。部署清单见 files.txt，最终状态与测试记录见 evidence/。历史中间内容版本文件保留，不将它们当作当前菜单。
