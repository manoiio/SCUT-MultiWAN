#!/bin/sh
# One-time installer bound to the inspected 2026-10-09 baseline.
set -eu
umask 077
B=/root/scut-morning-retry-backup-20261009
S=/tmp/scut-morning-retry-stage
test ! -e "$B"
sha256sum -c "$S/baseline.sha256"
while IFS= read -r file; do
    test -s "$S/$file"
    case "$file" in usr/*) case "$file" in *.json) ;; *) sh -n "$S/$file";; esac;; esac
done < "$S/files.txt"
mkdir -m 700 "$B"
cp "$S/files.txt" "$B/files.txt"
while IFS= read -r file; do
    mkdir -p "$B/$(dirname "$file")"
    if [ -f "/$file" ]; then cp -p "/$file" "$B/$file"; else printf '%s\n' "$file" >> "$B/absent.txt"; fi
done < "$S/files.txt"
cp -p /etc/crontabs/root "$B/crontab"
cp "$S/rollback.sh" "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
sh -n "$B/rollback.sh"
setsid sh -c 'trap "" HUP; sleep 600; test -f /root/scut-morning-retry-backup-20261009/confirmed || exec sh /root/scut-morning-retry-backup-20261009/rollback.sh' > "$B/guard.log" 2>&1 </dev/null &
echo "$!" > "$B/guard.pid"
exec 9>>/tmp/scut-multiwan-locks/portal
n=0
while ! flock -n 9; do n=$((n+1)); test "$n" -lt 50 || exit 75; sleep 1; done
touch /tmp/scut-multiwan-deploying
trap 'rm -f /tmp/scut-multiwan-deploying' EXIT
while IFS= read -r file; do
    cp "$S/$file" "/$file.scut-new"
    case "$file" in usr/bin/*) chmod 755 "/$file.scut-new";; *) chmod 644 "/$file.scut-new";; esac
    mv "/$file.scut-new" "/$file"
done < "$S/files.txt"
# Existing precise 07:00 scheduling is retained; this only supplies bounded retries.
sed '\|/usr/bin/scut-morning-start retry|d' "$B/crontab" > /etc/crontabs/root.scut-new
printf '%s\n' '*/5 7-8 * * * /usr/bin/scut-morning-start retry >/dev/null 2>&1' >> /etc/crontabs/root.scut-new
chmod 600 /etc/crontabs/root.scut-new
mv /etc/crontabs/root.scut-new /etc/crontabs/root
printf 'root\n' > /var/spool/cron/crontabs/cron.update
if [ -f /tmp/luci-indexcache.795b10fe.json ]; then mv /tmp/luci-indexcache.795b10fe.json "$B/menu-index.json"; fi
while IFS= read -r file; do cmp -s "$S/$file" "/$file"; done < "$S/files.txt"
rm -f /tmp/scut-multiwan-deploying
trap - EXIT
flock -u 9
echo morning-retry-installed
