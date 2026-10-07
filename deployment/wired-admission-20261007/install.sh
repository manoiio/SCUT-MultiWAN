#!/bin/sh
# Historical one-time deployment; does not reboot the router.
set -eu
B=/root/scut-wired-admission-backup-20261007
S=/tmp/scut-wired-admission-stage-20261007
test ! -e "$B"
echo 'ff9bce81d102357b290da24f56c4df1747ea81fce003157ef234826148a982af  /usr/bin/scut-wired-gate' | sha256sum -c -
echo '05eafaf1f717dc876fcb526f118c8d6c796db00c7cbe2e1d9bbc643b73b20f2e  /usr/bin/scutclient-wired' | sha256sum -c -
sha256sum -c "$S/candidate.sha256"
sh -n "$S/scut-wired-gate"
test -s "$S/scutclient-wired"
"$S/scutclient-wired" --version
mkdir "$B"; chmod 700 "$B"
cp /usr/bin/scut-wired-gate /usr/bin/scutclient-wired "$B/"
sha256sum /usr/bin/scut-wired-gate /usr/bin/scutclient-wired > "$B/original.sha256"
sha256sum /etc/config/network /etc/config/wireless /etc/config/firewall /etc/config/dhcp /etc/scut-multiwan/native.session /etc/scut-multiwan/usb.session /etc/campus-portal.conf > "$B/preserved.sha256"
cp "$S/rollback.sh" "$B/rollback.sh"; chmod 700 "$B/rollback.sh"
trap 'rc=$?; [ "$rc" = 0 ] || sh "$B/rollback.sh"; exit "$rc"' EXIT
/etc/init.d/scut-wired stop
sleep 2
read -r stored dev extra < /etc/scut-multiwan/wired.session
if test "$stored" != none; then /usr/bin/scutclient-wired --release; fi
read -r stored dev extra < /etc/scut-multiwan/wired.session
test "$stored" = none; test "$dev" = wan; test -z "$extra"
test ! -e /tmp/scut-wired-ready
for f in scut-wired-gate scutclient-wired; do
    cp "$S/$f" "/usr/bin/$f.new"; chmod 755 "/usr/bin/$f.new"
    mv "/usr/bin/$f.new" "/usr/bin/$f"
done
sha256sum /usr/bin/scut-wired-gate /usr/bin/scutclient-wired
sha256sum -c "$B/preserved.sha256"
sync
/etc/init.d/scut-wired start
date -Iseconds
