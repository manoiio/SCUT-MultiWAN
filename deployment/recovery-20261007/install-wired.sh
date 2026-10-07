#!/bin/sh
set -eu
umask 077
B=/root/scut-multiwan-recovery-wired-backup-20261007
S=/tmp/scut-recovery-wired-20261007
. /usr/lib/scut-multiwan/common.sh
mw_require_scan 60
[ "$(sha256sum /usr/bin/scutclient-wired | awk '{print $1}')" = d390261c58d575499902fc3b6da60d292057275c54a2fa3f22873f833ac62b25 ]
[ "$(sha256sum "$S/scutclient-wired" | awk '{print $1}')" = 787e9c9ebd4934e72cb6ea0e9981a1b26bd9489d4ca83b8fcd783e40e8aedd79 ]
test -s "$S/scutclient-wired"; wc -c "$S/scutclient-wired"
"$S/wired-protocol"
test ! -e "$B"; mkdir -m 700 "$B"
cp -p /usr/bin/scutclient-wired "$B/scutclient-wired"
cp "$S/rollback-wired.sh" "$B/rollback.sh"; chmod 700 "$B/rollback.sh"
(cd "$B"; sha256sum scutclient-wired > original.sha256)
sha256sum /etc/config/network /etc/config/wireless /etc/config/dhcp /etc/campus-portal.conf /etc/scut-wired.conf /etc/crontabs/root /etc/scut-multiwan/native.session /etc/scut-multiwan/usb.session > "$B/preserved.sha256"
# Let the supported stop path confirm release; never fabricate 'none'.
/etc/init.d/scut-wired stop
I=0
while [ "$I" -lt 15 ]; do
 if grep -qx 'none wan' /etc/scut-multiwan/wired.session; then break; fi
 sleep 1; I=$((I+1))
done
grep -qx 'none wan' /etc/scut-multiwan/wired.session || { echo 'Wired release unconfirmed; replacement refused'; exit 75; }
cp "$S/scutclient-wired" /usr/bin/scutclient-wired.recovery-new
chmod 755 /usr/bin/scutclient-wired.recovery-new
cmp "$S/scutclient-wired" /usr/bin/scutclient-wired.recovery-new
mv /usr/bin/scutclient-wired.recovery-new /usr/bin/scutclient-wired
sha256sum /usr/bin/scutclient-wired > "$B/installed.sha256"
sha256sum -c "$B/preserved.sha256"
/etc/init.d/scut-wired start
date; echo WIRED_WAIT_FIX_INSTALLED
