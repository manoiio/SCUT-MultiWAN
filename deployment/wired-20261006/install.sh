#!/bin/sh
# Historical, baseline-bound deployment. Auth remains disabled until acceptance.
set -eu
S=/tmp/scut-wired-deploy-20261006
B=/root/scut-multiwan-wired-backup-20261006
[ ! -e "$B" ] && [ ! -e /tmp/scut-multiwan-deploying ] || exit 75
cd "$S"
sha256sum -c candidate.sha256
for f in usr/bin/scut-wired-gate usr/lib/scut-multiwan/wired-run etc/init.d/scut-wired usr/bin/dualwan-refresh etc/hotplug.d/iface/95-dualwan-refresh; do
    [ -s "root/$f" ] && sh -n "root/$f" || exit 1
done
[ "$(sha256sum /etc/config/network | awk '{print $1}')" = bfb859e538671ca2d34cef53641267cbd96a860484865e0a7b3e2a4d155dd285 ] || exit 75
[ "$(sha256sum /usr/bin/dualwan-refresh | awk '{print $1}')" = 8621b826ca6f926d57dfeeeaf6c57ffc38ab79ad5f1a3eb12a9c617241b034a1 ] || exit 75
[ "$(sha256sum /etc/hotplug.d/iface/95-dualwan-refresh | awk '{print $1}')" = 11c522643232df687caa2dd4032c8832429a246bcb8046e962e6bafd6dbc5df7 ] || exit 75
./root/usr/bin/scutclient-wired --version
. /usr/lib/scut-multiwan/common.sh
mw_require_active 120 || exit $?
mw_portal_lock 0 || exit $?
umask 077
mkdir -p "$B/files"
chmod 700 "$B"
cp files.list "$B/files.list"
cp rollback.sh "$B/rollback.sh"
chmod 700 "$B/rollback.sh"
: > "$B/absent.list"
while read -r target; do
    if [ -f "$target" ]; then
        mkdir -p "$B/files${target%/*}"
        cp -p "$target" "$B/files$target"
    else printf '%s\n' "$target" >> "$B/absent.list"; fi
done < files.list
sha256sum /etc/config/wireless /etc/config/firewall /etc/campus-portal.conf /etc/scut-multiwan/native.session /etc/scut-multiwan/usb.session /etc/crontabs/root > "$B/preserved.sha256"
mkdir -p "$S/config"
cp -p /etc/config/network "$S/config/network"
uci -c "$S/config" set network.wan.proto=static
uci -c "$S/config" set network.wan.ipaddr=110.64.88.149
uci -c "$S/config" set network.wan.netmask=255.255.255.0
uci -c "$S/config" set network.wan.gateway=110.64.88.254
uci -c "$S/config" set network.wan.metric=600
uci -c "$S/config" set network.wan.dns_metric=600
uci -c "$S/config" set network.wan.force_link=0
uci -c "$S/config" set network.wan.peerdns=1
uci -c "$S/config" -q delete network.wan.dns || true
uci -c "$S/config" add_list network.wan.dns=222.201.130.30
uci -c "$S/config" add_list network.wan.dns=222.201.130.33
uci -c "$S/config" commit network
cp -p "$S/config/network" root/etc/config/network
touch "$B/armed" /tmp/scut-multiwan-deploying
(exec 7>&- 8>&- 9>&-; sleep 300; [ ! -e "$B/armed" ] || sh "$B/rollback.sh") > "$B/auto-rollback.log" 2>&1 &
trap 'rm -f /tmp/scut-multiwan-deploying; exec 9>&-; sh "$B/rollback.sh"' EXIT
while read -r target; do
    [ -s "$S/root$target" ] || exit 1
    mkdir -p "${target%/*}"
    cp "$S/root$target" "$target.wired-new"
    case "$target" in /etc/config/network|/etc/scut-wired.conf) chmod 600 "$target.wired-new";; *) chmod 755 "$target.wired-new";; esac
    cmp "$S/root$target" "$target.wired-new"
    mv "$target.wired-new" "$target"
done < files.list
if [ ! -e /etc/scut-multiwan/wired.session ]; then
    printf 'none wan\n' > /etc/scut-multiwan/wired.session
fi
if [ ! -e /etc/scut-multiwan/wired.night-budget ]; then
    printf 'none 0 0 0\n' > /etc/scut-multiwan/wired.night-budget
fi
chmod 600 /etc/scut-multiwan/wired.session /etc/scut-multiwan/wired.night-budget
ubus call network reload
sleep 3
[ "$(ip -4 -o addr show dev wan | awk '{print $4; exit}')" = 110.64.88.149/24 ] || exit 1
sha256sum -c "$B/preserved.sha256"
rm -f /tmp/scut-multiwan-deploying
exec 9>&-
/usr/bin/dualwan-refresh apply
rm -f "$B/armed"
trap - EXIT
echo wired-static-installed-auth-disabled
