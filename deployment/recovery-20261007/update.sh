#!/bin/sh
# Final code revision; retain the original code/DNS rollback baseline.
set -eu
B=/root/scut-multiwan-recovery-backup-20261007
S=/tmp/scut-recovery-revision-20261007
. /usr/lib/scut-multiwan/common.sh
mw_require_scan 40
exec 5>>/tmp/scut-multiwan-locks/native-watchdog; flock -n 5 || exit 75
exec 6>>/tmp/scut-multiwan-locks/native-best; flock -n 6 || exit 75
exec 3>>/tmp/scut-multiwan-locks/dualwan-refresh; flock -n 3 || exit 75
exec 7>>/tmp/scut-multiwan-locks/qca-phy0-sta0; flock -n 7 || exit 75
exec 8>>/tmp/scut-multiwan-locks/qca-phy2-sta0; flock -n 8 || exit 75
mw_portal_lock 5
sha256sum -c "$B/installed.sha256"
[ "$(sha256sum /usr/bin/native-best | awk '{print $1}')" = 9ff9c9584cd53fa59f4e2e0851ca205b11583146dbeaa78ae2fe4a02e0f64868 ]
mkdir "$B/revision-before"
cp -p /usr/bin/native-best /usr/bin/native-watchdog "$B/revision-before/"
sha256sum /etc/config/network /etc/config/wireless /etc/config/dhcp /etc/config/firewall /etc/campus-portal.conf /etc/scut-wired.conf /etc/crontabs/root /etc/scut-multiwan/*.session /etc/scut-multiwan/*.night-budget > "$B/revision-preserved.sha256"
for f in native-best native-watchdog; do test -s "$S/$f"; wc -c "$S/$f"; sh -n "$S/$f"; done
mkdir /tmp/scut-multiwan-deploying
DONE=0
cleanup() {
 r=$?; trap - EXIT INT TERM HUP
 if [ "$DONE" = 0 ]; then
  for f in native-best native-watchdog; do cp -p "$B/revision-before/$f" "/usr/bin/$f.revision-restore.$$"; mv "/usr/bin/$f.revision-restore.$$" "/usr/bin/$f"; done
 fi
 sha256sum /usr/bin/native-best /usr/bin/native-watchdog /etc/config/dhcp > "$B/installed.sha256"
 rmdir /tmp/scut-multiwan-deploying
 exit "$r"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
for f in native-best native-watchdog; do
 cp "$S/$f" "/usr/bin/$f.revision-new.$$"; chmod 755 "/usr/bin/$f.revision-new.$$"
 cmp "$S/$f" "/usr/bin/$f.revision-new.$$"; sh -n "/usr/bin/$f.revision-new.$$"
 mv "/usr/bin/$f.revision-new.$$" "/usr/bin/$f"
done
sha256sum -c "$B/revision-preserved.sha256"
DONE=1
date; echo RECOVERY_FINAL_REVISION_INSTALLED
