#!/bin/sh
set -eu
umask 077
S=/tmp/scut-recovery-20261007
B=/root/scut-multiwan-recovery-backup-20261007
cd "$S"
sha256sum -c candidate.sha256
for f in native-best native-watchdog; do test -s "$f"; wc -c "$f"; sh -n "$f"; done
sh -n rollback.sh
dnsmasq --test --conf-file="$S/dnsmasq-wan-bound.conf"
. /usr/lib/scut-multiwan/common.sh
mw_require_scan 60
exec 5>>/tmp/scut-multiwan-locks/native-watchdog; flock -n 5 || exit 75
exec 6>>/tmp/scut-multiwan-locks/native-best; flock -n 6 || exit 75
exec 3>>/tmp/scut-multiwan-locks/dualwan-refresh; flock -n 3 || exit 75
exec 7>>/tmp/scut-multiwan-locks/qca-phy0-sta0; flock -n 7 || exit 75
exec 8>>/tmp/scut-multiwan-locks/qca-phy2-sta0; flock -n 8 || exit 75
mw_portal_lock 10
sha256sum -c "$S/baseline.sha256"
test ! -e "$B"
mkdir -m 700 "$B"
cp -p /usr/bin/native-best /usr/bin/native-watchdog "$B/"
cp -p /etc/config/dhcp "$B/dhcp"
cp "$S/rollback.sh" "$B/rollback.sh"; chmod 700 "$B/rollback.sh"
sha256sum /etc/config/network /etc/config/wireless /etc/config/firewall /etc/config/system /etc/campus-portal.conf /etc/scut-wired.conf /etc/crontabs/root /etc/scut-multiwan/*.session /etc/scut-multiwan/*.night-budget > "$B/preserved.sha256"
(cd "$B"; sha256sum native-best native-watchdog dhcp > original.sha256)
mkdir /tmp/scut-multiwan-deploying
DONE=0
cleanup() {
 r=$?; trap - EXIT INT TERM HUP
 if [ "$DONE" = 0 ]; then
  for f in native-best native-watchdog; do cp -p "$B/$f" "/usr/bin/$f.recovery-restore.$$"; mv "/usr/bin/$f.recovery-restore.$$" "/usr/bin/$f"; done
  cp -p "$B/dhcp" /etc/config/dhcp.recovery-restore; mv /etc/config/dhcp.recovery-restore /etc/config/dhcp
  /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
 fi
 rmdir /tmp/scut-multiwan-deploying
 exit "$r"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
mkdir -p "$S/config"
cp -p /etc/config/dhcp "$S/config/dhcp"
uci -c "$S/config" set dhcp.@dnsmasq[0].allservers=1
# Baseline has no user server overrides. Preserve the other DHCP/DNS options.
for server in 222.201.130.30@wan 222.201.130.33@wan 10.6.6.6@phy3-sta0 10.5.5.5@phy3-sta0; do
 uci -c "$S/config" add_list dhcp.@dnsmasq[0].server="$server"
done
uci -c "$S/config" commit dhcp
for f in native-best native-watchdog; do
 cp "$S/$f" "/usr/bin/$f.recovery-new.$$"; chmod 755 "/usr/bin/$f.recovery-new.$$"
 cmp "$S/$f" "/usr/bin/$f.recovery-new.$$"; sh -n "/usr/bin/$f.recovery-new.$$"
 mv "/usr/bin/$f.recovery-new.$$" "/usr/bin/$f"
done
cp -p "$S/config/dhcp" /etc/config/dhcp.recovery-new
cmp "$S/config/dhcp" /etc/config/dhcp.recovery-new
mv /etc/config/dhcp.recovery-new /etc/config/dhcp
/etc/init.d/dnsmasq restart >/dev/null 2>&1
sha256sum -c "$B/preserved.sha256"
sha256sum /usr/bin/native-best /usr/bin/native-watchdog /etc/config/dhcp > "$B/installed.sha256"
DONE=1
date; echo RECOVERY_FIX_INSTALLED
