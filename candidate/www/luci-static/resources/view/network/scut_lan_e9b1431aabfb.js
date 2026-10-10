'use strict';
'require view';
'require fs';
'require ui';
'require poll';

var names = { tunnel: '三网聚合隧道', multi: '原三网出口', wired: '单有线出口' };
var descriptions = {
    tunnel: '汇聚三路校园网，统一从新 VPS 出网',
    multi: '按连接分担流量，使用校园网原出口',
    wired: '仅使用有线校园网，不自动切换无线'
};
function decode(r) {
    if (r.code !== 0) throw new Error((r.stdout || r.stderr || '操作失败').trim());
    var data = JSON.parse(r.stdout);
    if (data.error) throw new Error(data.error);
    return data;
}
return view.extend({
    load: function() {
        return Promise.all([
            fs.exec('/usr/libexec/scut-lan-status', []).then(decode),
            fs.exec('/usr/libexec/scut-lan-link-status', []).then(decode)
        ]);
    },
    render: function(data) {
        var status = E('div', { 'class': 'scut-current-name' }), summary = E('p'), ready = E('span'), health = E('span');
        var buttons = [], actionButtons = [], busy = false, linkBusy = false, lastMode = data[0];
        var links = E('div', { 'class': 'scut-link-grid' }), morning = E('div', { 'class': 'scut-times' });
        var css = E('style', {}, '.scut-panel{max-width:1120px;margin:0 auto;color:#253047}.scut-panel *{box-sizing:border-box}.scut-panel h2{font-size:24px;margin:0 0 6px}.scut-intro{color:#737f91;margin:0 0 12px}.scut-current{display:flex;justify-content:space-between;align-items:center;gap:20px;padding:14px 18px;background:#f3f7fc;border:1px solid #dce6f3;border-radius:14px;margin-bottom:16px}.scut-eyebrow{font-size:12px;color:#64748b;margin-bottom:4px}.scut-current-name{font-size:22px;font-weight:650;line-height:1.3}.scut-current p{margin:4px 0 0;color:#617086;font-size:14px}.scut-current-side{display:flex;flex-direction:column;align-items:flex-end;gap:6px;white-space:nowrap}.scut-ready{color:#15835c;background:#e3f4ec;padding:5px 12px;border-radius:20px;font-size:13px}.scut-wait{color:#8a641b;background:#fff2d9;padding:5px 12px;border-radius:20px;font-size:13px}.scut-health{font-size:13px;color:#64748b}.scut-section-title{font-size:17px;margin:0 0 12px;font-weight:650}.scut-mode-grid,.scut-link-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}.scut-mode{display:flex;flex-direction:column;align-items:flex-start;text-align:left;min-height:104px;width:100%;padding:14px;border:1px solid #d7dee8;border-radius:12px;background:#fff;color:#253047;cursor:pointer;font-family:inherit;box-shadow:none}.scut-mode:hover{border-color:#719ddd;background:#f8fbff}.scut-mode:focus-visible{outline:3px solid #8db7ed;outline-offset:3px}.scut-mode-selected,.scut-mode-selected:hover{border:2px solid #3978cf;padding:13px;background:#f2f7ff}.scut-mode-title{font-size:16px;font-weight:650;margin-bottom:7px}.scut-mode-desc{font-size:13px;line-height:1.4;color:#738094;flex:1}.scut-mode-action{font-size:12px;color:#3978cf;margin-top:10px}.scut-mode:disabled{cursor:default}.scut-mode-selected:disabled{opacity:1;color:#253047}.scut-mode:disabled:not(.scut-mode-selected){opacity:.6}.scut-link-section{margin-top:22px;padding-top:17px;border-top:1px solid #e6eaf0}.scut-section-head{display:flex;justify-content:space-between;align-items:baseline;gap:14px;margin-bottom:12px}.scut-section-head h3{margin:0}.scut-section-head p{font-size:12px;color:#7b8798;margin:0}.scut-link{padding:14px;border:1px solid #e0e5ed;border-radius:12px;background:#fff}.scut-link-name{font-size:16px;font-weight:650;margin:0 0 4px}.scut-link-name a{color:inherit;text-decoration:none;display:inline-flex;align-items:center;gap:7px}.scut-link-name a:hover{color:#3978cf;text-decoration:underline}.scut-link-arrow{font-size:13px;color:#8593a5;font-weight:400}.scut-link-device{font-size:12px;color:#8993a3;margin-bottom:10px}.scut-link-state{font-size:14px;min-height:22px;color:#657286;margin:0}.scut-link-state:before{content:"";display:inline-block;width:7px;height:7px;background:#96a1b2;border-radius:50%;margin-right:8px;vertical-align:middle}.scut-link-online{color:#15835c}.scut-link-online:before{background:#20a471}.scut-link-pending{color:#3978cf}.scut-link-pending:before{background:#3978cf}.scut-link-offline{color:#a57023}.scut-link-offline:before{background:#d09739}.scut-link-note{font-size:12px;color:#8a641b;min-height:6px;margin:4px 0 9px}.scut-link-controls{display:flex;gap:9px}.scut-control{font-size:13px;border:1px solid #d5dce6;border-radius:7px;padding:7px 13px;color:#6e7888;background:#fff;cursor:pointer;flex:1;font-family:inherit}.scut-control-login{color:#3978cf;border-color:#c5d7ef;background:#f6f9fe}.scut-control:hover{background:#edf3fb}.scut-control:disabled{opacity:.45;cursor:default}.scut-schedule{margin-top:12px;padding:12px 16px;border-radius:10px;background:#f7f8fa}.scut-schedule-heading{font-size:13px;font-weight:600;color:#626f82;margin-bottom:8px}.scut-times{display:flex;flex-wrap:wrap;gap:12px 30px;color:#7b8798;font-size:12px}.scut-time-value{font-size:15px;font-weight:600;color:#495971;margin-left:9px;font-variant-numeric:tabular-nums}.scut-note{font-size:12px;color:#8490a1;line-height:1.7;margin:10px 0 0}@media(max-width:720px){.scut-current{padding:20px;align-items:flex-start}.scut-current-name{font-size:21px}.scut-mode-grid,.scut-link-grid{grid-template-columns:1fr}.scut-mode{min-height:115px}.scut-section-head{display:block}.scut-section-head p{margin-top:7px}.scut-current-side{gap:8px}.scut-times{gap:12px 20px}}');
        function update(s) {
            lastMode = s;
            status.textContent = names[s.mode] || '未知出口';
            summary.textContent = descriptions[s.mode] || '等待读取出口状态';
            ready.textContent = s.ready ? '已就绪' : '等待链路恢复';
            ready.className = s.ready ? 'scut-ready' : 'scut-wait';
            health.textContent = '可用线路 ' + (s.available_wans == null ? '?' : s.available_wans) + ' / 3';
            health.className = 'scut-health';
            buttons.forEach(function(item) {
                var selected = item.mode === s.mode;
                item.button.disabled = busy || linkBusy || selected;
                item.button.className = 'scut-mode' + (selected ? ' scut-mode-selected' : '');
                item.button.setAttribute('aria-pressed', String(selected));
                item.action.textContent = selected ? '✓ 当前使用' : busy ? '正在切换…' : '切换到此出口 →';
            });
        }
        var row = E('div', { 'class': 'scut-mode-grid' });
        ['tunnel', 'multi', 'wired'].forEach(function(mode) {
            var action = E('span', { 'class': 'scut-mode-action' });
            var b = E('button', { 'class': 'scut-mode', 'type': 'button', 'data-mode': mode }, [
                E('span', { 'class': 'scut-mode-title' }, names[mode]),
                E('span', { 'class': 'scut-mode-desc' }, descriptions[mode]), action
            ]);
            b.addEventListener('click', function() {
                busy = true; update(lastMode);
                fs.exec('/usr/libexec/scut-lan-set', [mode]).then(decode).then(function(s) {
                    busy = false; update(s);
                }).catch(function(err) {
                    busy = false; ui.addNotification(null, E('p', err.message));
                    fs.exec('/usr/libexec/scut-lan-status', []).then(decode).then(update);
                });
            });
            buttons.push({ button: b, mode: mode, action: action }); row.appendChild(b);
        });
        var labels = { native: 'Native 无线', usb: 'USB 无线', wan: '有线校园网' };
        function clock(seconds) {
            return String(Math.floor(seconds / 3600)).padStart(2, '0') + ':' + String(Math.floor(seconds / 60) % 60).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0');
        }
        function refreshLinks(s) {
            links.replaceChildren(); actionButtons = [];
            linkBusy = s.links.some(function(x) { return x.running; });
            s.links.forEach(function(x) {
                var text = x.running ? '正在执行，等待验证' : x.online === true ? '已登录 · 公网验证通过' : x.online === null ? '等待公网验证' : '公网不可达';
                var stateClass = x.running ? 'scut-link-pending' : x.online === true ? 'scut-link-online' : x.online === false ? 'scut-link-offline' : '';
                var note = x.paused ? (x.pause_reason === 'logout' ? '手动注销：自动登录暂停，次日晨间恢复' : x.pause_reason === 'vanished' ? '会话已消失，自动登录暂停' : '自动登录暂停') : '';
                if (!x.running && (x.last_action === 'failed' || x.last_action === 'deferred')) note += (note ? ' · ' : '') + '上次操作未完成';
                var controls = E('div', { 'class': 'scut-link-controls' });
                ['login', 'logout'].forEach(function(action) {
                    var b = E('button', { 'type': 'button', 'class': 'scut-control' + (action === 'login' ? ' scut-control-login' : '') }, action === 'login' ? '手动登录' : '注销');
                    // LuCI E() stringifies false attributes; use the DOM property.
                    b.disabled = linkBusy;
                    actionButtons.push(b);
                    b.addEventListener('click', function() {
                        ui.showModal(labels[x.slot] + ' · ' + (action === 'login' ? '手动登录' : '注销'), [
                            E('p', action === 'login' ? '重新占用校园会话可能使手机掉线。Native 登录会重新比较两 radio，完成公网验证后才显示已登录。' : '注销会中断该线路上的连接，当天暂停自动登录；次日该路的随机晨间时间会尝试一次恢复，也可提前手动登录。'),
                            E('div', { 'class': 'right' }, [
                                E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, '取消'),
                                E('button', { 'class': 'cbi-button cbi-button-action', 'click': function() {
                                    ui.hideModal(); linkBusy = true;
                                    actionButtons.forEach(function(button) { button.disabled = true; }); update(lastMode);
                                    fs.exec('/usr/libexec/scut-lan-link-action', [x.slot, action]).then(decode).then(function() {
                                        return fs.exec('/usr/libexec/scut-lan-link-status', []).then(decode).then(refreshLinks);
                                    }).catch(function(err) {
                                        ui.addNotification(null, E('p', err.message)); linkBusy = false;
                                        actionButtons.forEach(function(button) { button.disabled = false; }); update(lastMode);
                                    });
                                } }, '执行')
                            ])
                        ]);
                    });
                    controls.appendChild(b);
                });
                var device = x.slot === 'native' ? (x.radio === 'none' ? '未关联或切换中' : x.radio + ' · ' + x.device) : x.device;
                var href = x.slot === 'wan' ? L.url('admin/network/network') + '#cbi-network-wan-_ifacestat' : L.url('admin/network/wireless');
                if (x.slot === 'usb') href += '#cbi-wireless-radio3-_stat';
                else if (x.slot === 'native' && (x.radio === 'radio0' || x.radio === 'radio2')) href += '#cbi-wireless-' + x.radio + '-_stat';
                links.appendChild(E('div', { 'class': 'scut-link' }, [
                    E('div', { 'class': 'scut-link-name' }, E('a', { 'href': href, 'data-link-slot': x.slot, 'title': x.slot === 'wan' ? '打开 LuCI 原生接口界面' : '打开 LuCI 原生无线界面' }, [E('span', labels[x.slot]), E('span', { 'class': 'scut-link-arrow', 'aria-hidden': 'true' }, '→')])) ,
                    E('div', { 'class': 'scut-link-device' }, device),
                    E('p', { 'class': 'scut-link-state ' + stateClass }, text),
                    E('p', { 'class': 'scut-link-note' }, note), controls
                ]));
            });
            morning.replaceChildren();
            if (s.morning) ['native', 'usb', 'wan'].forEach(function(slot) {
                morning.appendChild(E('span', {}, [slot === 'native' ? 'Native' : slot === 'usb' ? 'USB' : '有线', E('span', { 'class': 'scut-time-value' }, clock(s.morning[slot]))]));
            });
            else morning.appendChild(E('span', {}, '等待时钟或配置恢复'));
            update(lastMode);
        }
        update(data[0]); refreshLinks(data[1]);
        poll.add(function() {
            if (!busy) return Promise.all([
                fs.exec('/usr/libexec/scut-lan-status', []).then(decode).then(update),
                fs.exec('/usr/libexec/scut-lan-link-status', []).then(decode).then(refreshLinks)
            ]);
        }, 5);
        return E('div', { 'class': 'cbi-map scut-panel' }, [css,
            E('h2', 'LAN 出口切换'), E('p', { 'class': 'scut-intro' }, '管理所有 LAN 设备的互联网出口'),
            E('div', { 'class': 'scut-current' }, [
                E('div', {}, [E('div', { 'class': 'scut-eyebrow' }, '当前出口'), status, summary]),
                E('div', { 'class': 'scut-current-side' }, [ready, health])
            ]),
            E('h3', { 'class': 'scut-section-title' }, '选择出口'), row,
            E('p', { 'class': 'scut-note' }, '选择立即生效并自动保存。切换时已有下载、游戏和通话可能需要重连；局域网和路由器管理仍可访问。'),
            E('section', { 'class': 'scut-link-section' }, [
                E('div', { 'class': 'scut-section-head' }, [E('h3', { 'class': 'scut-section-title' }, '三路登录管理'), E('p', '状态由各线路的公网验证确认')]),
                links,
                E('div', { 'class': 'scut-schedule' }, [E('div', { 'class': 'scut-schedule-heading' }, '每日自动启动 · 三路分别随机 07:00–07:40'), morning]),
                E('p', { 'class': 'scut-note' }, '手动注销或确认会话消失后，当天暂停自动登录；手动登录或次日该路晨间计划尝试恢复。状态最多缓存一分钟。')
            ])
        ]);
    },
    handleSave: null,
    handleSaveApply: null,
    handleReset: null
});
