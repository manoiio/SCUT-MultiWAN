#!/bin/sh
set -eu
B=/root/scut-mixed-production-backup-20261007
test -s "$B/scut-bond"
test -s "$B/server.json"
test -s "$B/vps-queue.sh"
systemctl stop scut-bond
systemctl disable --now scut-bond-endpoints || :
rm -f /etc/systemd/system/scut-bond.service.d/mixed.conf /etc/systemd/system/scut-bond-endpoints.service
systemctl daemon-reload
for f in scut-bond server.json vps-queue.sh; do
 case "$f" in
  scut-bond) target=/usr/local/bin/scut-bond;;
  server.json) target=/etc/scut-bond/server.json;;
  vps-queue.sh) target=/usr/local/lib/scut-bond/vps-queue.sh;;
 esac
 cp -p "$B/$f" "$target.rollback"
 mv "$target.rollback" "$target"
done
tc filter del dev ens18 parent 1: protocol ipv6 pref 2 || :
tc filter del dev ens18 parent 1: protocol ip pref 1 || :
tc filter add dev ens18 parent 1: protocol ip pref 1 u32 match ip protocol 6 0xff match ip sport 57501 0xffff flowid 1:3
tc qdisc del dev ens18 parent 1:2 handle 20:
tc qdisc add dev ens18 parent 1:2 handle 20: fq_codel
tc qdisc change dev ens18 parent 1:3 handle 30: fq maxrate 50mbit quantum 1448 initial_quantum 1448
rm -f /usr/local/lib/scut-bond/vps-endpoints.sh
systemctl restart scut-bond
systemctl is-active scut-bond
sha256sum -c "$B/before.sha256"
