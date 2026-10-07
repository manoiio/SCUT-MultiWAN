#!/bin/sh
set -eu
# Baseline is fq_codel handle 0. Limit only packets from proxy TCP port 57501.
tc qdisc show dev ens18 | grep -q '^qdisc fq_codel 0: root' || exit 1
tc qdisc replace dev ens18 root handle 1: prio bands 3 priomap 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
tc qdisc add dev ens18 parent 1:1 handle 10: fq_codel
tc qdisc add dev ens18 parent 1:2 handle 20: fq_codel
tc qdisc add dev ens18 parent 1:3 handle 30: fq maxrate 45mbit quantum 1448 initial_quantum 1448
tc filter add dev ens18 parent 1: protocol ip pref 1 u32 match ip protocol 6 0xff match ip sport 57501 0xffff flowid 1:3
tc qdisc show dev ens18
tc filter show dev ens18 parent 1:
