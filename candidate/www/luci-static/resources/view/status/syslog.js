'use strict';
'require tools.views as views';
'require fs';
'require ui';

return views.LogreadBox(null, _('System Log')).extend({
    showOriginal: false,

    async retrieveLog() {
        if (this.showOriginal)
            return this.super('retrieveLog', []);
        try {
            const text = await fs.exec_direct('/usr/libexec/syslog-wrapper');
            const count = Math.min(1000, Math.max(1, Number(this.fetchMaxRows) || 1000));
            let lines = text.trimEnd() ? text.trimEnd().split(/\n/).slice(-count) : [];
            lines = lines.filter(line => {
                const sev = this.logSeverityFilter === 'any' || line.includes(`.${this.logSeverityFilter}`);
                const fac = this.logFacilityFilter === 'any' || line.includes(`${this.logFacilityFilter}.`);
                return this.invertLogSeveritySearch != sev && this.invertLogFacilitySearch != fac;
            });
            lines = lines.filter(line => line.toLowerCase().includes((this.logTagFilter || '').toLowerCase()));
            lines = lines.filter(line => this.invertLogTextSearch
                ? !line.includes(this.logTextFilter) : line.includes(this.logTextFilter));
            return { value: lines.join('\n'), rows: lines.length + 1 };
        } catch (err) {
            ui.addNotification(null, E('p', {}, _('Unable to load log data: ') + err.message));
            return { value: '', rows: 1 };
        }
    },

    render(loglines) {
        const page = this.super('render', [loglines]);
        const button = E('button', { class: 'cbi-button cbi-button-neutral', type: 'button' }, '查看原始记录');
        button.addEventListener('click', async () => {
            this.showOriginal = !this.showOriginal;
            button.textContent = this.showOriginal ? '返回常规日志' : '查看原始记录';
            await this.pollLog();
        });
        const hint = E('div', { class: 'cbi-section-descr', style: 'margin-bottom:10px' }, [
            button, ' 常规日志按已核实的场景调整等级；原始记录保留原始等级。'
        ]);
        const heading = page.querySelector('h2');
        if (heading) heading.after(hint);
        return page;
    }
});
