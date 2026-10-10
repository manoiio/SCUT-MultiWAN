#!/bin/sh
# This device/date only. Never replace a live executable or clear session state.
set -eu
umask 077
backup=/root/scut-reboot-recovery-backup-20261010
exec 6>>/tmp/scut-multiwan-locks/wired-engine
flock -n 6 || { logger -t scut-recovery 'rollback deferred: wired engine is running'; exit 75; }
exec 9>>/tmp/scut-multiwan-locks/portal
flock -n 9 || exit 75
/etc/init.d/scut-reboot-watch stop 2>/dev/null || true
/etc/init.d/scut-reboot-watch disable 2>/dev/null || true
for file in usr/bin/scutclient-wired usr/bin/scut-wired-gate; do
    cp "$backup/$file" "/$file.rollback"
    chmod 755 "/$file.rollback"
    mv "/$file.rollback" "/$file"
done
for file in usr/bin/scut-wired-route-recover usr/bin/scut-reboot-watch etc/init.d/scut-reboot-watch; do
    rm -f "/$file"
done
for option in log_file log_size log_buffer_size; do
    if value="$(uci -c "$backup/config" -q get "system.@system[0].$option")"; then
        uci set "system.@system[0].$option=$value"
    else
        uci -q delete "system.@system[0].$option" || true
    fi
done
uci commit system
/etc/init.d/log reload
rm -f /tmp/scut-multiwan-deploying
logger -t scut-recovery 'reboot recovery/log configuration rolled back; saved logs retained'
