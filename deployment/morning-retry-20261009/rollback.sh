#!/bin/sh
set -eu
umask 077
B=/root/scut-morning-retry-backup-20261009
exec 9>>/tmp/scut-multiwan-locks/portal
n=0
while ! flock -n 9; do n=$((n+1)); test "$n" -lt 50 || exit 75; sleep 1; done
touch /tmp/scut-multiwan-deploying
trap 'rm -f /tmp/scut-multiwan-deploying' EXIT
while IFS= read -r file; do
    # Leave newly introduced immutable JS as an unused resource for open clients.
    [ -f "$B/$file" ] || continue
    cp -p "$B/$file" "/$file.scut-restore"
    mv "/$file.scut-restore" "/$file"
done < "$B/files.txt"
cp -p "$B/crontab" /etc/crontabs/root.scut-restore
mv /etc/crontabs/root.scut-restore /etc/crontabs/root
printf 'root\n' > /var/spool/cron/crontabs/cron.update
if [ -f /tmp/luci-indexcache.795b10fe.json ]; then mv /tmp/luci-indexcache.795b10fe.json "$B/menu-index-before-rollback.json"; fi
# No session journal, pause, cancellation or attempt counter is deleted.
rm -f /tmp/scut-multiwan-deploying
trap - EXIT
