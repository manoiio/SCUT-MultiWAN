#!/bin/sh
set -eu
B=/root/scut-lan-view-cache-backup-20261008
exec 9>>/tmp/scut-multiwan-locks/portal
n=0
while ! flock -n 9; do n=$((n+1)); [ "$n" -lt 40 ] || exit 75; sleep 1; done
for name in wireless-control.sh scut-lan-links; do
 if [ -f "$B/$name" ]; then
  case "$name" in wireless-control.sh) target=/usr/lib/scut-multiwan/wireless-control.sh;; *) target=/usr/bin/scut-lan-links;; esac
  cp -p "$B/$name" "$target.scut-restore"
  mv "$target.scut-restore" "$target"
 fi
done
cp -p "$B/canonical.js" /www/luci-static/resources/view/network/scut_lan.js.scut-restore
mv /www/luci-static/resources/view/network/scut_lan.js.scut-restore /www/luci-static/resources/view/network/scut_lan.js
cp -p "$B/menu.json" /usr/share/luci/menu.d/luci-app-scut-lan.json.scut-restore
mv /usr/share/luci/menu.d/luci-app-scut-lan.json.scut-restore /usr/share/luci/menu.d/luci-app-scut-lan.json
if [ -f /tmp/luci-indexcache.795b10fe.json ]; then
 mv /tmp/luci-indexcache.795b10fe.json "$B/indexcache-before-rollback.json"
fi
