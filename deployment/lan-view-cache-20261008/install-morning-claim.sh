#!/bin/sh
# One-time addition after the verified LAN view deployment of 2026-10-08.
set -eu
umask 077
B=/root/scut-logout-morning-backup-20261008
T=/usr/lib/scut-multiwan/wireless-control.sh
S=/tmp/scut-logout-morning-stage/wireless-control.sh
test ! -e "$B"
test -s "$S"
sh -n "$S"
grep -q 'logout before today' "$S"
test "$(wc -c < "$S")" -gt 4000
mkdir -m 700 "$B"
cp -p "$T" "$B/wireless-control.sh"
cat > "$B/rollback.sh" <<'ROLLBACK'
#!/bin/sh
set -eu
B=/root/scut-logout-morning-backup-20261008
exec 9>>/tmp/scut-multiwan-locks/portal
n=0
while ! flock -n 9; do n=$((n+1)); test "$n" -lt 40 || exit 75; sleep 1; done
cp -p "$B/wireless-control.sh" /usr/lib/scut-multiwan/wireless-control.sh.scut-restore
mv /usr/lib/scut-multiwan/wireless-control.sh.scut-restore /usr/lib/scut-multiwan/wireless-control.sh
ROLLBACK
chmod 700 "$B/rollback.sh"
sh -n "$B/rollback.sh"
setsid sh -c 'trap "" HUP; sleep 600; test -f /root/scut-logout-morning-backup-20261008/confirmed || exec sh /root/scut-logout-morning-backup-20261008/rollback.sh' >/dev/null 2>&1 </dev/null &
echo "$!" > "$B/guard.pid"
exec 9>>/tmp/scut-multiwan-locks/portal
n=0
while ! flock -n 9; do n=$((n+1)); test "$n" -lt 40 || exit 75; sleep 1; done
cp "$S" "$T.scut-new"
chmod 755 "$T.scut-new"
sh -n "$T.scut-new"
mv "$T.scut-new" "$T"
sha256sum "$T"
