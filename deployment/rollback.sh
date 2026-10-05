#!/bin/sh
set -eu
BACKUP=/root/scut-multiwan-backup-20261005-2005
STAGE=/tmp/scut-multiwan-deploy
: > /tmp/scut-multiwan-deploying
while read -r relative; do
    case "$relative" in usr/bin/*|etc/hotplug.d/iface/95-dualwan-refresh) ;;
        *) continue;;
    esac
    source="$BACKUP/$relative"
    [ -s "$source" ] || exit 1
    sh -n "$source" || exit 1
    restore="/${relative}.scut-restore-$$"
    cp -p "$source" "$restore"
    mv "$restore" "/$relative"
done < "$STAGE/files.list"
if [ -f "$BACKUP/runtime/last_scan" ]; then
    mkdir -p /tmp/native-watchdog
    cp -p "$BACKUP/runtime/last_scan" /tmp/native-watchdog/last_scan
fi
if [ -d "$BACKUP/runtime/qca-fixed-rate" ]; then
    cp -p "$BACKUP/runtime/qca-fixed-rate/"*.state /tmp/qca-fixed-rate/ 2>/dev/null || true
fi
if [ -f "$STAGE/install.pid" ]; then
    owner="$(cat "$STAGE/install.pid")"
    for lock in native-best native-watchdog usb-watchdog dualwan-refresh campus-portal-global fix-qca-sta-rate.phy0-sta0 fix-qca-sta-rate.phy2-sta0; do
        dir="/tmp/$lock.lock"
        if [ "$(cat "$dir/pid" 2>/dev/null)" = "$owner" ]; then rm -rf "$dir"; fi
    done
fi
rm -f /tmp/scut-multiwan-deploying
logger -t scut-multiwan 'original scripts restored by deployment rollback'
printf 'ROLLED BACK\n'
