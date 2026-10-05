#!/bin/sh
# Restores only this round's four text files; never login/logout/restart services.
set -eu
umask 077
BACKUP=/root/scut-multiwan-portal-limit-backup-20261006
FILES='usr/bin/campus-portal-login.impl usr/bin/campus-usb-login.impl usr/bin/campus-portal-logout.impl usr/bin/campus-usb-logout.impl'
test -d /tmp/scut-multiwan-locks
exec 9>>/tmp/scut-multiwan-locks/portal
waited=0
while ! flock -n 9; do
    [ "$waited" -lt 30 ] || exit 75
    sleep 1
    waited=$((waited + 1))
done
cd "$BACKUP"
sha256sum -c original.sha256
for rel in $FILES; do test -s "files/$rel"; sh -n "files/$rel"; done
for rel in $FILES; do
    dest="/$rel"
    cp -p "files/$rel" "$dest.portal-limit-rollback.$$"
    sh -n "$dest.portal-limit-rollback.$$"
    mv "$dest.portal-limit-rollback.$$" "$dest"
done
for rel in $FILES; do
    expected=$(sha256sum "files/$rel"); expected=${expected%% *}
    actual=$(sha256sum "/$rel"); actual=${actual%% *}
    [ "$expected" = "$actual" ] || exit 1
done
echo 'original four Portal entries restored; live sessions untouched'
