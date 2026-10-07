#!/bin/sh
set -eu
B=/root/scut-multiwan-recovery-wired-backup-20261007
. /usr/lib/scut-multiwan/common.sh
mw_require_scan 40
(cd "$B"; sha256sum -c original.sha256)
sha256sum -c "$B/installed.sha256"
/etc/init.d/scut-wired stop
I=0
while [ "$I" -lt 15 ]; do
 grep -qx 'none wan' /etc/scut-multiwan/wired.session && break
 sleep 1; I=$((I+1))
done
grep -qx 'none wan' /etc/scut-multiwan/wired.session || { echo 'Wired release unconfirmed; rollback refused'; exit 75; }
cp -p "$B/scutclient-wired" /usr/bin/scutclient-wired.recovery-old
mv /usr/bin/scutclient-wired.recovery-old /usr/bin/scutclient-wired
/etc/init.d/scut-wired start
echo WIRED_WAIT_FIX_ROLLED_BACK
