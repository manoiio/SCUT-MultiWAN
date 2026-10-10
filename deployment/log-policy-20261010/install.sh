#!/bin/sh
# Bound to the read-only baseline captured on 2026-10-10 afternoon. One time.
set -eu
umask 077
stage=/tmp/scut-log-policy-stage-20261010
backup=/root/scut-log-policy-backup-20261010
[ ! -e "$backup" ] || exit 75
[ ! -e /usr/libexec/scut-logread-policy ] || exit 75
[ "$(readlink /sbin/logread)" = /usr/libexec/logread-ubox ] || exit 75
cd "$stage"
sha256sum -c baseline.sha256
sha256sum -c candidate.sha256
for file in usr/bin/native-best usr/bin/scut-logread usr/bin/scut-reboot-watch usr/libexec/syslog-wrapper etc/init.d/log; do
    test -s "$file"; sh -n "$file"
done
usr/libexec/scut-logread-policy --classify </dev/null
exec 8>>/tmp/scut-multiwan-locks/native-best
flock -n 8 || exit 75
mkdir -p "$backup/usr/bin" "$backup/usr/libexec" "$backup/etc/init.d" "$backup/www/luci-static/resources/view/status" "$backup/evidence"
chmod 700 "$backup"
cp /usr/bin/native-best /usr/bin/scut-reboot-watch "$backup/usr/bin/"
cp /etc/init.d/log "$backup/etc/init.d/"
cp /usr/libexec/syslog-wrapper "$backup/usr/libexec/"
cp /www/luci-static/resources/view/status/syslog.js "$backup/www/luci-static/resources/view/status/"
readlink /sbin/logread > "$backup/logread.target"
cat /proc/sys/kernel/random/boot_id > "$backup/boot.id"
pidof logd > "$backup/logd.pid"
sha256sum /etc/config/network /etc/config/wireless /etc/config/firewall /etc/config/dhcp /etc/config/system /etc/campus-portal.conf /etc/scut-wired.conf /etc/crontabs/root /etc/scut-multiwan/*.session /etc/scut-multiwan/*.night-budget > "$backup/preserved.sha256"
cp rollback.sh "$backup/rollback.sh"; chmod 700 "$backup/rollback.sh"
(
    exec 8>&-
    trap '' HUP
    sleep 600
    [ -f "$backup/confirmed" ] || sh "$backup/rollback.sh"
) </dev/null >/dev/null 2>&1 &
echo "$!" > "$backup/guard.pid"
trap 'rc=$?; [ "$rc" = 0 ] || { exec 8>&-; sh "$backup/rollback.sh"; }; exit "$rc"' EXIT
for file in usr/libexec/scut-logread-policy usr/bin/scut-logread usr/bin/native-best usr/bin/scut-reboot-watch usr/libexec/syslog-wrapper etc/init.d/log www/luci-static/resources/view/status/syslog.js; do
    cp "$file" "/$file.scut-new"; chmod 755 "/$file.scut-new"
    [ "$file" != www/luci-static/resources/view/status/syslog.js ] || chmod 644 "/$file.scut-new"
    cmp "$file" "/$file.scut-new"; mv "/$file.scut-new" "/$file"
done
# Stop only the old file follower. Do not restart or flush logd's RAM ring.
ubus call service delete '{"name":"log","instance":"logfile"}' >/dev/null
cp /etc/scut-logs/system.log "$backup/evidence/system.before.log"
cp /etc/scut-logs/system.log /etc/scut-logs/raw.log
[ ! -f /etc/scut-logs/system.log.old ] || cp /etc/scut-logs/system.log.old /etc/scut-logs/raw.log.old
/usr/libexec/scut-logread-policy --classify < /etc/scut-logs/raw.log > /etc/scut-logs/system.log.scut-new
test "$(wc -l < /etc/scut-logs/raw.log)" = "$(wc -l < /etc/scut-logs/system.log.scut-new)"
mv /etc/scut-logs/system.log.scut-new /etc/scut-logs/system.log
if [ -f /etc/scut-logs/raw.log.old ]; then
    /usr/libexec/scut-logread-policy --classify < /etc/scut-logs/raw.log.old > /etc/scut-logs/system.log.old.scut-new
    mv /etc/scut-logs/system.log.old.scut-new /etc/scut-logs/system.log.old
fi
ln -s /usr/bin/scut-logread /sbin/logread.scut-new
mv /sbin/logread.scut-new /sbin/logread
/etc/init.d/log reload
sleep 2
# Separate handoff evidence includes the short follower replacement interval.
/usr/libexec/logread-ubox > "$backup/evidence/handoff.ram.log"
sha256sum -c "$backup/preserved.sha256"
[ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$backup/boot.id")" ]
[ "$(pidof logd)" = "$(cat "$backup/logd.pid")" ]
logger -p user.notice -t scut-log-policy 'installed: classified view plus bounded original evidence; Native teardown requires observed postconditions'
date -Iseconds > "$backup/installed"
echo "installed; guard needs explicit verification: $backup"
