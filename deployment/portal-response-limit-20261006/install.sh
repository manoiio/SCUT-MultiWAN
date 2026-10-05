#!/bin/sh
# This baseline-bound installer is prepared locally; do not run without approval.
set -eu
umask 077
STAGE=/tmp/scut-portal-response-limit-20261006
BACKUP=/root/scut-multiwan-portal-limit-backup-20261006
FILES='usr/bin/campus-portal-login.impl usr/bin/campus-usb-login.impl usr/bin/campus-portal-logout.impl usr/bin/campus-usb-logout.impl'
cd "$STAGE"
sha256sum -c candidate.sha256 || exit 1
for rel in $FILES; do
    test -s "files/$rel"
    printf '%s bytes=' "$rel"; wc -c < "files/$rel"
    sh -n "files/$rel"
    grep -q -- '--max-filesize 1048576' "files/$rel"
    grep -q '^CURL_RC=\$?' "files/$rel"
done
test -d /tmp/scut-multiwan-locks
exec 9>>/tmp/scut-multiwan-locks/portal
waited=0
while ! flock -n 9; do
    [ "$waited" -lt 30 ] || exit 75
    sleep 1
    waited=$((waited + 1))
done
cd /
sha256sum -c "$STAGE/baseline.sha256" || exit 1
test ! -e "$BACKUP" || { echo 'backup already exists; refusing replay'; exit 1; }
mkdir -m 700 "$BACKUP"
for rel in $FILES; do
    mkdir -p "$BACKUP/files/${rel%/*}"
    cp -p "/$rel" "$BACKUP/files/$rel"
done
cp "$STAGE/rollback.sh" "$BACKUP/rollback.sh"
chmod 700 "$BACKUP/rollback.sh"
cd "$BACKUP"
for rel in $FILES; do sha256sum "files/$rel"; done > original.sha256
sha256sum -c original.sha256 || exit 1
sha256sum /etc/config/network /etc/config/wireless /etc/config/firewall \
    /etc/config/system /etc/config/dhcp /etc/campus-portal.conf \
    /etc/scut-wired.conf /etc/crontabs/root \
    /etc/scut-multiwan/native.session /etc/scut-multiwan/usb.session \
    /etc/scut-multiwan/wired.session /etc/scut-multiwan/native.night-budget \
    /etc/scut-multiwan/usb.night-budget /etc/scut-multiwan/wired.night-budget \
    > preserved.sha256
restore_on_error() {
    rc=$?
    trap - EXIT INT TERM
    for rel in $FILES; do
        dest="/$rel"
        cp -p "$BACKUP/files/$rel" "$dest.portal-limit-restore.$$" &&
            mv "$dest.portal-limit-restore.$$" "$dest" || { echo 'restore failed; inspect backup'; exit 1; }
    done
    echo 'installation failed; original four files restored'
    exit "$rc"
}
trap restore_on_error EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
for rel in $FILES; do
    dest="/$rel"
    cp "$STAGE/files/$rel" "$dest.portal-limit-new.$$"
    chmod 755 "$dest.portal-limit-new.$$"
    sh -n "$dest.portal-limit-new.$$"
    mv "$dest.portal-limit-new.$$" "$dest"
done
cd /
sha256sum -c "$STAGE/installed.sha256"
sha256sum -c "$BACKUP/preserved.sha256"
trap - EXIT INT TERM
echo 'four Portal entries installed; no service/authentication action performed'
