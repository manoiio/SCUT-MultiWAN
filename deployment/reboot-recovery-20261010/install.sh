#!/bin/sh
# One-time installer bound to the inspected idle-engine/quiet-window baseline.
set -eu
umask 077
stage=/tmp/scut-reboot-recovery-stage-20261010
backup=/root/scut-reboot-recovery-backup-20261010
[ ! -e "$backup" ] || exit 75
[ ! -e /tmp/scut-multiwan-deploying ] || exit 75
[ -z "$(uci changes system)" ] || exit 75
cd "$stage"
sha256sum -c candidate.sha256
for file in usr/bin/scut-wired-gate usr/bin/scut-wired-route-recover usr/bin/scut-reboot-watch etc/init.d/scut-reboot-watch; do
    test -s "$file"; sh -n "$file"
done
usr/bin/scutclient-wired --version >/dev/null
for file in usr/bin/scut-wired-route-recover usr/bin/scut-reboot-watch etc/init.d/scut-reboot-watch; do
    [ ! -e "/$file" ] || exit 75
done
exec 6>>/tmp/scut-multiwan-locks/wired-engine
flock -n 6 || { logger -t scut-recovery 'install deferred: wired engine is running'; exit 75; }
exec 9>>/tmp/scut-multiwan-locks/portal
waited=0
while ! flock -n 9; do
    [ "$waited" -lt 20 ] || exit 75
    sleep 1; waited=$((waited+1))
done
[ ! -e /tmp/scut-wired-ready ] || exit 75
mkdir -p "$backup/usr/bin" "$backup/config" /etc/scut-logs
chmod 700 "$backup" /etc/scut-logs
cp /usr/bin/scutclient-wired /usr/bin/scut-wired-gate "$backup/usr/bin/"
cp /etc/config/system "$backup/config/system"
cp rollback.sh "$backup/rollback.sh"
chmod 700 "$backup/rollback.sh"
sha256sum /etc/config/network /etc/config/wireless /etc/config/firewall /etc/config/dhcp /etc/campus-portal.conf /etc/scut-wired.conf /etc/crontabs/root /etc/scut-multiwan/*.session /etc/scut-multiwan/wired.night-budget > "$backup/preserved.sha256"
cat /proc/sys/kernel/random/boot_id > "$backup/boot.id"
touch /tmp/scut-multiwan-deploying
(
    exec 6>&- 9>&-
    trap '' HUP
    sleep 600
    [ -f "$backup/confirmed" ] || sh "$backup/rollback.sh"+) </dev/null >/dev/null 2>&1 &
echo "$!" > "$backup/guard.pid"
trap 'rc=$?; [ "$rc" = 0 ] || { exec 6>&- 9>&-; sh "$backup/rollback.sh"; }; exit "$rc"' EXIT
for file in usr/bin/scut-wired-route-recover usr/bin/scut-reboot-watch etc/init.d/scut-reboot-watch usr/bin/scut-wired-gate usr/bin/scutclient-wired; do
    cp "$file" "/$file.scut-new"
    chmod 755 "/$file.scut-new"
    cmp "$file" "/$file.scut-new"
    mv "/$file.scut-new" "/$file"
done
# Preserve the current RAM history before starting the file follower.
logread > /etc/scut-logs/system.log
chmod 600 /etc/scut-logs/system.log
uci set system.@system[0].log_file=/etc/scut-logs/system.log
uci set system.@system[0].log_buffer_size=128
uci set system.@system[0].log_size=2048
uci commit system
# Keep logd's existing -S128 instance; add only the file follower.
/etc/init.d/log reload
/etc/init.d/scut-reboot-watch enable
/etc/init.d/scut-reboot-watch start
sha256sum -c "$backup/preserved.sha256"
[ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$backup/boot.id")" ]
sha256sum /etc/config/system > "$backup/installed-system.sha256"
rm -f /tmp/scut-multiwan-deploying
logger -t scut-recovery 'bounded wired release/route recovery and persistent logs installed; no authentication or reboot requested'
date -Iseconds > "$backup/installed"
echo "installed; verification required before confirming guard: $backup"
