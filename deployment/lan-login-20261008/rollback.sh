#!/bin/sh
set -eu
B=/root/scut-lan-login-backup-20261008
for rel in $(cat "$B/files.txt"); do
 if [ -f "$B/root/$rel" ]; then cp -p "$B/root/$rel" "/$rel.scut-restore"; mv "/$rel.scut-restore" "/$rel"; else rm -f "/$rel"; fi
done
cp -p "$B/crontab" /etc/crontabs/.root.scut-restore
mv /etc/crontabs/.root.scut-restore /etc/crontabs/root
if [ -f "$B/morning-enabled" ]; then cp -p "$B/morning-enabled" /etc/scut-multiwan/morning-random.enabled; else rm -f /etc/scut-multiwan/morning-random.enabled; fi
printf 'root\n' > /etc/crontabs/cron.update
/etc/init.d/rpcd restart
/usr/bin/scut-lan-mode set wired
rm -f /tmp/scut-multiwan-deploying
