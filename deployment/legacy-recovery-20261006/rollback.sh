#!/bin/sh
# Restore only this round's code; do not undo healthy associations or sessions.
set -eu
umask 077
BACKUP=/root/scut-multiwan-legacy-code-backup-20261006
. /usr/lib/scut-multiwan/common.sh
mw_require_active 30
mw_lock legacy-code-deploy 8
exec 5>>/tmp/scut-multiwan-locks/native-watchdog; flock -n 5 || exit 75
exec 4>>/tmp/scut-multiwan-locks/usb-watchdog; flock -n 4 || exit 75
exec 6>>/tmp/scut-multiwan-locks/native-best; flock -n 6 || exit 75
mw_lock qca-phy0-sta0 7
exec 3>>/tmp/scut-multiwan-locks/qca-phy2-sta0; flock -n 3 || exit 75
mw_portal_lock 5
cd "$BACKUP"
sha256sum -c original.sha256
for file in fix-qca-sta-rate native-watchdog usb-watchdog scut-rate-watchdog; do test -s "$file"; sh -n "$file"; done
mkdir /tmp/scut-multiwan-deploying
trap 'rmdir /tmp/scut-multiwan-deploying' EXIT
for file in fix-qca-sta-rate native-watchdog usb-watchdog scut-rate-watchdog; do
    dest="/usr/bin/$file"
    cp -p "$file" "$dest.legacy-rollback.$$"
    sh -n "$dest.legacy-rollback.$$"
    mv "$dest.legacy-rollback.$$" "$dest"
done
test -f scut-link-recover.absent && rm -f /usr/bin/scut-link-recover
for file in fix-qca-sta-rate native-watchdog usb-watchdog scut-rate-watchdog; do cmp "$file" "/usr/bin/$file"; done
echo 'original code restored; associations, routes, configuration and session records preserved'
