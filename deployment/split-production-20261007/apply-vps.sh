#!/bin/sh
set -eu
B=/root/scut-split-production-backup-20261007
S=/tmp/scut-split-production-stage
test ! -e "$B"
test ! -e /etc/systemd/system/scut-bond.service.d/mixed.conf
test ! -e /etc/systemd/system/scut-bond-endpoints.service
test -z "$(ip mptcp endpoint show | awk '{for(i=2;i<NF;i++)if($i=="id"&&$(i+1)==214)print}')"
test -s "$S/scut-bond"
test "$(wc -c < "$S/scut-bond")" -eq 6582432
echo '7f011d3be6627dfb56f6f08b6606e73c92bd11d2107297b955963d822731e50a  /tmp/scut-split-production-stage/scut-bond' | sha256sum -c -
sh -n "$S/vps-queue.sh"
sh -n "$S/vps-endpoints.sh"
sh -n "$S/rollback-vps.sh"
mkdir -m700 "$B"
cp -p /usr/local/bin/scut-bond "$B/scut-bond"
cp -p /etc/scut-bond/server.json "$B/server.json"
cp -p /usr/local/lib/scut-bond/vps-queue.sh "$B/vps-queue.sh"
sha256sum /usr/local/bin/scut-bond /etc/scut-bond/server.json /usr/local/lib/scut-bond/vps-queue.sh > "$B/before.sha256"
cp "$S/rollback-vps.sh" "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
systemd-run --unit=scut-split-production-rollback --on-active=15m /bin/sh "$B/rollback.sh"
sed -e 's/^{/{ "transport_network":"tcp",/' -e 's/0.0.0.0:57501/[::]:57503/' "$B/server.json" > /etc/scut-bond/server.json.new
chown scutbond:scutbond /etc/scut-bond/server.json.new
chmod 600 /etc/scut-bond/server.json.new
test -s /etc/scut-bond/server.json.new
cp "$S/scut-bond" /usr/local/bin/scut-bond.new
chmod 755 /usr/local/bin/scut-bond.new
cp "$S/vps-queue.sh" /usr/local/lib/scut-bond/vps-queue.sh.new
chmod 755 /usr/local/lib/scut-bond/vps-queue.sh.new
cp "$S/vps-endpoints.sh" /usr/local/lib/scut-bond/vps-endpoints.sh.new
chmod 755 /usr/local/lib/scut-bond/vps-endpoints.sh.new
mkdir -p /etc/systemd/system/scut-bond.service.d
cp "$S/scut-bond-endpoints.service" /etc/systemd/system/scut-bond-endpoints.service.new
cp "$S/mixed.conf" /etc/systemd/system/scut-bond.service.d/mixed.conf.new
systemctl stop scut-bond
mv /usr/local/bin/scut-bond.new /usr/local/bin/scut-bond
mv /etc/scut-bond/server.json.new /etc/scut-bond/server.json
mv /usr/local/lib/scut-bond/vps-queue.sh.new /usr/local/lib/scut-bond/vps-queue.sh
mv /usr/local/lib/scut-bond/vps-endpoints.sh.new /usr/local/lib/scut-bond/vps-endpoints.sh
mv /etc/systemd/system/scut-bond-endpoints.service.new /etc/systemd/system/scut-bond-endpoints.service
mv /etc/systemd/system/scut-bond.service.d/mixed.conf.new /etc/systemd/system/scut-bond.service.d/mixed.conf
tc filter del dev ens18 parent 1: protocol ip pref 1
tc filter add dev ens18 parent 1: protocol ip pref 1 u32 match ip protocol 6 0xff match ip sport 57503 0xffff flowid 1:3
tc filter add dev ens18 parent 1: protocol ipv6 pref 2 u32 match ip6 protocol 6 0xff match ip6 sport 57503 0xffff flowid 1:2
tc qdisc del dev ens18 parent 1:2 handle 20:
tc qdisc add dev ens18 parent 1:2 handle 20: fq maxrate 26mbit quantum 1448 initial_quantum 1448
tc qdisc change dev ens18 parent 1:3 handle 30: fq maxrate 50mbit quantum 1448 initial_quantum 1448
systemctl daemon-reload
systemctl enable scut-bond-endpoints
systemctl start scut-bond
systemctl is-active scut-bond scut-bond-endpoints
