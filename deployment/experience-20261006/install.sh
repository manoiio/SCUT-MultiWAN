#!/bin/sh
# Bound to this observed baseline; do not rerun after successful deployment.
set -eu
S=/tmp/scut-experience-deploy-20261006
B=/root/scut-multiwan-experience-backup-20261006
[ ! -e "$B" ] && [ ! -e /tmp/scut-multiwan-deploying ] || exit 75
exec 3>>/tmp/scut-multiwan-locks/experience-deploy
flock -n 3 || exit 75
(cd / && sha256sum -c "$S/production-before.sha256")
(cd "$S/files" && sha256sum -c "$S/candidate.sha256")
while read -r f; do
 [ -s "$S/files$f" ] || exit 1
 [ "$f" = /usr/bin/scutclient-wired ] || sh -n "$S/files$f"
 wc -c "$S/files$f"
done < "$S/files.list"
sh -n "$S/rollback.sh"
"$S/files/usr/bin/scutclient-wired" --version
. /usr/lib/scut-multiwan/common.sh
mw_require_active 60
umask 077
mkdir "$B"
mkdir "$B/files"
cp "$S/files.list" "$B/files.list"
cp "$S/rollback.sh" "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
: > "$B/absent.list"
while read -r f; do
 if [ -f "$f" ]; then mkdir -p "$B/files$(dirname "$f")"; cp -p "$f" "$B/files$f"
 else printf '%s\n' "$f" >> "$B/absent.list"; fi
done < "$S/files.list"
cp -p /etc/crontabs/root "$B/root.cron"
cp "$S/production-before.sha256" "$B/before.sha256"
sha256sum /etc/config/network /etc/config/wireless /etc/config/firewall /etc/config/system /etc/campus-portal.conf /etc/scut-wired.conf /etc/scut-multiwan/native.session /etc/scut-multiwan/usb.session > "$B/preserved.sha256"
cp -p /etc/scut-multiwan/wired.night-budget "$B/wired-budget.before"
# Keep the occupied-session journal on device, never include it in payloads.
cp -p /etc/scut-multiwan/wired.session "$B/wired-session.before"
cp -p /etc/crontabs/root "$S/root.cron.new"
for entry in '* 7-23 * * * /usr/bin/scut-rate-watchdog >/dev/null 2>&1' '0 7 * * * /usr/bin/scut-wired-morning >/dev/null 2>&1'; do
 grep -Fxq "$entry" "$S/root.cron.new" || printf '%s\n' "$entry" >> "$S/root.cron.new"
done
printf 'armed\n' > "$B/armed"
# Disarm only after a separate live verification. No SSH channel/lock inherited.
nohup sh -c 'sleep 300; [ ! -f "$1/armed" ] || sh "$1/rollback.sh"' sh "$B" > "$B/automatic-rollback.log" 2>&1 < /dev/null 3>&- &
# Release current engine BEFORE replacing its executable or holding Portal lock.
/etc/init.d/scut-wired stop
/usr/bin/scutclient-wired --release
read -r old dev extra < /etc/scut-multiwan/wired.session
[ "$old" = none ] && [ "$dev" = wan ] && [ -z "$extra" ] || exit 75
exec 5>>/tmp/scut-multiwan-locks/wired-engine
flock -n 5 || exit 75
mw_lock dualwan-refresh 8
mw_lock qca-phy0-sta0 7
exec 6>>/tmp/scut-multiwan-locks/qca-phy2-sta0
flock -n 6 || exit 75
mw_portal_lock 30 route
(cd / && sha256sum -c "$S/production-before.sha256")
sha256sum -c "$B/preserved.sha256"
mkdir /tmp/scut-multiwan-deploying
trap 'rmdir /tmp/scut-multiwan-deploying 2>/dev/null || true' EXIT
while read -r f; do
 cp "$S/files$f" "$f.experience-new"
 chmod 755 "$f.experience-new"
 cmp "$S/files$f" "$f.experience-new"
 [ "$f" = /usr/bin/scutclient-wired ] || sh -n "$f.experience-new"
 mv "$f.experience-new" "$f"
done < "$S/files.list"
cp "$S/root.cron.new" /etc/crontabs/root.experience-new
chmod 600 /etc/crontabs/root.experience-new
mv /etc/crontabs/root.experience-new /etc/crontabs/root
# Approved only for this date; does not alter count/last/block.
printf '%s 4\n' "$(date +%Y-%m-%d)" > /etc/scut-multiwan/wired.limit-override.new
chmod 600 /etc/scut-multiwan/wired.limit-override.new
mv /etc/scut-multiwan/wired.limit-override.new /etc/scut-multiwan/wired.limit-override
(cd / && sha256sum -c "$S/candidate.sha256")
sha256sum -c "$B/preserved.sha256"
printf 'root\n' >> /etc/crontabs/cron.update
rmdir /tmp/scut-multiwan-deploying
trap - EXIT
exec 9>&- 8>&- 7>&- 6>&- 5>&- 3>&-
/etc/init.d/scut-wired start
printf 'installed\n' > "$B/installed"
logger -t scut-multiwan 'network-experience candidate installed; temporary wired cap 4, verification pending'
date
echo EXPERIENCE_INSTALLED_ROLLBACK_ARMED
