#!/bin/sh
set -eu
BACKUP=/root/scut-bond-pacing-backup-20261007
test -s "$BACKUP/vps-queue.sh"
sh -n "$BACKUP/vps-queue.sh"
cp -p "$BACKUP/vps-queue.sh" /usr/local/lib/scut-bond/vps-queue.sh.rollback
mv /usr/local/lib/scut-bond/vps-queue.sh.rollback /usr/local/lib/scut-bond/vps-queue.sh
tc qdisc change dev ens18 parent 1:3 handle 30: fq maxrate 50mbit quantum 1448 initial_quantum 1448
tc qdisc show dev ens18
