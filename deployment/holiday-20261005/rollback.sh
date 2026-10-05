#!/bin/sh
# Device-specific rollback: only the 18 targets in this deployment manifest.
set -eu
B=/root/scut-multiwan-holiday-backup-20261005
FLAG=/tmp/scut-multiwan-deploying
(cd "$B" && sha256sum -c before.sha256)
mkdir -p /tmp/scut-multiwan-locks
chmod 700 /tmp/scut-multiwan-locks
if [ "$(readlink /proc/self/fd/9 2>/dev/null)" != /tmp/scut-multiwan-locks/portal ]; then
 exec 9>>/tmp/scut-multiwan-locks/portal
 WAITED=0
while ! flock -n 9; do
 [ "$WAITED" -lt 30 ] || exit 75
 sleep 1
 WAITED=$((WAITED+1))
done
fi
if [ -e "$FLAG" ]; then
 [ "$(cat "$FLAG/owner" 2>/dev/null)" = "$B" ] || exit 75
else mkdir "$FLAG"; printf '%s\n' "$B" > "$FLAG/owner"; fi
while read -r mode rel; do
 if grep -Fxq "$rel" "$B/present.list"; then
  cp -p "$B/$rel" "/$rel.holiday-rollback.$$"
  mv -f "/$rel.holiday-rollback.$$" "/$rel"
 else
  # Only explicitly absent-at-backup targets; no Portal/session journal removal.
  rm -f "/$rel"
 fi
done < "$B/files.list"
(cd / && sha256sum -c "$B/before.sha256")
printf 'root\n' >> /etc/crontabs/cron.update
rm -f "$B/armed"
rm "$FLAG/owner"
rmdir "$FLAG"
date
echo 'Holiday policy rolled back to the prior daily quiet policy'
