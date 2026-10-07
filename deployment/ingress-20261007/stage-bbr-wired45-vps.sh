#!/bin/sh
set -eu
S=/tmp/scut-bbr50-20261007
systemctl is-active scut-bbr50-20261007.service
test "$(sysctl -n net.ipv4.tcp_recovery)" = 1
tc qdisc show dev ens18 | grep -q '^qdisc fq_codel 10: parent 1:1 '
cat > "$S/cleanup.sh" <<'CLEAN'
#!/bin/sh
systemctl stop scut-bbr50-20261007.service
tc filter del dev ens18 parent 1: protocol ip pref 2
tc filter del dev ens18 parent 1: protocol ip pref 3
tc qdisc del dev ens18 parent 1:1 handle 10:
tc qdisc add dev ens18 parent 1:1 handle 10: fq_codel
tc qdisc del dev ens18 parent 1:2 handle 20:
tc qdisc add dev ens18 parent 1:2 handle 20: fq_codel
modprobe -r tcp_bbr
tc qdisc show dev ens18
sysctl net.ipv4.tcp_available_congestion_control
CLEAN
chmod 700 "$S/cleanup.sh"
tc filter del dev ens18 parent 1: protocol ip pref 2
tc qdisc del dev ens18 parent 1:1 handle 10:
tc qdisc add dev ens18 parent 1:1 handle 10: fq quantum 1448 initial_quantum 1448 maxrate 45mbit
tc filter add dev ens18 parent 1: protocol ip pref 2 u32 match ip protocol 6 0xff match ip sport 57502 0xffff match ip dst 110.64.88.149/32 flowid 1:1
tc filter add dev ens18 parent 1: protocol ip pref 3 u32 match ip protocol 6 0xff match ip sport 57502 0xffff flowid 1:2
tc filter show dev ens18 parent 1:
