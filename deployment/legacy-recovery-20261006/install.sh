#!/bin/sh
# Baseline-bound code-only replacement. Never repeat on a changed installation.
set -eu
umask 077
STAGE=/tmp/scut-legacy-code-20261006
BACKUP=/root/scut-multiwan-legacy-code-backup-20261006
FILES='fix-qca-sta-rate native-watchdog usb-watchdog scut-rate-watchdog scut-link-recover'
cd "$STAGE"
sha256sum -c candidate.sha256
for file in $FILES; do test -s "$file"; wc -c "$file"; sh -n "$file"; done
sh -n rollback.sh
grep -q 'legacy-5 6 9 12 18 24 36 48 54' fix-qca-sta-rate
grep -q 'mw_portal_lock 5' scut-link-recover
grep -q 'REASSOCIATE' scut-link-recover
. /usr/lib/scut-multiwan/common.sh
mw_require_scan 30
mw_lock legacy-code-deploy 8
exec 5>>/tmp/scut-multiwan-locks/native-watchdog; flock -n 5 || exit 75
exec 4>>/tmp/scut-multiwan-locks/usb-watchdog; flock -n 4 || exit 75
exec 6>>/tmp/scut-multiwan-locks/native-best; flock -n 6 || exit 75
mw_lock qca-phy0-sta0 7
exec 3>>/tmp/scut-multiwan-locks/qca-phy2-sta0; flock -n 3 || exit 75
mw_portal_lock 5
cd /
sha256sum -c "$STAGE/baseline.sha256"
test ! -e /usr/bin/scut-link-recover
test ! -e "$BACKUP"
mkdir -m 700 "$BACKUP"
for file in $FILES; do
    if [ -e "/usr/bin/$file" ]; then cp -p "/usr/bin/$file" "$BACKUP/$file";
    else touch "$BACKUP/$file.absent"; fi
done
cp "$STAGE/rollback.sh" "$BACKUP/rollback.sh"
chmod 700 "$BACKUP/rollback.sh"
sha256sum /etc/config/wireless /etc/config/network /etc/config/firewall /etc/config/system /etc/config/dhcp /etc/campus-portal.conf /etc/scut-wired.conf /etc/crontabs/root /etc/scut-multiwan/native.session /etc/scut-multiwan/usb.session /etc/scut-multiwan/wired.session /etc/scut-multiwan/native.night-budget /etc/scut-multiwan/usb.night-budget /etc/scut-multiwan/wired.night-budget > "$BACKUP/preserved.sha256"
(cd "$BACKUP"; sha256sum fix-qca-sta-rate native-watchdog usb-watchdog scut-rate-watchdog > original.sha256; sha256sum -c original.sha256)
mkdir /tmp/scut-multiwan-deploying
DONE=0
cleanup() {
    rc=$?
    trap - EXIT INT TERM HUP
    if [ "$DONE" = 0 ]; then
        for file in $FILES; do
            dest="/usr/bin/$file"
            if [ -f "$BACKUP/$file.absent" ]; then rm -f "$dest";
            else cp -p "$BACKUP/$file" "$dest.legacy-restore.$$" && mv "$dest.legacy-restore.$$" "$dest" || exit 1; fi
        done
        echo 'code installation failed; baseline restored'
    fi
    for file in $FILES; do rm -f "/usr/bin/$file.legacy-new.$$"; done
    rmdir /tmp/scut-multiwan-deploying
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
# New helper goes first; old callers remain compatible during replacement.
for file in scut-link-recover fix-qca-sta-rate native-watchdog usb-watchdog scut-rate-watchdog; do
    dest="/usr/bin/$file"
    cp "$STAGE/$file" "$dest.legacy-new.$$"
    chmod 755 "$dest.legacy-new.$$"
    cmp "$STAGE/$file" "$dest.legacy-new.$$"
    sh -n "$dest.legacy-new.$$"
    mv "$dest.legacy-new.$$" "$dest"
done
cd /usr/bin
sha256sum -c "$STAGE/candidate.sha256"
sha256sum -c "$BACKUP/preserved.sha256"
DONE=1
date
echo LEGACY_RECOVERY_CODE_INSTALLED
