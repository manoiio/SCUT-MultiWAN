#!/bin/sh
set -eu
B=/root/scut-wired-reboot-backup-20261007
(cd "$B"; sha256sum -c original.sha256)
sha256sum -c "$B/installed.sha256"
/etc/init.d/scut-wired stop
# Never replace an active process or erase its persistent session.
exec 8>/tmp/scut-multiwan-locks/wired-engine
flock -n 8 || exit 75
[ ! -f /tmp/scut-wired-ready ] || exit 75
cp -p "$B/scutclient-wired" /usr/bin/scutclient-wired.reboot-old
mv /usr/bin/scutclient-wired.reboot-old /usr/bin/scutclient-wired
cp -p "$B/scut-wired-gate" /usr/bin/scut-wired-gate.reboot-old
mv /usr/bin/scut-wired-gate.reboot-old /usr/bin/scut-wired-gate
flock -u 8
/etc/init.d/scut-wired start
