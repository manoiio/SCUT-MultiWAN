#!/bin/sh
set -u
systemctl disable --now scut-bond.service 2>/dev/null || :
systemctl disable --now scut-bond-queue.service 2>/dev/null || :
case "$(tc qdisc show dev ens18)" in *'qdisc prio 1:'*) tc qdisc del dev ens18 root;; esac
rm -f /etc/systemd/system/scut-bond.service /etc/systemd/system/scut-bond-queue.service /usr/local/bin/scut-bond
rm -rf /etc/scut-bond /usr/local/lib/scut-bond
systemctl daemon-reload
if [ -f /root/scut-bond-backup-20261007-v2/created-user ]; then userdel scutbond 2>/dev/null || :; fi
tc qdisc show dev ens18
