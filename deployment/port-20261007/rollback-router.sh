#!/bin/sh
set -eu
B=/root/scut-port-backup-20261007
test -s "$B/client.json"
cp -p "$B/client.json" /etc/scut-bond/client.json.rollback
mv /etc/scut-bond/client.json.rollback /etc/scut-bond/client.json
/etc/init.d/scut-bond restart
