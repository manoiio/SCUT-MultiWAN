#!/bin/sh
# One-time installer bound to the inspected 2026-10-09 evening baseline.
set -eu
umask 077
B=/root/scut-remote-release-backup-20261009
S=/tmp/scut-remote-release-stage
sha256sum -c "$S/baseline.sha256"
test ! -e "$B"
test ! -e /usr/lib/scut-multiwan/remote-release.sh
while IFS= read -r file; do test -s "$S/$file"; sh -n "$S/$file"; done < "$S/files.txt"
mkdir -m 700 "$B"
cp "$S/files.txt" "$B/files.txt"
for file in usr/bin/campus-portal-logout.impl usr/bin/campus-usb-logout.impl; do
 mkdir -p "$B/$(dirname "$file")"; cp -p "/$file" "$B/$file"
done
cp "$S/rollback.sh" "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
sh -n "$B/rollback.sh"
setsid sh -c 'trap "" HUP; sleep 600; test -f /root/scut-remote-release-backup-20261009/confirmed || exec sh /root/scut-remote-release-backup-20261009/rollback.sh' > "$B/guard.log" 2>&1 </dev/null &
echo "$!" > "$B/guard.pid"
exec 9>>/tmp/scut-multiwan-locks/portal
n=0
while ! flock -n 9; do n=$((n+1)); test "$n" -lt 50 || exit 75; sleep 1; done
sha256sum -c "$S/baseline.sha256"
touch /tmp/scut-multiwan-deploying
trap 'rm -f /tmp/scut-multiwan-deploying' EXIT
while IFS= read -r file; do
 cp "$S/$file" "/$file.scut-new"
 case "$file" in usr/bin/*) chmod 755 "/$file.scut-new";; *) chmod 644 "/$file.scut-new";; esac
 mv "/$file.scut-new" "/$file"
done < "$S/files.txt"
while IFS= read -r file; do cmp -s "$S/$file" "/$file"; done < "$S/files.txt"
rm -f /tmp/scut-multiwan-deploying
trap - EXIT
flock -u 9
printf 'remote-release-installed\n'
