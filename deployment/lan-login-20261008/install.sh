#!/bin/sh
set -eu
umask 077
command -v setsid >/dev/null || exit 1
B=/root/scut-lan-login-backup-20261008
S=/tmp/scut-lan-login-stage-20261008
test ! -e "$B"
mkdir -m 700 "$B"
cp "$S/files.txt" "$B/files.txt"
while read -r rel; do
 if [ -f "/$rel" ]; then mkdir -p "$B/root/${rel%/*}"; cp -p "/$rel" "$B/root/$rel"; fi
done < "$S/files.txt"
cp -p /etc/crontabs/root "$B/crontab"
[ ! -f /etc/scut-multiwan/morning-random.enabled ] || cp -p /etc/scut-multiwan/morning-random.enabled "$B/morning-enabled"
cp "$S/rollback.sh" "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
cat > "$B/guard.sh" <<'GUARD'
#!/bin/sh
sleep 900
[ -f /root/scut-lan-login-backup-20261008/confirmed ] || exec sh /root/scut-lan-login-backup-20261008/rollback.sh
GUARD
chmod 700 "$B/guard.sh"
setsid sh -c 'trap "" HUP; exec "$@"' sh sh "$B/guard.sh" > "$B/guard.log" 2>&1 </dev/null &
echo "$!" > "$B/guard.pid"
touch /tmp/scut-multiwan-deploying
# Quiesce Portal transactions; never terminate a running authentication.
. /usr/lib/scut-multiwan/common.sh
exec 9>>/tmp/scut-multiwan-locks/portal
n=0
while ! flock -n 9; do n=$((n+1)); [ "$n" -lt 40 ] || exit 75; sleep 1; done
while read -r rel; do
 test -s "$S/root/$rel"
 case "$rel" in *.js|*.json) ;; *) sh -n "$S/root/$rel";; esac
 dir=${rel%/*}; mkdir -p "/$dir"
 cp "$S/root/$rel" "/$rel.scut-new"
 case "$rel" in *.js|*.json) chmod 644 "/$rel.scut-new";; *) chmod 755 "/$rel.scut-new";; esac
 mv "/$rel.scut-new" "/$rel"
done < "$S/files.txt"
printf '1\n' > /etc/scut-multiwan/morning-random.enabled
chmod 600 /etc/scut-multiwan/morning-random.enabled
awk '!($1=="0"&&$2=="7"&&$0~/FORCE_SCAN=1 \/usr\/bin\/native-watchdog/)&&!($1=="1"&&$2=="7"&&$0~/\/usr\/bin\/usb-watchdog/)&&!($1=="2"&&$2=="7"&&$0~/\/usr\/bin\/dualwan-refresh/)&&!($1=="0"&&$2=="7"&&$0~/\/usr\/bin\/scut-wired-morning/){print}' /etc/crontabs/root > /etc/crontabs/.root.scut-new
printf '0 7 * * * /usr/bin/scut-morning-start schedule >/dev/null 2>&1\n' >> /etc/crontabs/.root.scut-new
chmod 600 /etc/crontabs/.root.scut-new
mv /etc/crontabs/.root.scut-new /etc/crontabs/root
printf 'root\n' > /etc/crontabs/cron.update
exec 9>&-
rm -f /tmp/scut-multiwan-deploying
/etc/init.d/rpcd restart
/usr/bin/scut-lan-mode set wired
/usr/bin/scut-lan-links status
sha256sum /usr/bin/scut-lan-mode /usr/bin/scut-lan-links /usr/bin/scut-morning-start
