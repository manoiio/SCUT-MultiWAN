#!/bin/sh
set -u
systemctl stop scut-bond-mixed-test 2>/dev/null || :
ip mptcp endpoint delete id 214 2>/dev/null || :
tc filter del dev ens18 parent 1: protocol ip pref 3 2>/dev/null || :
tc filter del dev ens18 parent 1: protocol ipv6 pref 4 2>/dev/null || :
tc qdisc del dev ens18 parent 1:2 2>/dev/null || :
tc qdisc add dev ens18 parent 1:2 handle 20: fq_codel
