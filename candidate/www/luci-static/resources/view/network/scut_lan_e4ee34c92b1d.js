'use strict';
'require view';
'require fs';
'require ui';
'require poll';

var names = { tunnel: '三网聚合隧道 · VPS 出口', multi: '原三网出口', wired: '单有线出口' };
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
        var status = E('p'), buttons = [], busy = false, links = E('tbody'), morning = E('p');
        function update(s) {
            status.textContent = '当前：' + (names[s.mode] || '未知') + (s.ready ? ' · 已就绪' : ' · 等待链路恢复') + ' · 健康 WAN：' + (s.available_wans == null ? '?' : s.available_wans) + '/3';
            buttons.forEach(function(b) { b.disabled = busy || b.dataset.mode === s.mode; });
        }
        var row = E('div', { 'style': 'display:flex;gap:12px;flex-wrap:wrap;margin:20px 0' });
        ['tunnel', 'multi', 'wired'].forEach(function(mode) {
            var b = E('button', { 'class': 'cbi-button cbi-button-action', 'type': 'button', 'data-mode': mode }, names[mode]);
            b.addEventListener('click', function() {
                busy = true; buttons.forEach(function(x) { x.disabled = true; });
                status.textContent = '正在切换…';
                fs.exec('/usr/libexec/scut-lan-set', [mode]).then(decode).then(function(s) {
                    busy = false; update(s);
                }).catch(function(err) {
                    busy = false; ui.addNotification(null, E('p', err.message));
                    fs.exec('/usr/libexec/scut-lan-status', []).then(decode).then(update);
                });
            });
            buttons.push(b); row.appendChild(b);
        });
        var labels = { native: 'Native 无线', usb: 'USB 无线', wan: '有线' };
        function clock(seconds) {
            return String(Math.floor(seconds / 3600)).padStart(2, '0') + ':' + String(Math.floor(seconds / 60) % 60).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0');
        }
        function refreshLinks(s) {
            links.replaceChildren();
            var running = s.links.some(function(x) { return x.running; });
            s.links.forEach(function(x) {
                var text = x.running ? '正在执行，等待验证' : x.online === true ? '已登录 · 公网验证通过' : x.online === null ? '等待公网验证' : '公网不可达';
                if (x.paused) text += x.pause_reason === 'vanished' ? ' · 会话已消失，自动登录暂停' : ' · 自动登录暂停';
                if (!x.running && (x.last_action === 'failed' || x.last_action === 'deferred')) text += ' · 上次操作未完成';
                var controls = E('td');
                ['login', 'logout'].forEach(function(action) {
                    var b = E('button', { 'type': 'button', 'class': 'cbi-button', 'disabled': running }, action === 'login' ? '手动登录' : '注销');
                    b.addEventListener('click', function() {
                        ui.showModal(labels[x.slot] + ' · ' + (action === 'login' ? '手动登录' : '注销'), [
                            E('p', action === 'login' ? '重新占用校园会话可能使手机掉线。Native 登录会重新比较两 radio，完成真实公网验证后才显示已登录。' : '注销会影响该链路上的连接，并暂停自动登录；下一日随机启动时间会恢复三路。'),
                            E('div', { 'class': 'right' }, [
                                E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, '取消'),
                                E('button', { 'class': 'cbi-button cbi-button-action', 'click': function() {
                                    ui.hideModal(); b.disabled = true;
                                    fs.exec('/usr/libexec/scut-lan-link-action', [x.slot, action]).then(decode).then(function() {
                                        return fs.exec('/usr/libexec/scut-lan-link-status', []).then(decode).then(refreshLinks);
                                    }).catch(function(err) { ui.addNotification(null, E('p', err.message)); b.disabled = false; });
                                } }, '执行')
                            ])
                        ]);
                    });
                    controls.appendChild(b);
                });
                links.appendChild(E('tr', {}, [E('td', labels[x.slot]), E('td', x.slot === 'native' ? (x.radio === 'none' ? '未关联或切换中' : x.radio + ' · ' + x.device) : x.device), E('td', text), controls]));
            });
            morning.textContent = s.morning ? '每日分别随机启动（' + s.morning.date + '）：Native ' + clock(s.morning.native) + '，USB ' + clock(s.morning.usb) + '，有线 ' + clock(s.morning.wan) + '。未到各自时间前不自动登录。' : '启动时间暂不可用，等待时钟或配置恢复。';
        }
        update(data[0]); refreshLinks(data[1]);
        poll.add(function() {
            if (!busy) return Promise.all([
                fs.exec('/usr/libexec/scut-lan-status', []).then(decode).then(update),
                fs.exec('/usr/libexec/scut-lan-link-status', []).then(decode).then(refreshLinks)
            ]);
        }, 5);
        return E('div', { 'class': 'cbi-map' }, [
            E('h2', 'LAN 出口切换'), status, row,
            E('h3', '三路登录状态'),
            E('table', { 'class': 'table' }, [E('thead', {}, E('tr', {}, [E('th', '链路'), E('th', '当前接口'), E('th', '登录与公网状态'), E('th', '手动操作')])), links]), morning,
            E('p', '对所有 LAN 设备的互联网流量生效，包含 TCP、UDP 与 IPv6。局域网和路由器管理仍可访问。'),
            E('p', '选择会立即生效并持久保存。已有下载、游戏和通话连接可能需要重连。'),
            E('p', '三网聚合隧道使用新 VPS；原三网按连接分流；单有线模式在有线故障时等待恢复，不自动走无线。'),
            E('p', '确认无线会话消失后停止自动登录，不与手机反复抢会话；仅手动登录或下一日各自随机启动时间恢复。状态经接口绑定 HTTPS 验证，最多缓存一分钟。')
        ]);
    },
    handleSave: null,
    handleSaveApply: null,
    handleReset: null
});
