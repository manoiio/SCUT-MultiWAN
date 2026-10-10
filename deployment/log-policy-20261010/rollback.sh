#!/bin/sh
# Restore only this deployment; retain all collected original evidence.
set -eu
umask 077
backup=/root/scut-log-policy-backup-20261010
[ -f "$backup/logread.target" ] || exit 75
exec 8>>/tmp/scut-multiwan-locks/native-best
waited=0
while ! flock -n 8; do
    [ "$waited" -lt 120 ] || exit 75
    sleep 1; waited=$((waited+1))
done
ubus call service delete '{"name":"log","instance":"logfile"}' >/dev/null || true
for file in usr/bin/native-best usr/bin/scut-reboot-watch usr/libexec/syslog-wrapper etc/init.d/log www/luci-static/resources/view/status/syslog.js; do
    cp "$backup/$file" "/$file.scut-restore"; chmod 755 "/$file.scut-restore"
    [ "$file" != www/luci-static/resources/view/status/syslog.js ] || chmod 644 "/$file.scut-restore"
    mv "/$file.scut-restore" "/$file"
done
target="$(cat "$backup/logread.target")"
[ "$target" = /usr/libexec/logread-ubox ] || exit 75
ln -s "$target" /sbin/logread.scut-restore
mv /sbin/logread.scut-restore /sbin/logread
# Revert the view to original priorities while retaining the new raw files.
if [ -f /etc/scut-logs/raw.log ]; then
    cp /etc/scut-logs/raw.log /etc/scut-logs/system.log.scut-restore
    mv /etc/scut-logs/system.log.scut-restore /etc/scut-logs/system.log
fi
/etc/init.d/log reload
date -Iseconds > "$backup/rolled-back"
logger -t scut-log-policy 'presentation policy rolled back; original evidence retained'
