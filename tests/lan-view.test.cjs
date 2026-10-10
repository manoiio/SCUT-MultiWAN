const fs = require('fs');
const assert = require('assert/strict');
const menu = JSON.parse(fs.readFileSync('candidate/usr/share/luci/menu.d/luci-app-scut-lan.json', 'utf8'));
const modulePath = menu['admin/network/scut_lan'].action.path;
const code = fs.readFileSync('candidate/www/luci-static/resources/view/' + modulePath + '.js', 'utf8');
const canonical = fs.readFileSync('candidate/www/luci-static/resources/view/network/scut_lan.js', 'utf8');
assert.equal(code, canonical, 'versioned view must match canonical source');
assert.equal(modulePath, 'network/scut_lan_' + require('crypto').createHash('sha256').update(code).digest('hex').slice(0, 12));
function E(tag, attrs, kids) {
    if (typeof attrs === 'string') { kids = attrs; attrs = {}; }
    const node = { tag, attrs: attrs || {}, children: [], dataset: {}, listeners: {}, disabled: false,
        textContent: '', appendChild(x) { this.children.push(x); }, replaceChildren() { this.children = []; },
        addEventListener(e, f) { this.listeners[e] = f; }, setAttribute(k, v) { this.attrs[k] = v; } };
    node.dataset.mode = node.attrs['data-mode']; node.disabled = node.attrs.disabled != null;
    if (typeof kids === 'string') node.textContent = kids;
    else if (Array.isArray(kids)) node.children = kids;
    else if (kids) node.children = [kids];
    return node;
}
const calls = []; let modal; let state = { links: [
    {slot:'native',device:'phy2-sta0',radio:'radio2',online:false,paused:true,pause_reason:'vanished',running:false},
    {slot:'usb',device:'phy3-sta0',radio:'none',online:false,paused:true,pause_reason:'vanished',running:false},
    {slot:'wan',device:'wan',radio:'none',online:true,paused:false,running:false}
],morning:{date:'2026-10-08',native:25801,usb:26412,wan:27033}};
const mode = {mode:'wired',ready:true,persistent:true,available_wans:1};
const api = { exec: async (path,args) => {
    calls.push([path,args]); let stdout;
    if(path.endsWith('link-action')) { state.links[0].running = true; stdout = {accepted:true}; }
    else stdout = path.endsWith('link-status') ? state : mode;
    return {code:0,stdout:JSON.stringify(stdout),stderr:''};
}};
const polls=[];
const ui = {showModal:(title,children)=>{modal=children;},hideModal:()=>{},addNotification:()=>{}};
const view = new Function('view','fs','ui','poll','E','L',code)({extend:x=>x},api,ui,{add:x=>polls.push(x)},E,{url:path=>'/cgi-bin/luci/'+path});
function flatten(n) { return [n,...n.children.flatMap(x=>typeof x === 'object' ? flatten(x) : [])]; }
(async () => {
    const page=view.render(await view.load());
    const nodes=flatten(page);
    assert.equal(nodes.filter(x=>x.attrs.class==='scut-link').length,3);
    assert.equal(nodes.filter(x=>x.attrs['data-mode']).length,3);
    assert(nodes.filter(x=>x.tag==='button'&&['手动登录','注销'].includes(x.textContent)).every(x=>!x.disabled));
    assert(nodes.some(x=>x.textContent.includes('可用线路 1 / 3')));
    for (const t of ['07:10:01','07:20:12','07:30:33']) assert(nodes.some(x=>x.textContent===t));
    const links=nodes.filter(x=>x.tag==='a');
    assert.equal(links.find(x=>x.attrs['data-link-slot']==='native').attrs.href, '/cgi-bin/luci/admin/network/wireless#cbi-wireless-radio2-_stat');
    assert.equal(links.find(x=>x.attrs['data-link-slot']==='usb').attrs.href, '/cgi-bin/luci/admin/network/wireless#cbi-wireless-radio3-_stat');
    assert.equal(links.find(x=>x.attrs['data-link-slot']==='wan').attrs.href, '/cgi-bin/luci/admin/network/network#cbi-network-wan-_ifacestat');
    const login=nodes.find(x=>x.tag==='button'&&x.textContent==='手动登录');
    login.listeners.click();
    const confirm=modal.flatMap(flatten).find(x=>x.textContent==='执行');
    confirm.attrs.click(); await new Promise(resolve=>setImmediate(resolve));
    assert(calls.some(x=>x[0]==='/usr/libexec/scut-lan-link-action'&&JSON.stringify(x[1])==='["native","login"]'));
    const text=flatten(page).map(x=>x.textContent);
    assert(text.some(x=>x.includes('正在执行，等待验证')));
    assert(flatten(page).filter(x=>x.tag==='button'&&['手动登录','注销'].includes(x.textContent)).every(x=>x.disabled));
    assert(!text.some(x=>x.includes('已登录')&&x.includes('会话已消失')));
    state.links[0].running=false;state.links[0].online=true;state.links[0].paused=false;
    await polls[0]();
    assert(flatten(page).some(x=>x.textContent==='已登录 · 公网验证通过'));
    assert(flatten(page).filter(x=>x.tag==='button'&&['手动登录','注销'].includes(x.textContent)).every(x=>!x.disabled));
    state.links[0].radio='radio0'; await polls[0]();
    assert.equal(flatten(page).find(x=>x.attrs['data-link-slot']==='native').attrs.href, '/cgi-bin/luci/admin/network/wireless#cbi-wireless-radio0-_stat');
    Object.assign(state.links[0],{paused:true,pause_reason:'morning',last_action:'failed',last_stage:'native-select',last_rc:23});
    state.morning.retry_active=true; await polls[0]();
    assert(flatten(page).some(x=>x.textContent.includes('09:00 前按计划重试')&&x.textContent.includes('Native 选优（23）')));
    state.morning.retry_active=false; await polls[0]();
    assert(flatten(page).some(x=>x.textContent.includes('等待手动或次日恢复')));
    console.log('PASS: three link rows, distinct morning times, exact Native action and pending/success rendering');
})().catch(e=>{console.error(e);process.exitCode=1;});
