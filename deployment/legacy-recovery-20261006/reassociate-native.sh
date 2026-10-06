#!/bin/sh
# One-shot, baseline diagnosis recovery. No login, logout, DHCP or UCI changes.
set -eu
. /usr/lib/scut-multiwan/common.sh
mw_require_scan 30
mw_lock native-best 8
exec 6>>/tmp/scut-multiwan-locks/native-watchdog
flock -n 6 || exit 75
mw_lock qca-phy0-sta0 7
mw_online wan 6 && mw_online phy3-sta0 6 || exit 1
BACKUP=/root/scut-multiwan-legacy-backup-20261006
umask 077
mkdir "$BACKUP"
cp -p /etc/config/wireless /etc/config/network "$BACKUP/"
sha256sum /etc/config/wireless /etc/config/network /etc/scut-multiwan/native.session /etc/scut-multiwan/usb.session /etc/scut-multiwan/wired.session > "$BACKUP/preserved.sha256"
cp -p /usr/bin/fix-qca-sta-rate "$BACKUP/"
mw_portal_lock 5
mw_require_scan 15
ubus call wpa_supplicant.phy0-sta0 control '{"command":"REASSOCIATE"}'
sleep 2
iw dev phy0-sta0 link
exec 9>&-
sleep 3
sha256sum -c "$BACKUP/preserved.sha256"
iw dev phy0-sta0 info
iw dev phy0-sta0 station dump | grep -E 'bitrate|connected time|tx failed|signal'
mw_online phy0-sta0 6
/usr/bin/dualwan-refresh force
date
