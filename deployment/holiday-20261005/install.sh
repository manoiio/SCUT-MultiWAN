#!/bin/sh
# Historical, device-specific deployment. Refuses drift or repeated installation.
set -eu
S=/tmp/scut-holiday-deploy-20261005
B=/root/scut-multiwan-holiday-backup-20261005
FLAG=/tmp/scut-multiwan-deploying
cd "$S"
test ! -e "$B"
test ! -e "$FLAG"
[ "$(date +%z)" = +0800 ]
H="$(date +%H)"; H="${H#0}"
[ "${H:-0}" -ge 7 ]
sha256sum -c candidate.sha256
while read -r mode rel; do
 test -s "$rel"
 wc -c "$rel"
 case "$rel" in usr/bin/*|etc/hotplug.d/*|usr/lib/scut-multiwan/common.sh) sh -n "$rel";; esac
done < files.list
sh -n install.sh
sh -n rollback.sh
LC_ALL=C awk -v year=2026 -f usr/lib/scut-multiwan/calendar-check.awk etc/scut-multiwan/calendar-2026.txt
grep -q '^0 7 .*FORCE_SCAN=1' etc/crontabs/root
grep -q '^13 12 1 .*scut-calendar-update' etc/crontabs/root
(cd / && sha256sum -c "$S/before.sha256")
while read -r mode rel; do
 grep -Fq "  $rel" before.sha256 || test ! -e "/$rel"
done < files.list
umask 077
mkdir -p /tmp/scut-multiwan-locks
chmod 700 /tmp/scut-multiwan-locks
exec 9>>/tmp/scut-multiwan-locks/portal
WAITED=0
while ! flock -n 9; do
 [ "$WAITED" -lt 30 ] || exit 75
 sleep 1
 WAITED=$((WAITED+1))
done
# Recheck after waiting for any running transaction.
(cd / && sha256sum -c "$S/before.sha256")
while read -r mode rel; do
 grep -Fq "  $rel" before.sha256 || test ! -e "/$rel"
done < files.list
READY=0
rollback_on_error() {
 rc=$?
 trap - EXIT
 if [ "$rc" -ne 0 ]; then
  if [ "$READY" = 1 ]; then sh "$B/rollback.sh"
  elif [ "$(cat "$FLAG/owner" 2>/dev/null)" = "$B" ]; then rm "$FLAG/owner"; rmdir "$FLAG"; fi
 fi
 exit "$rc"
}
trap rollback_on_error EXIT
mkdir "$FLAG"
printf '%s\n' "$B" > "$FLAG/owner"
mkdir "$B"
chmod 700 "$B"
: > "$B/present.list"
while read -r mode rel; do
 if [ -e "/$rel" ]; then
  mkdir -p "$B/${rel%/*}"
  cp -p "/$rel" "$B/$rel"
  printf '%s\n' "$rel" >> "$B/present.list"
 fi
done < files.list
cp before.sha256 candidate.sha256 files.list rollback.sh "$B/"
chmod 700 "$B/rollback.sh"
(cd "$B" && sha256sum -c before.sha256)
# Assert that the configuration and existing sessions remain untouched.
sha256sum /etc/config/wireless /etc/config/network /etc/config/firewall /etc/config/system /etc/campus-portal.conf /etc/scut-multiwan/native.session /etc/scut-multiwan/usb.session > "$B/unchanged.sha256"
READY=1
# Independent timer also restores the prior scripts if acceptance is lost.
cat > "$B/auto-rollback.sh" <<'AUTO'
#!/bin/sh
exec 9>&-
sleep 300
B=/root/scut-multiwan-holiday-backup-20261005
if [ -e "$B/armed" ]; then sh "$B/rollback.sh" > "$B/auto-rollback.log" 2>&1; fi
AUTO
chmod 700 "$B/auto-rollback.sh"
: > "$B/armed"
nohup sh "$B/auto-rollback.sh" </dev/null >/dev/null 2>&1 &
printf '%s\n' "$!" > "$B/timer.pid"
while read -r mode rel; do
 mkdir -p "/${rel%/*}"
 TMP="/$rel.holiday-new.$$"
 cp "$S/$rel" "$TMP"
 chmod "$mode" "$TMP"
 cmp "$S/$rel" "$TMP"
 mv -f "$TMP" "/$rel"
done < files.list
chmod 700 /etc/scut-multiwan
(cd / && sha256sum -c "$B/candidate.sha256")
sha256sum -c "$B/unchanged.sha256"
printf 'root\n' >> /etc/crontabs/cron.update
rm "$FLAG/owner"
rmdir "$FLAG"
trap - EXIT
date
echo "Deployment complete; 300-second rollback armed: $B"
