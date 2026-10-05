#!/bin/sh
# Restore this deployment only; uncertain release refuses binary replacement.
set -eu
B=/root/scut-multiwan-experience-backup-20261006
[ -s "$B/files.list" ] || exit 1
exec 3>>/tmp/scut-multiwan-locks/experience-deploy
flock -n 3 || exit 75
# Installer may have failed mid-copy; let verified release guards run normally.
if [ -d /tmp/scut-multiwan-deploying ]; then rmdir /tmp/scut-multiwan-deploying; fi
/etc/init.d/scut-wired stop
/usr/bin/scutclient-wired --release
read -r current dev extra < /etc/scut-multiwan/wired.session
[ "$current" = none ] && [ "$dev" = wan ] && [ -z "$extra" ] || exit 75
. /usr/lib/scut-multiwan/common.sh
mw_lock dualwan-refresh 8
mw_lock qca-phy0-sta0 7
exec 6>>/tmp/scut-multiwan-locks/qca-phy2-sta0
flock -n 6 || exit 75
exec 5>>/tmp/scut-multiwan-locks/wired-engine
flock -n 5 || exit 75
mw_portal_lock 30 route
mkdir /tmp/scut-multiwan-deploying
trap 'rmdir /tmp/scut-multiwan-deploying 2>/dev/null || true' EXIT
while read -r f; do
 if [ -f "$B/files$f" ]; then
  cp -p "$B/files$f" "$f.experience-restore"
  mv "$f.experience-restore" "$f"
 elif grep -Fxq "$f" "$B/absent.list"; then rm -f "$f"
 else exit 1; fi
done < "$B/files.list"
# Keep legitimate excess counts readable at 07:00; never restore/reset budgets.
read -r stamp count last block extra < /etc/scut-multiwan/wired.night-budget
case "$count" in 3|4)
 sed 's/\[ "$count" -le 2 \]/[ "$count" -le 4 ]/' /usr/bin/scut-wired-gate > /usr/bin/scut-wired-gate.experience-compat
 chmod 755 /usr/bin/scut-wired-gate.experience-compat
 sh -n /usr/bin/scut-wired-gate.experience-compat
 mv /usr/bin/scut-wired-gate.experience-compat /usr/bin/scut-wired-gate;;
esac
cp -p "$B/root.cron" /etc/crontabs/root.experience-restore
mv /etc/crontabs/root.experience-restore /etc/crontabs/root
rm -f /etc/scut-multiwan/wired.limit-override
printf 'root\n' >> /etc/crontabs/cron.update
sha256sum -c "$B/preserved.sha256"
rmdir /tmp/scut-multiwan-deploying
trap - EXIT
rm -f "$B/armed"
exec 9>&- 8>&- 7>&- 6>&- 5>&- 3>&-
/etc/init.d/scut-wired start
/usr/bin/dualwan-refresh force
logger -t scut-multiwan 'experience rollback complete; excess budget retained; wired may wait until 07:00'
date
echo EXPERIENCE_ROLLED_BACK
