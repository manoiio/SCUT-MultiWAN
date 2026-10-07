#!/bin/sh
set -eu
B=/root/scut-wired-admission-backup-20261007
/etc/init.d/scut-wired stop
sleep 2
read -r stored dev extra < /etc/scut-multiwan/wired.session
if test "$stored" != none; then /usr/bin/scutclient-wired --release; fi
read -r stored dev extra < /etc/scut-multiwan/wired.session
test "$stored" = none; test "$dev" = wan; test -z "$extra"
for f in scut-wired-gate scutclient-wired; do
    cp "$B/$f" "/usr/bin/$f.new"; chmod 755 "/usr/bin/$f.new"
    mv "/usr/bin/$f.new" "/usr/bin/$f"
done
sha256sum -c "$B/original.sha256"
sync
/etc/init.d/scut-wired start
