#!/bin/sh
# Code and resolver configuration only: do not restore radios or session ledgers.
set -eu
B=/root/scut-multiwan-recovery-backup-20261007
. /usr/lib/scut-multiwan/common.sh
mw_require_scan 40
exec 5>>/tmp/scut-multiwan-locks/native-watchdog; flock -n 5 || exit 75
exec 6>>/tmp/scut-multiwan-locks/native-best; flock -n 6 || exit 75
exec 3>>/tmp/scut-multiwan-locks/dualwan-refresh; flock -n 3 || exit 75
exec 7>>/tmp/scut-multiwan-locks/qca-phy0-sta0; flock -n 7 || exit 75
exec 8>>/tmp/scut-multiwan-locks/qca-phy2-sta0; flock -n 8 || exit 75
mw_portal_lock 10
(cd "$B"; sha256sum -c original.sha256)
sha256sum -c "$B/installed.sha256"
mkdir /tmp/scut-multiwan-deploying
trap 'rmdir /tmp/scut-multiwan-deploying' EXIT
for f in native-best native-watchdog; do
 cp -p "$B/$f" "/usr/bin/$f.recovery-old.$$"; sh -n "/usr/bin/$f.recovery-old.$$"
 mv "/usr/bin/$f.recovery-old.$$" "/usr/bin/$f"
done
cp -p "$B/dhcp" /etc/config/dhcp.recovery-old
mv /etc/config/dhcp.recovery-old /etc/config/dhcp
/etc/init.d/dnsmasq restart >/dev/null 2>&1
date; echo RECOVERY_FIX_ROLLED_BACK
