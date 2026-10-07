#!/bin/sh
set -eu
STAGE=/tmp/scut-bond-deploy
BACKUP=/root/scut-bond-backup-20261007-v2
for p in /usr/bin/scut-bond /usr/bin/scut-bond-paths /etc/init.d/scut-bond /etc/scut-bond; do [ ! -e "$p" ]; done
[ ! -d "$BACKUP" ]
[ -z "$(ip mptcp endpoint show)" ]
for t in 201 202 203; do [ -z "$(ip route show table "$t" 2>/dev/null)" ]; done
[ -z "$(ip rule show | awk '$1=="80:" || $1=="81:" || $1=="82:"')" ]
for f in scut-bond scut-bond-paths scut-bond.init client.json server.crt rollback.sh; do [ -s "$STAGE/$f" ]; done
sh -n "$STAGE/scut-bond-paths" "$STAGE/scut-bond.init" "$STAGE/rollback.sh"
mkdir -m 700 "$BACKUP"
cp "$STAGE/rollback.sh" "$BACKUP/rollback.sh"
chmod 700 "$BACKUP/rollback.sh"
sha256sum /etc/config/network /etc/config/wireless /etc/config/firewall /etc/config/dhcp /etc/scut-multiwan/native.session /etc/scut-multiwan/usb.session /etc/scut-multiwan/wired.session > "$BACKUP/preserved.sha256"
ip route show table 103 > "$BACKUP/table103.before"
ip mptcp limits show > "$BACKUP/mptcp-limits.before"
(trap '' HUP; sleep 1800; sh "$BACKUP/rollback.sh") > "$BACKUP/guard.log" 2>&1 < /dev/null &
echo $! > "$BACKUP/guard.pid"
sleep 1
kill -0 "$(cat "$BACKUP/guard.pid")"
success=0
trap '[ "$success" = 1 ] || sh "$BACKUP/rollback.sh"' EXIT
mkdir -m 700 /etc/scut-bond
cp "$STAGE/client.json" /etc/scut-bond/client.json; chmod 600 /etc/scut-bond/client.json
cp "$STAGE/server.crt" /etc/scut-bond/server.crt; chmod 600 /etc/scut-bond/server.crt
for pair in 'scut-bond /usr/bin/scut-bond' 'scut-bond-paths /usr/bin/scut-bond-paths' 'scut-bond.init /etc/init.d/scut-bond'; do
    set -- $pair
    cp "$STAGE/$1" "$2.new"; chmod 755 "$2.new"; mv "$2.new" "$2"
done
sha256sum -c "$BACKUP/preserved.sha256"
/etc/init.d/scut-bond enable
/etc/init.d/scut-bond start
success=1
