#!/bin/sh
set -eu
B=/root/scut-port-backup-20261007
test ! -e "$B"
mkdir -m700 "$B"
cp -p /etc/scut-bond/client.json "$B/client.json"
sha256sum /etc/scut-bond/client.json > "$B/before.sha256"
cp /tmp/scut-port-rollback.sh "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
sh -n "$B/rollback.sh"
sed 's/58.252.223.164:57501/58.252.223.164:57502/' /etc/scut-bond/client.json > /etc/scut-bond/client.json.new
chmod 600 /etc/scut-bond/client.json.new
test -s /etc/scut-bond/client.json.new
test "$(jsonfilter -i /etc/scut-bond/client.json.new -e @.server)" = '58.252.223.164:57502'
(trap '' HUP; sleep 900; sh "$B/rollback.sh") </dev/null > "$B/guard.log" 2>&1 &
echo "$!" > "$B/guard.pid"
mv /etc/scut-bond/client.json.new /etc/scut-bond/client.json
/etc/init.d/scut-bond restart
jsonfilter -i /etc/scut-bond/client.json -e @.server -e @.listen
