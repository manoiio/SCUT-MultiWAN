#!/bin/sh
set -eu
. /usr/lib/scut-multiwan/common.sh
mw_require_scan 30
mw_lock usb-watchdog 8
mw_online wan 6 && mw_online phy0-sta0 6 || exit 1
mw_portal_lock 5
mw_require_scan 15
ubus call wpa_supplicant.phy3-sta0 control '{"command":"REASSOCIATE"}'
sleep 2
iw dev phy3-sta0 link
exec 9>&-
sleep 3
sha256sum -c /root/scut-multiwan-legacy-backup-20261006/preserved.sha256
iw dev phy3-sta0 info
iw dev phy3-sta0 station dump | grep -E 'bitrate|connected time|tx failed|signal'
mw_online phy3-sta0 6
date
