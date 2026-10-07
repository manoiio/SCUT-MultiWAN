#!/bin/sh
set -eu
B=/root/scut-port-backup-20261007
test -s "$B/server.json"
test -s "$B/vps-queue.sh"
cp -p "$B/server.json" /etc/scut-bond/server.json.rollback
mv /etc/scut-bond/server.json.rollback /etc/scut-bond/server.json
cp -p "$B/vps-queue.sh" /usr/local/lib/scut-bond/vps-queue.sh.rollback
mv /usr/local/lib/scut-bond/vps-queue.sh.rollback /usr/local/lib/scut-bond/vps-queue.sh
tc filter del dev ens18 parent 1: protocol ip pref 1
tc filter add dev ens18 parent 1: protocol ip pref 1 u32 match ip protocol 6 0xff match ip sport 57501 0xffff flowid 1:3
tc qdisc change dev ens18 parent 1:3 handle 30: fq maxrate 50mbit quantum 1448 initial_quantum 1448
systemctl restart scut-bond
systemctl is-active scut-bond
