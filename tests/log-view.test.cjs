const fs = require('node:fs');
const assert = require('node:assert/strict');
const source = fs.readFileSync('candidate/www/luci-static/resources/view/status/syslog.js', 'utf8');
let input = 'Sat Oct 10 13:00:00 2026 cron.info crond[1]: USER root pid 12 cmd test\nSat Oct 10 13:00:01 2026 daemon.err native-best: phase=radio-cleanup state=unconfirmed\n';
let notices = 0, failed = false, rawCalls = 0, click, hint;
const base = {
  logSeverityFilter: 'any', logFacilityFilter: 'any', invertLogSeveritySearch: false,
  invertLogFacilitySearch: false, logTagFilter: '', logTextFilter: '', invertLogTextSearch: false,
  fetchMaxRows: 1000,
  render() { return { querySelector: () => ({ after: node => { hint = node; } }) }; },
  retrieveLog() { rawCalls++; return { value: 'raw', rows: 2 }; },
  async pollLog() { await this.retrieveLog(); },
  super(name, args) { return base[name].apply(this, args); }
};
let views = { LogreadBox: () => ({ extend: methods => ({ ...base, ...methods }) }) };
if (process.argv[2] === '--live-framework') {
  const framework = fs.readFileSync(process.argv[3], 'utf8');
  const start = framework.indexOf('const toCamelCase=');
  const end = framework.indexOf('const Headers=');
  assert(start >= 0 && end > start);
  const Class = new Function('LuCI', framework.slice(start, end) + ';return Class;')(
    { prototype: { isArguments: arg => Object.prototype.toString.call(arg) === '[object Arguments]' } });
  const properties = { ...base, __init__() {} }; delete properties.super;
  const Base = Class.extend(properties);
  views = { LogreadBox: () => Base };
}
const Result = new Function('views', 'fs', 'ui', 'E', '_', source)(
  views,
  { exec_direct: async path => { assert.equal(path, '/usr/libexec/syslog-wrapper'); if (failed) throw Error('fixture'); return input; } },
  { addNotification: () => notices++ }, (tag, attrs, children) => ({
    tag, attrs, children, addEventListener: (event, handler) => { assert.equal(event, 'click'); click = handler; }
  }), text => text);
const view = typeof Result === 'function' ? new Result() : Result;
(async () => {
  assert.equal((await view.retrieveLog()).rows, 3);
  view.logSeverityFilter = 'err'; assert.match((await view.retrieveLog()).value, /unconfirmed/);
  assert.doesNotMatch((await view.retrieveLog()).value, /cron.info/);
  view.invertLogSeveritySearch = true; assert.match((await view.retrieveLog()).value, /cron.info/);
  view.invertLogSeveritySearch = false; view.logSeverityFilter = 'any'; view.fetchMaxRows = 1;
  assert.equal((await view.retrieveLog()).rows, 2);
  view.logTextFilter = 'missing'; assert.equal((await view.retrieveLog()).rows, 1);
  view.showOriginal = true; assert.equal((await view.retrieveLog()).value, 'raw'); assert.equal(rawCalls, 1);
  view.showOriginal = false; failed = true; assert.equal((await view.retrieveLog()).rows, 1); assert.equal(notices, 1);
  failed = false; view.render({ value: 'fixture', rows: 2 }); assert(hint); assert.equal(typeof click, 'function');
  await click(); assert.equal(view.showOriginal, true); await click(); assert.equal(view.showOriginal, false);
  console.log('ALL 10 LOG VIEW CHECKS PASSED (mock data' + (process.argv[2] ? ', actual router Class/super' : '') + '; not browser acceptance)');
})().catch(err => { console.error(err); process.exitCode = 1; });
