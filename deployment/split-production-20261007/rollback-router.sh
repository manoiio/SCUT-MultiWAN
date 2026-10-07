#!/bin/sh
set -eu
B=/root/scut-split-production-backup-20261007
test -s "$B/scut-bond"
test -s "$B/client.json"
test -s "$B/scut-bond-paths"
/etc/init.d/scut-bond stop
for f in scut-bond client.json scut-bond-paths; do
 case "$f" in
  scut-bond) target=/usr/bin/scut-bond;;
  client.json) target=/etc/scut-bond/client.json;;
  scut-bond-paths) target=/usr/bin/scut-bond-paths;;
 esac
 cp -p "$B/$f" "$target.rollback"
 mv "$target.rollback" "$target"
done
rm -f /etc/scut-bond/mixed.enabled
/etc/init.d/scut-bond start
sha256sum -c "$B/before.sha256"
