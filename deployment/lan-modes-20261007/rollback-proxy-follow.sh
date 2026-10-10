#!/bin/sh
set -eu
B=/root/scut-lan-proxy-backup-20261007
/etc/init.d/scut-bond stop
cp -p "$B/scut-bond" /usr/bin/.scut-bond-lan.restore
mv /usr/bin/.scut-bond-lan.restore /usr/bin/scut-bond
cp -p "$B/client.json" /etc/scut-bond/.client-lan.restore.json
mv /etc/scut-bond/.client-lan.restore.json /etc/scut-bond/client.json
cp -p "$B/scut-lan-mode" /usr/bin/.scut-lan-mode.restore
mv /usr/bin/.scut-lan-mode.restore /usr/bin/scut-lan-mode
for table in 103 106; do ip -4 rule del pref 94 fwmark 0x5343 lookup "$table" >/dev/null 2>&1 || :; done
/etc/init.d/scut-bond start
