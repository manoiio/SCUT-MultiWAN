#!/bin/sh
set -eu
S=/tmp/scut-bbr50-20261007
test -s "$S/scut-bond"
test "$(sysctl -n net.ipv4.tcp_recovery)" = 1
test -z "$(ss -Hln sport = :57502)"
! tc filter show dev ens18 parent 1: | grep -q 'pref 2 '
tc qdisc show dev ens18 | grep -q '^qdisc fq_codel 20: parent 1:2 '
! lsmod | grep -q '^tcp_bbr '
cat > "$S/cleanup.sh" <<'CLEAN'
#!/bin/sh
systemctl stop scut-bbr50-20261007.service
tc filter del dev ens18 parent 1: protocol ip pref 2
tc qdisc del dev ens18 parent 1:2 handle 20:
tc qdisc add dev ens18 parent 1:2 handle 20: fq_codel
modprobe -r tcp_bbr
tc qdisc show dev ens18
sysctl net.ipv4.tcp_available_congestion_control
CLEAN
chmod 700 "$S/cleanup.sh"
systemd-run --unit=scut-bbr50-cleanup-20261007 --on-active=900s --timer-property=AccuracySec=1s /bin/sh "$S/cleanup.sh"
modprobe tcp_bbr
tc qdisc del dev ens18 parent 1:2 handle 20:
tc qdisc add dev ens18 parent 1:2 handle 20: fq quantum 1448 initial_quantum 1448 maxrate 50mbit
tc filter add dev ens18 parent 1: protocol ip pref 2 u32 match ip protocol 6 0xff match ip sport 57502 0xffff flowid 1:2
# The existing flat server configuration has no nested objects. Add a final
# override (Go JSON decoding uses the last value) without exposing its token.
sed 's/0\.0\.0\.0:57501/0.0.0.0:57502/;s/}/,"congestion_control":"bbr"}/' /etc/scut-bond/server.json > "$S/server.json"
grep -q '0.0.0.0:57502' "$S/server.json"
chgrp scutbond "$S" "$S/server.json"
chmod 750 "$S"
chmod 640 "$S/server.json"
chmod 755 "$S/scut-bond"
systemd-run --unit=scut-bbr50-20261007 --uid=scutbond --gid=scutbond --property=AmbientCapabilities=CAP_NET_ADMIN --property=NoNewPrivileges=yes --property=MemoryMax=128M "$S/scut-bond" -config "$S/server.json"
sleep 1
systemctl is-active scut-bbr50-20261007.service
ss -lnt 'sport = :57502'
