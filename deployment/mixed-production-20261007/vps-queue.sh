#!/bin/sh
set -eu
# Only packets originating from this proxy port enter the paced band.
tc qdisc show dev ens18 | grep -q '^qdisc fq_codel 0: root' || exit 1
tc qdisc replace dev ens18 root handle 1: prio bands 3 priomap 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
tc qdisc add dev ens18 parent 1:1 handle 10: fq_codel
tc qdisc add dev ens18 parent 1:2 handle 20: fq maxrate 45mbit quantum 1448 initial_quantum 1448
tc qdisc add dev ens18 parent 1:3 handle 30: fq maxrate 50mbit quantum 1448 initial_quantum 1448
tc filter add dev ens18 parent 1: protocol ip pref 1 u32 match ip protocol 6 0xff match ip sport 57503 0xffff flowid 1:2
tc filter add dev ens18 parent 1: protocol ipv6 pref 2 u32 match ip6 protocol 6 0xff match ip6 sport 57503 0xffff flowid 1:2
