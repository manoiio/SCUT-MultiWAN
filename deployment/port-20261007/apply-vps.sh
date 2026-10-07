#!/bin/sh
set -eu
B=/root/scut-port-backup-20261007
test ! -e "$B"
mkdir -m700 "$B"
cp -p /etc/scut-bond/server.json "$B/server.json"
cp -p /usr/local/lib/scut-bond/vps-queue.sh "$B/vps-queue.sh"
sha256sum /etc/scut-bond/server.json /usr/local/lib/scut-bond/vps-queue.sh > "$B/before.sha256"
cp /tmp/scut-port-rollback.sh "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
sh -n "$B/rollback.sh"
sed 's/0.0.0.0:57501/0.0.0.0:57502/' /etc/scut-bond/server.json > /etc/scut-bond/server.json.new
chown scutbond:scutbond /etc/scut-bond/server.json.new
chmod 600 /etc/scut-bond/server.json.new
test -s /etc/scut-bond/server.json.new
if cmp -s /etc/scut-bond/server.json.new "$B/server.json"; then exit 1; fi
sed -e 's/57501/57502/g' -e 's/50mbit/45mbit/' /usr/local/lib/scut-bond/vps-queue.sh > /usr/local/lib/scut-bond/vps-queue.sh.new
chmod 755 /usr/local/lib/scut-bond/vps-queue.sh.new
sh -n /usr/local/lib/scut-bond/vps-queue.sh.new
systemd-run --unit=scut-port-rollback --on-active=15m "$B/rollback.sh"
systemctl stop scut-port-test
systemctl stop scut-port-cleanup.timer
tc filter del dev ens18 parent 1: protocol ip pref 2
tc qdisc del dev ens18 parent 1:2 handle 20:
tc qdisc add dev ens18 parent 1:2 handle 20: fq_codel
mv /etc/scut-bond/server.json.new /etc/scut-bond/server.json
mv /usr/local/lib/scut-bond/vps-queue.sh.new /usr/local/lib/scut-bond/vps-queue.sh
tc filter del dev ens18 parent 1: protocol ip pref 1
tc filter add dev ens18 parent 1: protocol ip pref 1 u32 match ip protocol 6 0xff match ip sport 57502 0xffff flowid 1:3
tc qdisc change dev ens18 parent 1:3 handle 30: fq maxrate 45mbit quantum 1448 initial_quantum 1448
systemctl restart scut-bond
systemctl is-active scut-bond
tc qdisc show dev ens18
tc filter show dev ens18 parent 1:
