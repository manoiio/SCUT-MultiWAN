#!/bin/sh
set -eu
B=/root/scut-split-production-backup-20261007
S=/tmp/scut-split-production-stage
test ! -e "$B"
test ! -e /etc/scut-bond/mixed.enabled
test -s "$S/scut-bond"
test "$(wc -c < "$S/scut-bond")" -eq 6095008
echo 'd98b44a62776c1c6acb2fd25be80fa5058519107f06a963a2c6b8ebc06a62d01  /tmp/scut-split-production-stage/scut-bond' | sha256sum -c -
sh -n "$S/paths"
sh -n "$S/rollback-router.sh"
mkdir -m700 "$B"
cp -p /usr/bin/scut-bond "$B/scut-bond"
cp -p /usr/bin/scut-bond-paths "$B/scut-bond-paths"
cp -p /etc/scut-bond/client.json "$B/client.json"
sha256sum /usr/bin/scut-bond /usr/bin/scut-bond-paths /etc/scut-bond/client.json > "$B/before.sha256"
sha256sum /etc/config/network /etc/config/wireless /etc/config/firewall /etc/config/dhcp /etc/scut-multiwan/native.session /etc/scut-multiwan/usb.session /etc/scut-multiwan/wired.session > "$B/preserved.sha256"
cp "$S/rollback-router.sh" "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
(trap '' HUP; sleep 900; sh "$B/rollback.sh") </dev/null > "$B/guard.log" 2>&1 &
p=$!
echo "$p" > "$B/guard.pid"
awk '{print $22}' /proc/$p/stat > "$B/guard.start"
readlink /proc/$p/exe > "$B/guard.exe"
sed -e 's/^{/{ "transport_network":"tcp","fallback_server":"58.252.223.164:57503","fallback_local_address_file":"\/var\/run\/scut-bond\/fallback-address",/' -e 's/58.252.223.164:57501/[2409:8a55:727a:5740:be24:11ff:fea4:ae10]:57503/' "$B/client.json" > /etc/scut-bond/client.json.new
chmod 600 /etc/scut-bond/client.json.new
test -s /etc/scut-bond/client.json.new
cp "$S/scut-bond" /usr/bin/scut-bond.new
chmod 755 /usr/bin/scut-bond.new
cp "$S/paths" /usr/bin/scut-bond-paths.new
chmod 755 /usr/bin/scut-bond-paths.new
: > /etc/scut-bond/mixed.enabled.new
chmod 600 /etc/scut-bond/mixed.enabled.new
/etc/init.d/scut-bond stop
mv /usr/bin/scut-bond.new /usr/bin/scut-bond
mv /usr/bin/scut-bond-paths.new /usr/bin/scut-bond-paths
mv /etc/scut-bond/client.json.new /etc/scut-bond/client.json
mv /etc/scut-bond/mixed.enabled.new /etc/scut-bond/mixed.enabled
/etc/init.d/scut-bond start
sha256sum -c "$B/preserved.sha256"
